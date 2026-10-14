function RegistryBoundaryObject(kind as string, name="" as string) as object
    if kind="roRegistry"
        return {GetSectionList:function() as object
            return ["auth","settings","addons","library","playbackMemory"]
        end function}
    end if
    if kind="roRegistrySection" then return m.sections[name]
    return CreateObject(kind)
end function
function AcquisitionEventType(event as dynamic) as string
    if event=invalid then return "Invalid"
    return "roUrlEvent"
end function
function AcquisitionWrite(path as string, payload as string) as boolean
    m.acquisition.files[path]={size:Len(payload),body:payload}
    return true
end function
function AcquisitionRead(path as string) as string
    m.acquisition.reads=m.acquisition.reads+1
    return m.acquisition.files[path].body
end function
function AcquisitionWait(milliseconds as integer, port as dynamic) as dynamic
    m.acquisition.elapsed=m.acquisition.elapsed+milliseconds
    if m.acquisition.complete<>true then return invalid
    return {code:m.acquisition.status,GetResponseCode:function() as integer
        return m.code
    end function}
end function
function AcquisitionObject(kind as string) as object
    if kind="roMessagePort" then return {}
    if kind="roTimespan"
        return {state:m.acquisition,Mark:sub()
            m.state.elapsed=0
        end sub,TotalMilliseconds:function() as integer
            return m.state.elapsed
        end function}
    end if
    if kind="roFileSystem"
        return {state:m.acquisition,Stat:function(path as string) as dynamic
            return m.state.files[path]
        end function,Delete:function(path as string) as boolean
            m.state.deleted.Push(path)
            m.state.files.Delete(path)
            return true
        end function}
    end if
    return {state:m.acquisition,GetIdentity:function() as integer
        return 7
    end function,SetMessagePort:sub(port as object)
    end sub,SetCertificatesFile:sub(file as string)
    end sub,EnablePeerVerification:sub(value as boolean)
    end sub,EnableHostVerification:sub(value as boolean)
    end sub,EnableEncodings:sub(value as boolean)
        m.state.decoding=value
    end sub,SetUrl:sub(url as string)
    end sub,SetHeaders:sub(headers as object)
    end sub,RetainBodyOnError:sub(value as boolean)
    end sub,AsyncGetToFile:function(output as string) as boolean
        m.state.method="GET":m.state.issued=m.state.issued+1
        m.state.files[output]={size:m.state.decodedSize,body:m.state.body}
        return true
    end function,AsyncPostFromFileToFile:function(inputFile as string,output as string) as boolean
        m.state.method="POST":m.state.issued=m.state.issued+1
        m.state.postPayload=m.state.files[inputFile].body
        m.state.files[output]={size:m.state.decodedSize,body:m.state.body}
        return true
    end function,AsyncHead:function() as boolean
        m.state.method="HEAD":m.state.issued=m.state.issued+1
        return true
    end function,AsyncCancel:sub()
        m.state.cancelled=true
    end sub}
end function
sub AcquisitionSetup(size as integer, complete=true as boolean)
    m.acquisition={files:{},deleted:[],reads:0,issued:0,elapsed:0,decodedSize:size,body:"{}",complete:complete,status:200,cancelled:false}
end sub

Harness_Suite("Whole-registry budget includes every section and preserves good data")
m.sections={}
for each name in ["auth","settings","addons","library","playbackMemory"]
    m.sections[name]=MockRegistry()
end for
m.sections.auth.Write("session",String(10000,"a"))
m.sections.addons.Write("providers",String(10000,"b"))
m.sections.playbackMemory.Write("outcomes",String(10000,"c"))
io=RegistryIO(m.sections.library,"library")
Harness_Ok(not io.Write("library",String(1000,"d")),"source memory/auth/addon bytes count toward library admission")
Harness_Ok(not io.Flush(),"global-budget refusal cannot be acknowledged")
Harness_Equal(m.sections.library.Read("library"),"","refused value not buffered")
Harness_Ok(io.Write("library",String(200,"d")),"small replacement within global budget accepted")
Harness_Ok(io.Flush(),"small global-budget transaction acknowledged")
good=m.sections.library.Read("library")
Harness_Ok(io.Write("library","new"),"first member of multi-key transaction fits")
Harness_Ok(not io.Write("second",String(2000,"e")),"later member exceeds shared budget")
Harness_Ok(not io.Flush(),"partially refused transaction not flushed")
Harness_Equal(m.sections.library.Read("library"),good,"first member restored after later refusal")
Harness_Equal(m.sections.library.durable.library,good,"previous durable snapshot preserved")

Harness_Suite("Decoded file acquisition rejects excess data before string allocation")
AcquisitionSetup(1048577)
client=AcquisitionClient()
result=client._attempt({method:"GET",url:"https://example.invalid/stream/movie/A.json",timeoutMs:500})
Harness_Ok(not result.ok,"oversized source response fails controllably")
Harness_Equal(m.acquisition.reads,0,"oversized response never read into an application string")
Harness_Ok(m.acquisition.cancelled,"oversized transfer cancelled")
Harness_Equal(m.acquisition.files.Count(),0,"temporary input/output paths cleaned")
AcquisitionSetup(131073)
m.acquisition.wireBytes=100
result=client._attempt({method:"GET",url:"https://example.invalid/subtitles/movie/A.json",timeoutMs:500})
Harness_Ok(not result.ok,"small compressed wire size cannot bypass decoded file limit")
Harness_Ok(m.acquisition.decoding,"native content decoding enabled before file transfer")
Harness_Equal(m.acquisition.reads,0,"oversized decoded content never parsed")
AcquisitionSetup(2)
result=client._attempt({method:"POST",url:"https://example.invalid/api/test",body:{value:true},timeoutMs:500})
Harness_Ok(result.ok,"bounded POST file response succeeds")
Harness_Equal(m.acquisition.method,"POST","POST uses file-to-file native API")
Harness_Equal(ParseJson(m.acquisition.postPayload).value,true,"POST body preserved")
Harness_Equal(m.acquisition.reads,1,"valid response read once after size check")
Harness_Equal(m.acquisition.files.Count(),0,"POST request body removed after transfer")
AcquisitionSetup(2,false)
result=client._attempt({method:"GET",url:"https://example.invalid/manifest.json",timeoutMs:100})
Harness_Ok(not result.ok,"unfinished request has a bounded deadline")
Harness_Ok(m.acquisition.cancelled,"deadline cancels transfer")
AcquisitionSetup(0)
result=client._attempt({method:"HEAD",url:"https://example.invalid/movie.mkv",timeoutMs:100})
Harness_Ok(result.ok,"HEAD does not require an output file")
Harness_Equal(m.acquisition.reads,0,"HEAD cannot download/read a movie body")

Harness_Suite("Uncertain POST completion does not duplicate a server-side write")
client.applied=0
client._attempt=function(request as object) as object
    m.applied=m.applied+1
    return {ok:false,status:-56,body:"",error:"receive failed after write"}
end function
result=client._execute({method:"POST",url:"https://example.invalid/api/write"})
Harness_Equal(client.applied,1,"receive failure after applied POST is not automatically replayed")
Harness_Ok(not result.ok,"uncertain completion remains failed for explicit reconciliation")

print "Assertions passed: ";m.passed;" failed: ";m.failed
if m.failed=0 then print "RESULT: PASS" else print "RESULT: FAIL":stop
