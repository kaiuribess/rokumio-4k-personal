' Run in the native-player suite: production OnEnter, resolver callback,
' scheduling/retry timer, native handoff and English acceptance remain intact.
function UhdDeferralMedia(width as integer, height as integer) as object
    return {complete:true,tracks:[{kind:1,enabled:true,width:width,height:height}]}
end function

sub UhdDeferralSetup(options = invalid as dynamic)
    SetupPlayerFixture()
    m.stores = invalid
    m.sourceMemoryPending = []
    m.sourceMemoryTask = invalid
    m.sourceMemoryPump = invalid
    m.measuredHdUrls = ["https://media.example/previous-private-url"]
    first = {name:"English 2160p AAC",url:"https://media.example/labelled-uhd-a.mkv"}
    nextStream = {name:"English 2160p AAC",url:"https://media.example/labelled-uhd-b.mkv"}
    params = {stream:first,candidates:[first,nextStream],preferUhd:true,autoSourceRetry:true,fourKOnly:false,metaType:"movie",metaId:"tt001",videoId:"tt001",audioMode:"projector",name:"Fixture",position:900.5,serverAddress:""}
    if Type(options) = "roAssociativeArray"
        for each key in options
            params[key] = options[key]
        end for
    end if
    OnEnter(params)
end sub

function UhdDeferralResult(media as dynamic, ok = true as boolean) as object
    return {ok:ok,url:m.playParams.stream.url,streamFormat:"mkv",mode:"direct",headers:[],media:media,audioPolicy:{known:true,compatible:true}}
end function

sub UhdDeferralAcceptEnglish()
    onPlayKickFire()
    m.video.state = "playing"
    m.video.availableAudioTracks = [{Language:"eng",Track:"english",Name:"English AAC"}]
    m.video.currentAudioTrack = "english"
    m.video.audioFormat = "aac"
    onEnglishAudioFactsChanged()
    for sample = 1 to 3
        m.video.positionInfo = {audio:sample,video:sample}
        onAudioProgressTick()
    end for
end sub

