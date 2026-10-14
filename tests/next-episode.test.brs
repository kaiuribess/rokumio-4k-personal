function EpisodeTimerClock() as dynamic
    if m.testTimed = true
        return {elapsed:0,Mark:sub()
            m.elapsed=0
        end sub,TotalMilliseconds:function() as integer
            return m.elapsed
        end function}
    end if
    return invalid
end function

function EpisodeMeta() as object
    return {id:"show",videos:[{id:"next-season",season:3,episode:1,name:"New season"},{id:"special",season:0,episode:1},{id:"two",season:"1",episode:"2",name:"Second",released:"2026-10-13"},{id:"one",season:1,episode:1},{id:"three",season:1,episode:3}]}
end function

function EpisodeParams() as object
    return {metaType:"series",metaId:"show",videoId:"one",season:1,episode:1,position:400,stream:{url:"https://private.invalid/previous"},candidates:[{}],addonAddress:"https://provider.invalid",name:"Test show",audioMode:"surround",fourKOnly:true,poster:"https://art.invalid/poster",diagnostic:false,waitForProviders:true}
end function

function EpisodeStore() as object
    return {calls:[], callFunc:function(name as string,a=invalid as dynamic,b=invalid as dynamic,c=invalid as dynamic,d=invalid as dynamic,e=invalid as dynamic,f=invalid as dynamic,g=invalid as dynamic,h=invalid as dynamic,i=invalid as dynamic,j=invalid as dynamic,k=invalid as dynamic) as dynamic
        m.calls.Push({name:name,a:a,b:b,c:c,h:h,i:i})
        if name = "TimeNowIso" then return "2026-10-14T12:00:00Z"
        if name = "LibraryIsChannelType" then return false
        return invalid
    end function}
end function

sub EpisodeSetup()
    m.playParams = EpisodeParams()
    m.nextEpisodeMeta = EpisodeMeta()
    m.nextEpisodeTimer = {control:"stop"}
    m.nextEpisodeSetup = {control:"stop"}
    m.nextEpisodeTask = invalid
    m.nextEpisodePending = false
    m.nextEpisodeParams = invalid
    m.playbackActive = true
    m.sourceAccepted = true
    m.hasPlayed = true
    m.naturalEnd = false
    m.saved = false
    m.audioGuardBlocked = false
    m.audioGuardActive = false
    m.audioGuardArmed = false
    m.audioGuardTimer = {control:"stop"}
    m.retryPending = false
    m.sourceFailure = ""
    m.status = {text:""}
    m.video = {state:"finished",duration:600,position:600,HasField:function(name as string) as boolean
        return m.DoesExist(name)
    end function}
    m.top = {screenActive:true,nextEpisodeRequest:invalid,watchStateUpdate:invalid}
    m.store = EpisodeStore()
    m.stores = {library:m.store,watch:m.store,time:m.store}
    m.workerSequence = 0
    m.launched = 0
    m.reaped = 0
end sub

sub onEnglishAudioFactsChanged()
end sub
sub StopSourceStartupLimit()
end sub
sub HideBuffering()
end sub
sub HidePlaybackInfo()
end sub
sub onPlaybackFactsChanged()
end sub
sub StopResolvePulse()
end sub
function HasLogo() as boolean
    return false
end function
sub ArmSourceStartupLimit()
end sub
sub ShowPlaybackInfo()
end sub
sub LogVideoError()
end sub
function NotPlayableOnDevice() as boolean
    return false
end function
function ScheduleNextSource(reason as string) as boolean
    m.sourceFailure = reason
    return true
end function
function NextPlayerWorkerId(prefix as string) as string
    m.workerSequence = m.workerSequence + 1
    return prefix + m.workerSequence.ToStr()
end function
function AsyncTask_Launch(owner as object,kind as string,callback as string,params as object,id as string) as object
    m.launched = m.launched + 1
    return {id:id,params:params}
end function
sub AsyncTask_Reap(task as object,owner as object,cancel as boolean)
    m.reaped = m.reaped + 1
