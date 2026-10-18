Harness_Suite("Production automatic worker prefers practical UHD before large-file UHD")
m.selectionRegistry = MockRegistry()
m.selectionNow = now
giant = TestSource("D.2160p.mkv","English 2160p AAC 2.0")
giant.url = "https://cdn.example/giant?signature=fixture"
giant.behaviorHints.videoSize = 87937111321#
practical = TestSource("A.2160p.mkv","English 2160p AAC 2.0")
practical.url = "https://other-cdn.example/practical?signature=fixture"
practical.behaviorHints.videoSize = 12884901888#
unknownSize = {url:"https://third.example/unknown",name:"English 2160p AAC 2.0"}
fallback = {url:"https://fourth.example/hd",name:"English 1080p AAC 2.0"}
raw = [giant,practical,unknownSize,fallback]
rawBefore = FormatJson(raw)
m.top = {providerGroups:[CinemaBudgetStreams(raw)],excludedUrls:[],videoId:"tt100001",audioMode:"projector",fourKOnly:false}
TestAutomaticChoose()
Harness_Equal(m.top.result.streams.Count(),4,"large file remains an eligible bounded fallback")
Harness_Equal(m.top.result.streams[0].url,practical.url,"12 GiB UHD precedes the observed 87.9 GB file through budget and real worker")
Harness_Equal(m.top.result.streams[1].url,unknownSize.url,"unknown size remains an ordinary eligible UHD source")
Harness_Equal(m.top.result.streams[2].url,giant.url,"large UHD is retained ahead of 1080p")
Harness_Equal(m.top.result.streams[3].url,fallback.url,"file size never raises HD above eligible UHD")
Harness_Equal(FormatJson(raw),rawBefore,"preference never mutates provider records or private URLs")

' A remembered source can carry a file-size label without changing its opaque
' identity. Its verified startup must not override the new size preference.
rememberedGiant = TestSource("D.2160p.mkv","English 2160p AAC 2.0")
rememberedGiant.url = giant.url
rememberedGiant.description = "File size: 81.9 GiB"
memory = SourceMemory_Record(SourceMemory_Empty(),keyD,"working",now)
SourceMemory_Save(m.selectionRegistry,memory,now)
m.top.providerGroups = [[rememberedGiant,practical,unknownSize,fallback]]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams[0].url,practical.url,"remembered giant cannot outrank ordinary UHD")
Harness_Ok(not m.top.result.rememberedSource,"remembered-first flag describes the actual chosen source")

practical2 = {url:"https://other-cdn.example/practical2",name:"English 2160p AAC 2.0",description:"16 GiB"}
practical3 = {url:"https://other-cdn.example/practical3",name:"English 2160p AAC 2.0",description:"20 GB"}
m.top.providerGroups = [[rememberedGiant,practical,practical2,practical3,fallback]]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams.Count(),4,"three-UHD budget and HD fallback remain bounded")
Harness_Equal(m.top.result.streams[0].url,practical.url,"ordinary UHD starts before a remembered large host")
Harness_Equal(m.top.result.streams[1].url,practical2.url,"host rotation cannot insert a giant ahead of ordinary UHD")
Harness_Equal(m.top.result.streams[2].url,practical3.url,"third practical same-host UHD survives the initial UHD budget")
Harness_Equal(m.top.result.streams[3].url,fallback.url,"initial pool still reserves HD fallback after three UHD")
m.top.fourKOnly = true
TestAutomaticChoose()
Harness_Equal(m.top.result.streams.Count(),4,"strict UHD keeps the large source after practical alternatives")
Harness_Equal(m.top.result.streams[3].url,rememberedGiant.url,"large source is deferred rather than banned")

manual = AutoPlayback_Candidates(rememberedGiant,[rememberedGiant,practical,fallback],6,3)
Harness_Equal(manual[0].url,rememberedGiant.url,"manual selected source is never reordered by size")
Harness_Equal(manual[1].url,practical.url,"manual fallback ordering remains unchanged")

