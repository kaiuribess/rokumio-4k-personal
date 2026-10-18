' Only Roku I/O is replaced. The production store, resolver, byte parser,
' player result callback and native content handoff all run below.
function NativeBoundaryObject(kind as string, first = "" as string, second = "" as string) as object
    if kind = "roRegex" then return CreateObject(kind,first,second)
    if kind = "roMessagePort" then return {}
    if kind = "roFileSystem"
        return {state:m.nativeBoundary,Stat:function(path as string) as object
            return {size:m.state.size}
        end function,Delete:function(path as string) as boolean
            m.state.deleted.Push(path)
            return true
        end function}
    end if
    if kind = "roUrlTransfer"
        if m.nativeBoundary.failFactory = true then return invalid
        return {state:m.nativeBoundary,SetMessagePort:sub(port as object)
        end sub,SetCertificatesFile:sub(path as string)
        end sub,EnablePeerVerification:sub(value as boolean)
            m.state.verifyPeer = value
        end sub,EnableHostVerification:sub(value as boolean)
            m.state.verifyHost = value
        end sub,SetUrl:sub(url as string)
            m.state.url = url
        end sub,AddHeader:sub(name as string,value as string)
            m.state.headers[LCase(name)] = value
        end sub,AsyncGetToFile:function(path as string) as boolean
            m.state.issued = m.state.issued + 1
            return m.state.starts
        end function,AsyncCancel:sub()
            m.state.cancelled = true
        end sub}
    end if
    return CreateObject(kind)
end function

function NativeBoundaryEventType(event as dynamic) as string
    if event = invalid then return "Invalid"
    return "roUrlEvent"
end function

function NativeBoundaryWait(milliseconds as integer, port as object) as dynamic
    m.nativeBoundary.waits = m.nativeBoundary.waits + 1
    if not m.nativeBoundary.finished then return invalid
    return {state:m.nativeBoundary,GetResponseCode:function() as integer
        return m.state.status
    end function,GetResponseHeaders:function() as object
        return m.state.responseHeaders
    end function}
end function

function NativeBoundaryRead(data as object, path as string) as boolean
    m.nativeBoundary.reads = m.nativeBoundary.reads + 1
    if not m.nativeBoundary.readable then return false
    for each value in m.nativeBoundary.bytes
        data.Push(value)
    end for
    return true
end function

sub NativeBoundarySetup()
    ' Minimal valid EBML + Segment + Tracks, English AAC two-channel track.
    bytes = [26,69,223,163,128,24,83,128,103,255,22,84,174,107,152,174,150,131,129,2,134,133,65,95,65,65,67,34,181,156,131,101,110,103,225,131,159,129,2]
    SetupPlayerFixture()
    m.nativeBoundary = {bytes:bytes,size:bytes.Count(),status:206,issued:0,waits:0,reads:0,starts:true,finished:true,readable:true,cancelled:false,headers:{},deleted:[],responseHeaders:{"Content-Range":"bytes 0-38/5000000000"}}
    m.top.id = "bounded-test"
    m.top.serverAddress = ""
    m.top.season = 0
    m.top.episode = 0
    m.top.audioMode = "projector"
    m.top.stream = {url:"https://media.example/api/file/opaque",name:"2160p",behaviorHints:{proxyHeaders:{request:{"Referer":"https://provider.example/"}}}}
end sub