end sub
function EpisodeEvent(task as object,result as object) as object
    return {task:task,result:result,GetRoSGNode:function() as object
        return m.task
    end function,GetData:function() as object
        return m.result
    end function}
end function

sub TestEpisodePolicy()
    Harness_Suite("Next episode uses real provider metadata and fresh sources")
    params = EpisodeParams()
    meta = EpisodeMeta()
    nextParams = NextEpisode_Params(params,meta,"2026-10-14")
    Harness_Equal(nextParams.videoId,"two","opaque provider id preserved")
    Harness_Equal(nextParams.season,1,"season preserved")
    Harness_Equal(nextParams.episode,2,"numeric string episode normalized")
    Harness_Equal(nextParams.position,0,"next episode starts from zero")
    Harness_Equal(nextParams.fourKOnly,true,"explicit UHD mode preserved")
    Harness_Equal(nextParams.audioMode,"surround","speaker mode preserved")
    Harness_Ok(nextParams.waitForProviders,"explicit full comparison is preserved for the next episode")
    Harness_Equal(nextParams.autoPlay,true,"new episode automatically selects sources")
    Harness_Equal(nextParams.stream,invalid,"previous signed source is never reused")
    Harness_Equal(nextParams.candidates,invalid,"previous source queue is never reused")
    Harness_Equal(nextParams.name,"Test show","series title remains stable")
    Harness_Equal(nextParams.episodeName,"Second","episode caption supplied")
    Harness_Equal(params.position,400,"input request unchanged")
    params.videoId="three": params.episode=3
    nextParams = NextEpisode_Params(params,meta,"2026-10-14")
    Harness_Equal(nextParams.videoId,"next-season","rolls into next known season, including gaps")
    params.videoId="next-season": params.season=3: params.episode=1
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"final episode stops without looping to specials")
    params=EpisodeParams(): params.videoId="missing"
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"unknown current id cannot advance")
    params.videoId=""
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"missing current id cannot advance")
    params=EpisodeParams(): params.season=0: params.episode=1: params.videoId="special"
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"last special does not jump to a regular season")
    meta.videos.Push({id:"special-two",season:0,episode:2})
    Harness_Equal(NextEpisode_Params(params,meta).videoId,"special-two","specials advance only within their season")
    params=EpisodeParams(): params.metaType="movie"
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"movies never auto advance")
    params=EpisodeParams(): params.diagnostic=true
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"diagnostics never auto advance")
    params=EpisodeParams(): params.autoNextEpisode=false
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"explicit opt out respected")
    params=EpisodeParams(): meta.videos[2].released="2099-01-01"
    Harness_Equal(NextEpisode_Params(params,meta,"2026-10-14"),invalid,"unaired immediate next episode stops, not skipped")
    meta=EpisodeMeta(): meta.id="other-show"
    Harness_Equal(NextEpisode_Params(params,meta),invalid,"metadata for another show rejected")
    params=EpisodeParams(): meta={id:"show",videos:[{season:1,episode:1},{season:1,episode:2}]}
    Harness_Equal(NextEpisode_Params(params,meta).videoId,"show:1:2","conventional id fallback only for known episode")
    Harness_Equal(NextEpisode_Ordinal("2147483648"),invalid,"overflow rejected")
    Harness_Equal(NextEpisode_Ordinal(-1),invalid,"negative ordinal rejected")
    Harness_Equal(NextEpisode_Ordinal(1.5),invalid,"fraction rejected")
    Harness_Equal(NextEpisode_Ordinal("1x"),invalid,"malformed ordinal rejected")
end sub