Harness_Suite("File-size hints remain bounded and preserve native numeric types")
boxedInt = CreateObject("roInt"):boxedInt.SetInt(1048576)
boxedLong = CreateObject("roLongInteger"):boxedLong.SetLongInt(87937111321&)
boxedFloat = CreateObject("roFloat"):boxedFloat.SetFloat(80000000000.0)
boxedDouble = CreateObject("roDouble"):boxedDouble.SetDouble(87937111321#)
for each pair in [[1048576,1048576#],[87937111321&,87937111321#],[12.5,12.5#],[87937111321#,87937111321#],[boxedInt,1048576#],[boxedLong,87937111321#],[boxedFloat,80000000000#],[boxedDouble,87937111321#]]
    valueSource = {url:"https://fixture.example/value",name:"2160p",behaviorHints:{videoSize:pair[0]}}
    budgeted = CinemaBudgetStreams([valueSource])
    Harness_Equal(CinemaStreamSizeBytes(budgeted[0]),pair[1],"boxed and unboxed numeric size survives production budget without 32-bit truncation")
end for
giant.behaviorHints.videoSize = boxedLong
m.selectionRegistry = MockRegistry()
m.top = {providerGroups:[CinemaBudgetStreams([giant,practical,fallback])],excludedUrls:[],videoId:"tt100001",audioMode:"projector",fourKOnly:false}
TestAutomaticChoose()
Harness_Equal(m.top.result.streams[0].url,practical.url,"native boxed 64-bit giant is deferred through budget and selection worker")
Harness_Equal(m.top.result.streams[1].url,giant.url,"boxed 64-bit giant stays ahead of HD fallback")
for each value in ["87937111321",true,false,0,-1,{},[],1099511627777#]
    malformed = {url:"https://fixture.example/bad",description:"80 GiB",behaviorHints:{videoSize:value}}
    Harness_Equal(CinemaStreamSizeBytes(malformed),invalid,"malformed explicit size never coerces into a size preference")
    budgeted = CinemaBudgetStreams([malformed])
    Harness_Equal(CinemaStreamSizeBytes(budgeted[0]),invalid,"budget boundary preserves unknown size rather than trusting contradictory label")
end for
for each pair in [["Size: 1.5 GiB",1610612736#],["35 GB",35000000000#],["500 MB",500000000#],["500 MiB",524288000#],["size: 81.9 gib",87939448832#]]
    parsed = CinemaStreamSizeBytes({description:pair[0]})
    ' Decimal annotations are approximate; exact binary values are checked in
    ' the first four cases, while the last needs only the same heavy class.
    if pair[0] = "size: 81.9 gib"
        Harness_Ok(parsed > 37580963840#,"decimal lowercase GiB annotation is classified without Int overflow")
    else
        Harness_Equal(parsed,pair[1],"GB/MB and GiB/MiB use their distinct documented units")
    end if
end for
for each label in ["80 Gbps","80 GB/s","Movie.80GB.mkv","1,000 GB","size 2 TB","-40 GB","1e2 GB"]
    Harness_Equal(CinemaStreamSizeBytes({description:label}),invalid,"speed strings, filenames and unsupported or malformed sizes stay unknown")
end for
Harness_Equal(CinemaStreamSizeBytes({url:"https://fixture.example/80GB?size=90GB",behaviorHints:{filename:"Film.100GB.mkv"}}),invalid,"private URL and filename are never size evidence")
Harness_Equal(CinemaStreamSizeBytes({description:"file 10 GB | pack 80 GB"}),invalid,"two different annotations in one field remain unknown")
Harness_Equal(CinemaStreamSizeBytes({title:"10 GB",description:"80 GB"}),invalid,"conflicting title and description remain unknown")
Harness_Equal(CinemaStreamSizeBytes({title:"10 GB",description:"10 GB"}),10000000000#,"identical separate annotations can agree")
Harness_Equal(CinemaStreamSizeBytes({description:String(513,"x") + " 80 GB"}),invalid,"oversized raw field is never scanned")
Harness_Equal(CinemaStreamSizeBytes({description:"80 GiB",behaviorHints:{videoSize:10000000000#}}),10000000000#,"valid numeric metadata takes precedence over a display label")

Harness_Suite("Automatic size classes retain quality, memory, English and fallback boundaries")
boundary = {url:"https://boundary.example/uhd",name:"English 2160p AAC 2.0",behaviorHints:{videoSize:37580963840#}}
above = {url:"https://above.example/uhd",name:"English 2160p AAC 2.0",behaviorHints:{videoSize:37580963841#}}
m.top.providerGroups = [[above,boundary,fallback]]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams[0].url,boundary.url,"35 GiB boundary is ordinary while only greater values are deferred")
Harness_Equal(m.top.result.streams[1].url,above.url,"one byte above threshold is a preference change, not rejection")
manualRanked = CinemaChooseStreams([above,boundary,fallback],false,"projector",false)
Harness_Equal(manualRanked[0].url,above.url,"manual source ranking retains its stable equal-hint order")
memoryPreferred = TestSource("D.2160p.mkv","English 2160p AAC 2.0")
memoryPreferred.url = "https://cdn.example/remembered-small"
memoryPreferred.description = "10 GiB"
SourceMemory_Save(m.selectionRegistry,SourceMemory_Record(SourceMemory_Empty(),keyD,"working",now),now)
m.top.providerGroups = [[practical,memoryPreferred,giant,fallback]]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams[0].url,memoryPreferred.url,"remembered working file remains first within ordinary UHD class")
Harness_Ok(m.top.result.rememberedSource,"remembered flag remains true for actual remembered practical handoff")
onlyHeavy = [giant,above,fallback]
m.top.providerGroups = [onlyHeavy]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams.Count(),3,"all-large result set retains every unique file within budget")
Harness_Equal(m.top.result.streams[2].url,fallback.url,"all-large UHD still precedes HD")
m.top.excludedUrls = [giant.url]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams.Count(),2,"already attempted giant stays excluded on recovery")
Harness_Equal(m.top.result.streams[0].url,above.url,"recovery reaches the next eligible UHD rather than replaying excluded URL")
foreignSmall = {url:"https://fixture.example/foreign",name:"Hindi only",title:"2160p",description:"10 GiB"}
unsafeSmall = {url:"http://fixture.example/plain",name:"2160p",description:"10 GiB"}
uncachedSmall = {url:"https://fixture.example/download",name:"[TB download] Torrentio 2160p",description:"10 GiB"}
m.top.excludedUrls = []
m.top.providerGroups = [[foreignSmall,unsafeSmall,uncachedSmall,practical,fallback]]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams.Count(),2,"practical size cannot admit foreign-only, HTTP or uncached descriptors")
Harness_Equal(m.top.result.streams[0].url,practical.url,"existing English and delivery eligibility still govern selection")
stereo = {url:"https://rank.example/stereo",name:"English 2160p AAC 2.0",description:"20 GiB"}
unspecified = {url:"https://rank.example/unspecified",name:"English 2160p",description:"5 GiB"}
m.selectionRegistry = MockRegistry()
m.top.providerGroups = [[unspecified,stereo,fallback]]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams[0].url,stereo.url,"within practical class smaller does not override projector audio ranking")
surround = {url:"https://rank.example/ddplus",name:"English 2160p HEVC DDP5.1",description:"20 GiB"}
m.top.audioMode = "surround"
m.top.providerGroups = [[stereo,surround,fallback]]
TestAutomaticChoose()
Harness_Equal(m.top.result.streams[0].url,surround.url,"within practical class receiver DD+ preference remains intact")
