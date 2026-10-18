sub Main()
    Harness_Suite("Server-declared file totals retain exact large-file precision")
    for each fixture in [{text:"5000000000",value:5000000000#},{text:"5000000001",value:5000000001#},{text:"50000000001",value:50000000001#},{text:"1099511627776",value:1099511627776#},{text:"0000001000",value:1000}]
        value = NativeMedia_DeclaredFileBytes({"Content-Range":"bytes 0-38/" + fixture.text})
        Harness_Equal(value,fixture.value,"decimal total is preserved exactly: " + fixture.text)
    end for
    Harness_Equal(NativeMedia_DeclaredFileBytes({"cOnTeNt-RaNgE":" BYTES 0-38/5000000001 "}),5000000001#,"case and surrounding whitespace are accepted")
    for each bad in [invalid,{},[],"bytes 0-38/5000000000",{"Content-Range":1},{"Content-Range":"bytes 0-38/*"},{"Content-Range":"bytes 1-38/1000"},{"Content-Range":"bytes 0-38/0"},{"Content-Range":"bytes 0-38/1099511627777"},{"Content-Range":"bytes 0-38/99999999999999"},{"Content-Range":"bytes 0-38/4.5"},{"Content-Range":"bytes 0-38/-1000"},{"Content-Range":"bytes 0-38/5000 private-fixture-token"}]
        Harness_Equal(NativeMedia_DeclaredFileBytes(bad),invalid,"unknown or malformed declarations do not create a total")
    end for
    duplicate = CreateObject("roAssociativeArray")
    duplicate.SetModeCaseSensitive()
    duplicate["Content-Range"] = "bytes 0-38/1000"
    duplicate["content-range"] = "bytes 0-38/2000"
    Harness_Equal(NativeMedia_DeclaredFileBytes(duplicate),invalid,"duplicate range headers cannot create ambiguous totals")

    Harness_Suite("Average container rate is bounded and distinct from delivery speed")
    facts = PlaybackInfo_FileFacts({declaredFileBytes:5000000001#,url:"https://example.invalid/private-fixture-token"},8000)
    Harness_Equal(facts.declaredFileBytes,5000000001#,"status retains exact totals beyond signed 32-bit range")
    Harness_Equal(facts.nativeDurationSeconds,8000,"fresh native duration is retained")
    Harness_Equal(facts.averageContainerBitsPerSecond,5000000.001#,"average uses double precision before multiplication/division")
    Harness_Equal(facts.measurement,"server-declared-size-divided-by-native-duration","estimate states its actual provenance")
    Harness_Equal(facts.Count(),4,"file status has a fixed scalar allowlist")
    Harness_Ok(FormatJson(facts).InStr("private-fixture-token") < 0,"file status contains no path, URL or arbitrary provider metadata")
    for each size in [5000000001#,50000000001#,1099511627776#]
        facts = PlaybackInfo_FileFacts({declaredFileBytes:size},604800)
        Harness_Equal(facts.declaredFileBytes,size,"integer validation never narrows a large total to 32 bits")
        Harness_Ok(facts.averageContainerBitsPerSecond <> invalid,"bounded large-file estimate remains available")
    end for
    for each badSize in [invalid,"5000000000",true,{},[],0,-1,1.5,5000000000.5#,1099511627777#]
        facts = PlaybackInfo_FileFacts({declaredFileBytes:badSize},8000)
        Harness_Equal(facts.declaredFileBytes,invalid,"invalid sizes stay unknown")
        Harness_Equal(facts.averageContainerBitsPerSecond,invalid,"invalid sizes never imply a measured rate")
    end for
    for each duration in [invalid,"8000",false,{},[],0,-1,604801]
        facts = PlaybackInfo_FileFacts({declaredFileBytes:5000000001#},duration)
        Harness_Equal(facts.nativeDurationSeconds,invalid,"missing or malformed source duration stays unknown")
        Harness_Equal(facts.averageContainerBitsPerSecond,invalid,"a size without fresh duration cannot produce an average")
    end for
    facts = PlaybackInfo_FileFacts({declaredFileBytes:1099511627776#},1)
    Harness_Equal(facts.averageContainerBitsPerSecond,invalid,"unreasonable rate estimates are rejected")
    facts = PlaybackInfo_FileFacts(invalid,8000)
    Harness_Equal(facts.declaredFileBytes,invalid,"non-MKV or missing header evidence has no invented size")
    Harness_Equal(facts.averageContainerBitsPerSecond,invalid,"native duration alone is not a rate measurement")
    Harness_Finish()
end sub