sub TestEpisodeFinishAndCancel()
    Harness_Suite("Only accepted natural finish arms a cancellable deferred transition")
    EpisodeSetup()
    onVideoStateChanged()
    Harness_Ok(m.naturalEnd,"natural end recorded")
    Harness_Ok(m.nextEpisodePending,"next episode pending")
    Harness_Equal(m.nextEpisodeTimer.control,"start","countdown timer armed")
    Harness_Equal(m.nextEpisodeSeconds,5,"five second cancel window")
    Harness_Equal(m.top.nextEpisodeRequest,invalid,"no scene navigation inside Video observer")
    Harness_Equal(m.store.calls.Count(),1,"only pure clock call before timer")
    onVideoStateChanged()
    Harness_Equal(m.nextEpisodeSeconds,5,"duplicate finish does not multiply countdown")
    for i=1 to 4
        onNextEpisodeTick()
    end for
    Harness_Equal(m.top.nextEpisodeRequest,invalid,"no early request")
    onNextEpisodeTick()
    Harness_Equal(m.top.nextEpisodeRequest.params.videoId,"two","timer sends next episode")
    Harness_Equal(m.top.nextEpisodeRequest.videoId,"one","request scopes current episode")
    Harness_Equal(m.top.watchStateUpdate.position,600,"completion persisted before reset")
    Harness_Ok(m.saved,"completed position saved")
    Harness_Equal(m.nextEpisodeTimer.control,"stop","countdown stopped")
    Harness_Ok(CanAdvanceEpisode("one"),"matching finished playback accepts route")
    Harness_Ok(not CanAdvanceEpisode("old"),"stale request rejected")
    EpisodeSetup(): m.video.position=0
    onVideoStateChanged()
    for i=1 to 5
        onNextEpisodeTick()
    end for
    Harness_Equal(m.top.watchStateUpdate.position,600,"terminal native position reset still marks complete")
    EpisodeSetup(): m.video.position=100
    onVideoStateChanged()
    Harness_Equal(m.sourceFailure,"unexpected-end","premature ending retries same episode")
    Harness_Ok(not m.nextEpisodePending,"premature ending never advances")
    EpisodeSetup(): m.sourceAccepted=false
    onVideoStateChanged()
    Harness_Equal(m.sourceFailure,"ended-before-audio","unaccepted playback retries")
    Harness_Ok(not m.nextEpisodePending,"unaccepted playback never advances")
    EpisodeSetup(): m.playParams.diagnostic=true
    onVideoStateChanged()
    Harness_Ok(not m.nextEpisodePending,"test sample finish never advances")
    EpisodeSetup(): m.top.screenActive=false
    Harness_Ok(not ScheduleNextEpisode(),"hidden screen cannot schedule")
    EpisodeSetup(): m.naturalEnd=true
    ScheduleNextEpisode(): CancelNextEpisode()
    onNextEpisodeTick()
    Harness_Equal(m.top.nextEpisodeRequest,invalid,"Back cancellation cannot restart")
    EpisodeSetup(): m.naturalEnd=true
    ScheduleNextEpisode(): m.video.state="playing"
    onNextEpisodeTick()
    Harness_Ok(not m.nextEpisodePending,"replay cancels old countdown")
    Harness_Equal(m.top.nextEpisodeRequest,invalid,"replay not interrupted")
    EpisodeSetup(): m.naturalEnd=true
    ScheduleNextEpisode(): m.top.screenActive=false
    onNextEpisodeTick()
    Harness_Ok(not m.nextEpisodePending,"leaving cancels late timer")
end sub