sub Test_OpaqueNativeResolve()
    Harness_Suite("Opaque media uses bounded byte evidence through resolver and player")
    NativeBoundarySetup()
    NativeBoundaryResolve()
    answer = m.top.result
    Harness_Ok(answer.ok,"opaque direct delivery remains resolved")
    Harness_Equal(answer.streamFormat,"mkv","EBML and Segment bytes identify MKV without a filename")
    Harness_Ok(answer.media.complete,"same bounded read parses the complete Tracks element")
    Harness_Ok(answer.audioPolicy.englishOnlyAac,"explicit English AAC stereo survives the real resolver boundary")
    Harness_Equal(m.nativeBoundary.issued,1,"opaque detection and metadata use one bounded request")
    Harness_Equal(m.nativeBoundary.headers.range,"bytes=0-1048575","header request cannot intentionally acquire an entire movie")
    Harness_Equal(m.nativeBoundary.headers["accept-encoding"],"identity","file byte offsets request identity encoding")
    Harness_Equal(m.nativeBoundary.headers.referer,"https://provider.example/","per-stream request requirements survive inspection")
    Harness_Ok(m.nativeBoundary.verifyPeer and m.nativeBoundary.verifyHost,"TLS verification stays enabled")
    Harness_Ok(m.nativeBoundary.cancelled,"completed transfer is cancelled before cleanup")
    Harness_Equal(m.nativeBoundary.deleted.Count(),2,"final and temporary native transfer files are cleaned")
    task = {id:"bounded-player-resolve",result:answer}
    m.resolveTask = task
    m.playParams = {stream:m.top.stream,name:"Opaque movie",audioMode:"projector",position:0}
    onResolveResult(PlayerTest_Event(task,answer))
    Harness_Equal(m.video.content.streamFormat,"mkv","production callback hands the detected container to the native Video content")
    Harness_Equal(m.video.content.url,"https://media.example/api/file/opaque","format detection retains the exact signed delivery address privately")
    Harness_Equal(m.video.content.audioWhitelist,"en,eng","detected MKV keeps the strict native English filter")
    Harness_Ok(m.video.mute,"header facts alone do not unmute before native decoder checks")
    Harness_Ok(not m.sourceAccepted,"format and language metadata do not prove actual rendered playback")

    for each format in ["mp4","m3u8","mpd"]
        NativeBoundarySetup()
        m.top.stream.url = "https://media.example/video." + format
        NativeBoundaryResolve()
        Harness_Ok(m.top.result.ok,"known delivery still resolves")
        Harness_Equal(m.nativeBoundary.issued,0,"known MP4 HLS DASH do not incur a new header probe")
        expected = format
        if format = "m3u8" then expected = "hls"
        if format = "mpd" then expected = "dash"
        Harness_Equal(m.top.result.streamFormat,expected,"known transport is never overwritten by original file hints")
    end for

    NativeBoundarySetup()
    m.nativeBoundary.bytes = [26,69,223,163,128,0,0,0,0,0]
    m.nativeBoundary.size = 10
    m.nativeBoundary.responseHeaders["Content-Range"] = "bytes 0-9/1000"
    NativeBoundaryResolve()
    Harness_Equal(m.top.result.streamFormat,"","four magic bytes alone cannot declare a Matroska container")
    Harness_Ok(not m.top.result.media.complete,"unrecognized content never supplies English track evidence")

    NativeBoundarySetup()
    m.nativeBoundary.bytes = [26,69,223,163,128,24,83,128,103,255]
    m.nativeBoundary.size = 10
    m.nativeBoundary.responseHeaders["Content-Range"] = "bytes 0-9/1000"
    NativeBoundaryResolve()
    Harness_Equal(m.top.result.streamFormat,"mkv","bounded container evidence does not require Tracks to appear early")
    Harness_Ok(not m.top.result.media.complete,"missing Tracks remain uninspected")
    Harness_Ok(not m.top.result.audioPolicy.known,"container detection alone cannot authorize English fallback")

    for each failure in ["range-ignored","oversized","timeout","range-mismatch","read-failed","not-started"]
        NativeBoundarySetup()
        if failure = "range-ignored" then m.nativeBoundary.status = 200
        if failure = "oversized" then m.nativeBoundary.size = 2097153
        if failure = "timeout" then m.nativeBoundary.finished = false
        if failure = "range-mismatch" then m.nativeBoundary.responseHeaders["Content-Range"] = "bytes 1-39/1000"
        if failure = "read-failed" then m.nativeBoundary.readable = false
        if failure = "not-started" then m.nativeBoundary.starts = false
        NativeBoundaryResolve()
        Harness_Ok(m.top.result.ok,"optional failed inspection does not erase a valid direct URL")
        Harness_Equal(m.top.result.streamFormat,"","failed inspection never guesses the opaque container")
        Harness_Ok(not m.top.result.audioPolicy.known,"failed inspection cannot certify English audio")
        Harness_Ok(m.nativeBoundary.cancelled,"failure cancels the bounded transfer")
        Harness_Equal(m.nativeBoundary.deleted.Count(),2,"failure cleans both native output paths")
        if failure <> "read-failed" then Harness_Equal(m.nativeBoundary.reads,0,"unsafe response is never loaded into memory")
        Harness_Ok(m.nativeBoundary.waits <= 100,"inspection has a fixed maximum wait count")
    end for

    NativeBoundarySetup()
    m.nativeBoundary.failFactory = true
    NativeBoundaryResolve()
    Harness_Ok(m.top.result.ok,"a thrown native inspection failure cannot discard the valid delivery")
    Harness_Equal(m.top.result.media.reason,"inspection-error","inspection failure stays distinct from metadata evidence")
    Harness_Ok(not m.top.result.audioPolicy.known,"caught native inspection failure retains decoder verification")
    Harness_Equal(m.nativeBoundary.issued,0,"failure before native transfer starts performs no request")

    Harness_Ok(NativeMedia_ValidHeaderRange({"Content-Range":"bytes 0-1048575/5000000000"},1048576),"large movie total does not exceed the bounded prefix policy")
    Harness_Ok(NativeMedia_ValidHeaderRange({"Content-Range":"bytes 0-9/*"},10),"unknown total remains safe when the byte prefix is exact")
    for each range in ["bytes 0-38/20","bytes 0-39/1000","bytes 0-37/1000","bytes 1-39/1000","bytes 0-garbage/1000","items 0-38/1000",""]
        Harness_Ok(not NativeMedia_ValidHeaderRange({"Content-Range":range},39),"malformed or mismatched range cannot authorize file parsing")
    end for
    Harness_Ok(not NativeMedia_ValidHeaderRange({"Content-Range":1},39),"non-text response header fails closed")
    Harness_Ok(not NativeMedia_ValidHeaderRange(invalid,39),"missing response headers fail closed")
    Harness_Ok(not NativeMedia_ValidHeaderRange({"Content-Range":"bytes 0-1048576/*"},1048577),"declared range cannot enlarge the memory budget")
end sub

Test_OpaqueNativeResolve()
