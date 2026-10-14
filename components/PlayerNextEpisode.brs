' All navigation/workers run outside the native Video state observer. The
' finished observer only arms a pre-existing timer, as the play-kick does.
sub InitNextEpisode()
    m.nextEpisodeTimer = m.top.FindNode("nextEpisodeCountdown")
    m.nextEpisodeSetup = m.top.FindNode("nextEpisodeSetup")
    m.nextEpisodeTimer.ObserveField("fire", "onNextEpisodeTick")
    m.nextEpisodeSetup.ObserveField("fire", "onNextEpisodeSetup")
    m.nextEpisodeTask = invalid
    m.nextEpisodeMeta = invalid
    m.nextEpisodePending = false
    m.naturalEnd = false
end sub

sub PrepareNextEpisode(params as object)
    CancelNextEpisode()
    m.naturalEnd = false
    m.nextEpisodeMeta = params.seriesMeta
    if params.metaType <> "series" or params.diagnostic = true or params.autoNextEpisode = false then return
    if Type(m.nextEpisodeMeta) = "roAssociativeArray" and Type(m.nextEpisodeMeta.videos) = "roArray" and m.nextEpisodeMeta.videos.Count() > 0 then return
    if NextEpisode_Text(params.addonAddress) = "" or NextEpisode_Text(params.metaId) = "" then return
    m.nextSetupPending = true
    m.nextSetupGuard = TimerGuard_Start(m.nextEpisodeSetup,100)
end sub

sub onNextEpisodeSetup()
    if m.nextSetupPending <> true then return
    if m.playbackActive <> true or m.top.screenActive <> true then return
    if not TimerGuard_Ready(m.nextEpisodeSetup,m.nextSetupGuard) then return
    m.nextSetupPending = false
    if Type(m.playParams) <> "roAssociativeArray" or m.playParams.metaType <> "series" or m.playParams.diagnostic = true or m.playParams.autoNextEpisode = false then return
    if m.nextEpisodeTask <> invalid then return
    m.nextEpisodeTask = AsyncTask_Launch(m.top, "MetaLoaderTask", "onNextEpisodeMetaLoaded", {addonAddress:NextEpisode_Text(m.playParams.addonAddress),metaType:"series",metaId:NextEpisode_Text(m.playParams.metaId)}, NextPlayerWorkerId("nextEpisodeMeta"))
end sub

sub onNextEpisodeMetaLoaded(event as object)
    if m.nextEpisodeTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.nextEpisodeTask.id then return
    result = event.GetData()
    if Type(result) <> "roAssociativeArray" then return
    m.nextEpisodeTask = invalid
    AsyncTask_Reap(task, m.top, false)
    if m.playbackActive <> true or m.top.screenActive <> true then return
    if result.ok = true and Type(result.meta) = "roAssociativeArray" then m.nextEpisodeMeta = result.meta
end sub

function NextEpisodeClock() as string
    if m.stores <> invalid and m.stores.time <> invalid
        try
            return NextEpisode_Text(m.stores.time.callFunc("TimeNowIso"))
        catch e
        end try
    end if
    return ""
end function

function ScheduleNextEpisode() as boolean
    if m.nextEpisodePending = true then return true
    if m.playbackActive <> true or m.top.screenActive <> true or m.sourceAccepted <> true or m.hasPlayed <> true then return false
    nextParams = NextEpisode_Params(m.playParams, m.nextEpisodeMeta, NextEpisodeClock())
    if nextParams = invalid or m.nextEpisodeTimer = invalid then return false
    m.nextEpisodeParams = nextParams
    m.nextEpisodeSeconds = 5
    m.nextEpisodePending = true
    UpdateNextEpisodeCountdown()
    m.nextEpisodeGuard = TimerGuard_Start(m.nextEpisodeTimer,1000)
    return true
end function

sub UpdateNextEpisodeCountdown()
    params = m.nextEpisodeParams
    label = "Next: S" + params.season.ToStr() + " E" + params.episode.ToStr()
    if NextEpisode_Text(params.episodeName) <> "" then label = label + " · " + params.episodeName
    m.status.text = label + Chr(10) + "Starting in " + m.nextEpisodeSeconds.ToStr() + " seconds · Back cancels"
end sub

sub onNextEpisodeTick()
    if m.nextEpisodePending <> true then return
    if m.playbackActive <> true or m.top.screenActive <> true or m.video = invalid
        CancelNextEpisode()
        return
    end if
    if m.video.state <> "finished" or m.naturalEnd <> true or m.sourceAccepted <> true
        CancelNextEpisode()
        return
    end if
    if not TimerGuard_Ready(m.nextEpisodeTimer,m.nextEpisodeGuard) then return
    m.nextEpisodeSeconds = m.nextEpisodeSeconds - 1
    if m.nextEpisodeSeconds > 0
        m.nextEpisodeGuard = TimerGuard_Start(m.nextEpisodeTimer,1000)
        UpdateNextEpisodeCountdown()
        return
    end if
    ' Recheck the date; never retain signed URLs or resume the previous file.
    params = NextEpisode_Params(m.playParams, m.nextEpisodeMeta, NextEpisodeClock())
    m.nextEpisodePending = false
    m.nextEpisodeTimer.control = "stop"
    if params = invalid then return
    SavePosition()
    m.top.nextEpisodeRequest = {videoId:NextEpisode_Text(m.playParams.videoId),params:params}
end sub

sub CancelNextEpisode()
    m.nextEpisodePending = false
    m.nextSetupPending = false
    m.nextEpisodeGuard = invalid
    m.nextSetupGuard = invalid
    m.nextEpisodeParams = invalid
    if m.nextEpisodeTimer <> invalid then m.nextEpisodeTimer.control = "stop"
    if m.nextEpisodeSetup <> invalid then m.nextEpisodeSetup.control = "stop"
    if m.nextEpisodeTask <> invalid
        task = m.nextEpisodeTask
        m.nextEpisodeTask = invalid
        AsyncTask_Reap(task, m.top, true)
    end if
end sub

function CanAdvanceEpisode(videoId as string) as boolean
    if m.sourceAccepted <> true or m.hasPlayed <> true then return false
    if m.playbackActive <> true or m.top.screenActive <> true or m.naturalEnd <> true or m.video = invalid then return false
    if Type(m.playParams) <> "roAssociativeArray" or m.video.state <> "finished" then return false
    return NextEpisode_Text(m.playParams.videoId) = videoId and m.playParams.metaType = "series" and m.playParams.diagnostic <> true
end function