sub TestEpisodeMetadataAndRoute()
    Harness_Suite("Metadata worker cancellation and fixed-depth Scene route")
    EpisodeSetup()
    PrepareNextEpisode(m.playParams)
    Harness_Equal(m.nextEpisodeSetup.control,"start","sparse series primes worker off timer")
    onNextEpisodeSetup()
    Harness_Equal(m.launched,1,"one metadata worker")
    stale={id:"old"}
    onNextEpisodeMetaLoaded(EpisodeEvent(stale,{ok:true,meta:EpisodeMeta()}))
    Harness_Ok(m.nextEpisodeTask<>invalid,"stale metadata cannot consume current worker")
    current=m.nextEpisodeTask
    onNextEpisodeMetaLoaded(EpisodeEvent(current,{ok:true,meta:EpisodeMeta()}))
    Harness_Equal(m.nextEpisodeTask,invalid,"completed worker reaped")
    Harness_Equal(m.nextEpisodeMeta.id,"show","series metadata retained")
    m.playParams.seriesMeta=EpisodeMeta()
    PrepareNextEpisode(m.playParams)
    Harness_Equal(m.nextEpisodeSetup.control,"stop","complete metadata does not refetch")
    m.nextEpisodeTask={id:"cancel"}
    CancelNextEpisode()
    Harness_Equal(m.nextEpisodeTask,invalid,"Back cancels metadata worker")
    onNextEpisodeMetaLoaded(EpisodeEvent({id:"cancel"},{ok:true,meta:{id:"wrong"}}))
    Harness_Equal(m.nextEpisodeMeta.id,"show","cancelled callback ignored")
    node={calls:0,callFunc:sub(name as string,params as object)
        m.calls=m.calls+1
        m.params=params
    end sub}
    m.stack={entries:[{id:"streamsScreen",node:node},{id:"playerScreen"}],pops:0,pushes:0,top:function() as object
        return m.entries[m.entries.Count()-1]
    end function,pop:function() as boolean
        m.entries.Pop(): m.pops=m.pops+1
        return true
    end function,push:sub(id as string,params as object)
        m.pushes=m.pushes+1
    end sub}
    m.playerScreen={allow:true,nextEpisodeRequest:{videoId:"one",params:NextEpisode_Params(EpisodeParams(),EpisodeMeta())},callFunc:function(name as string,id as string) as boolean
        return m.allow
    end function}
    onNextEpisodeRequest()
    Harness_Equal(m.stack.entries.Count(),1,"old player removed, old streams reused")
    Harness_Equal(m.stack.pushes,0,"no duplicate streams added")
    Harness_Equal(node.params.videoId,"two","existing list receives new episode")
    onNextEpisodeRequest()
    Harness_Equal(m.stack.pops,1,"duplicate event while on sources ignored")
    m.stack.entries.Push({id:"playerScreen"})
    m.playerScreen.allow=false
    onNextEpisodeRequest()
    Harness_Equal(m.stack.pops,1,"stale request cannot stop later playback")
end sub

sub TestEpisodeTimedEvents()
    Harness_Suite("Queued countdown and metadata events respect the current episode's interval")
    EpisodeSetup():m.testTimed=true:m.naturalEnd=true
    ScheduleNextEpisode()
    onNextEpisodeTick()
    Harness_Equal(m.nextEpisodeSeconds,5,"queued old countdown cannot shorten five-second choice")
    Harness_Equal(m.top.nextEpisodeRequest,invalid,"early countdown cannot navigate")
    m.nextEpisodeGuard.clock.elapsed=1000:onNextEpisodeTick()
    Harness_Equal(m.nextEpisodeSeconds,4,"a current second advances exactly once")
    onNextEpisodeTick()
    Harness_Equal(m.nextEpisodeSeconds,4,"duplicate queued tick cannot count another second")
    for second=1 to 4
        m.nextEpisodeGuard.clock.elapsed=1000:onNextEpisodeTick()
    end for
    Harness_Equal(m.top.nextEpisodeRequest.params.videoId,"two","mature countdown still advances to intended episode")
    EpisodeSetup():m.playParams.seriesMeta=invalid
    PrepareNextEpisode(m.playParams)
    onNextEpisodeSetup()
    Harness_Equal(m.launched,0,"old metadata setup event cannot launch early")
    m.nextSetupGuard.clock.elapsed=100:onNextEpisodeSetup()
    Harness_Equal(m.launched,1,"current metadata setup launches once")
    onNextEpisodeSetup()
    Harness_Equal(m.launched,1,"duplicate metadata setup does not launch again")
    EpisodeSetup():m.playParams.autoNextEpisode=false
    PrepareNextEpisode(m.playParams):onNextEpisodeSetup()
    Harness_Equal(m.launched,0,"cancelled setup cannot fetch after autoplay is disabled")
    m.testTimed=false
end sub

TestEpisodePolicy()
TestEpisodeFinishAndCancel()
TestEpisodeMetadataAndRoute()
TestEpisodeTimedEvents()
Harness_Finish()