sub Test_PlayerMeasuredHdDeferral()
    Harness_Suite("Automatic 4K-first inspects later UHD while retaining measured HD fallback")
    UhdDeferralSetup()
    first = m.playParams.stream
    other = m.sourceQueue[1]
    firstTask = m.resolveTask
    hd = UhdDeferralResult(UhdDeferralMedia(1920,1080))
    Harness_Equal(m.measuredHdUrls.Count(),0,"real OnEnter clears the reused screen's prior private measurements")
    onResolveResult(PlayerTest_Event(firstTask,hd))
    Harness_Ok(m.retryPending,"measured HD takes the actual automatic retry path")
    Harness_Equal(m.video.content,invalid,"measured HD does not reach native content ahead of remaining UHD")
    Harness_Equal(m.sourceQueue.Count(),3,"one fallback is retained after the remaining pool")
    Harness_Equal(m.sourceQueue[2].url,first.url,"retained fallback preserves its exact private source configuration")
    Harness_Equal(m.sourceMemoryPending.Count(),0,"quality deferral creates no network or incompatible-file memory")
    Harness_Equal(m.playParams.position,900.5,"pre-acceptance deferral preserves the accepted resume checkpoint")
    Harness_Ok(m.status.text.InStr("fallback") >= 0,"status distinguishes quality checking from a broken source")
    onResolveResult(PlayerTest_Event(firstTask,hd))
    Harness_Equal(m.sourceQueue.Count(),3,"duplicate resolve callback cannot append a second fallback")
    onAutoSourceRetry()
    secondTask = m.resolveTask
    Harness_Equal(m.playParams.stream.url,other.url,"production retry timer resolves the next candidate")
    Harness_Equal(m.measuredHdUrls.Count(),1,"same-session retry retains the measured-HD fact")
    onResolveResult(PlayerTest_Event(firstTask,hd))
    Harness_Equal(m.resolveTask.id,secondTask.id,"stale previous source cannot consume the current resolver")
    onResolveResult(PlayerTest_Event(secondTask,UhdDeferralResult(UhdDeferralMedia(3840,2160))))
    Harness_Equal(m.video.content.url,other.url,"actual UHD proceeds through the production native content handoff")
    Harness_Ok(not m.sourceAccepted,"encoded dimensions alone do not accept audio/playback")
    UhdDeferralAcceptEnglish()
    Harness_Ok(m.sourceAccepted and not m.video.mute,"ordinary English track and advancing native samples still authorize playback")
    handoffs = m.contentHandoffs.Count()
    acceptedUrl = m.video.content.url
    late = {id:"late-owned-result"}:m.resolveTask = late
    onResolveResult(PlayerTest_Event(late,hd))
    Harness_Equal(m.contentHandoffs.Count(),handoffs,"late owned resolver cannot replace accepted playback")
    Harness_Equal(m.video.content.url,acceptedUrl,"accepted native file remains untouched")
    Harness_Ok(not m.retryPending,"late resolution cannot schedule quality switching during playback")
    OnExit()
    Harness_Equal(m.measuredHdUrls.Count(),0,"real OnExit releases all temporary private source URLs")
    OnEnter({stream:first,candidates:[first,other],preferUhd:true,autoSourceRetry:true,position:900.5,metaType:"movie"})
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    Harness_Ok(m.retryPending,"same title on a later player entry gets fresh quality inspection")

    Harness_Suite("Failed later UHD reaches retained HD without a quality retry cycle")
    UhdDeferralSetup()
    first = m.playParams.stream
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    onAutoSourceRetry()
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(invalid,false)))
    Harness_Equal(m.sourceMemoryPending.Count(),1,"real later resolution failure retains normal failure memory")
    onAutoSourceRetry()
    Harness_Equal(m.playParams.stream.url,first.url,"actual retry timer returns to the retained HD candidate")
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    Harness_Equal(m.video.content.url,first.url,"retained HD starts when the remaining UHD attempt failed")
    Harness_Ok(not m.retryPending,"measured fallback cannot defer itself forever")
    Harness_Equal(m.sourceQueue.Count(),3,"fallback retry does not keep growing the bounded pool")
    Harness_Equal(m.playParams.position,900.5,"all unaccepted alternatives preserve the intended resume position")

    UhdDeferralSetup()
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    onAutoSourceRetry()
    second = m.playParams.stream
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    Harness_Equal(m.video.content.url,second.url,"a remaining known-HD fallback never masquerades as untried UHD")
    Harness_Ok(not m.retryPending and m.measuredHdUrls.Count() = 2,"two false UHD labels terminate quality comparison without cycling")

    Harness_Suite("Manual, disabled, strict, incomplete and malformed cases preserve their existing policies")
    for each options in [{preferUhd:invalid},{preferUhd:false},{autoSourceRetry:false},{diagnostic:true},{diagnosticControl:true}]
        UhdDeferralSetup(options)
        selectedUrl = m.playParams.stream.url
        onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
        Harness_Equal(m.video.content.url,selectedUrl,"manual, disabled or diagnostic playback keeps the selected usable source")
        Harness_Ok(not m.retryPending,"automatic UHD preference does not override an excluded playback mode")
    end for
    UhdDeferralSetup({fourKOnly:true})
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    Harness_Ok(m.retryPending and m.video.content = invalid,"strict 4K still rejects known below-UHD video")
    Harness_Equal(m.sourceQueue.Count(),2,"strict 4K rejection never retains an HD fallback")
    Harness_Equal(m.sourceMemoryPending.Count(),0,"strict quality rejection remains separate from broken-file memory")
    for each media in [invalid,{},"malformed",{complete:false,tracks:[{kind:1,enabled:true,width:1920,height:1080}]},{complete:true,tracks:[{kind:1,enabled:true,width:0,height:1080}]},{complete:true,tracks:[{kind:1,enabled:true,width:1920,height:1080},{kind:1,enabled:true,width:3840,height:2160}]}]
        UhdDeferralSetup()
        selectedUrl = m.playParams.stream.url
        onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(media)))
        Harness_Equal(m.video.content.url,selectedUrl,"unknown, incomplete or mixed native dimensions do not invent an HD verdict")
    end for
    UhdDeferralSetup()
    m.sourceQueue = [m.playParams.stream,invalid,{},"bad",{name:"2160p",url:"http://media.example/plain"},{name:"2160p",description:"[Hindi only]",url:"https://media.example/foreign"},{name:"1080p English",url:"https://media.example/hd"}]
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    Harness_Equal(m.video.content.url,m.playParams.stream.url,"only an eligible remaining UHD source can justify deferral")
    Harness_Ok(not m.retryPending,"malformed, rejected and HD candidates do not cause a useless quality retry")

    Harness_Suite("Quality deferral stays bounded and cannot revive stale player ownership")
    UhdDeferralSetup()
    for index = 3 to 64
        m.sourceQueue.Push({name:"2160p",url:"https://media.example/extra-" + index.ToStr()})
    end for
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    Harness_Equal(m.sourceQueue.Count(),64,"a full queue cannot grow beyond its resource limit")
    Harness_Equal(m.video.content.url,m.playParams.stream.url,"full queue preserves the usable source instead of dropping fallback")
    UhdDeferralSetup()
    for index = 1 to 64
        m.measuredHdUrls.Push("https://media.example/known-" + index.ToStr())
    end for
    onResolveResult(PlayerTest_Event(m.resolveTask,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
    Harness_Equal(m.measuredHdUrls.Count(),64,"measured source identities obey the same bounded budget")
    Harness_Ok(not m.retryPending,"exhausted observation budget cannot create another retry cycle")
    for each state in ["inactive","retrying"]
        UhdDeferralSetup()
        held = m.resolveTask
        if state = "inactive" then m.playbackActive = false else m.retryPending = true
        onResolveResult(PlayerTest_Event(held,UhdDeferralResult(UhdDeferralMedia(1920,1080))))
        Harness_Equal(m.video.content,invalid,"late result cannot start native playback after cancellation or queued recovery")
        Harness_Equal(m.sourceQueue.Count(),2,"late result cannot mutate the next operation's queue")
        Harness_Equal(m.resolveTask,invalid,"owned stale result is reaped rather than left occupying the worker")
    end for
end sub
