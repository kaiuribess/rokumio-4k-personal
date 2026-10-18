' Outcomes contain only hashed file identities. The write worker is serialized
' and launched from a timer, outside native Video observer callbacks.
sub InitSourceMemory()
    m.sourceProofTimer = m.top.FindNode("sourceProofTick")
    m.sourceMemoryPump = m.top.FindNode("sourceMemoryPump")
    if m.sourceProofTimer <> invalid then m.sourceProofTimer.ObserveField("fire","onSourceProofTick")
    if m.sourceMemoryPump <> invalid then m.sourceMemoryPump.ObserveField("fire","onSourceMemoryPump")
    m.sourceMemoryPending = []
    m.sourceMemoryTask = invalid
    m.sourceMemoryInFlight = []
    m.sourceMemoryRetryCount = 0
    m.sourceMemoryRetryBlocked = false
    m.sourceMemoryRetryGuard = invalid
    m.sourceAttemptKey = ""
    m.memorySaved = false
    ResetSourceProof()
end sub

sub PrepareSourceMemoryAttempt(stream as object)
    ResetSourceProof()
    m.sourceAttemptKey = ""
    if Type(m.playParams) <> "roAssociativeArray" or m.playParams.diagnosticControl = true then return
    try
        m.sourceAttemptKey = SourceMemory_Fingerprint(stream,PlaybackInfo_Text(m.playParams.videoId),PlaybackInfo_Text(m.playParams.audioMode))
    catch e
        ' No usable identity means no memory, not a failed source.
    end try
end sub

sub ResetSourceProof()
    if m.sourceProofTimer <> invalid then m.sourceProofTimer.control = "stop"
    m.sourceProofSamples = invalid
    m.sourceProofSeconds = 0
    m.sourceProofWritten = false
    m.sourceProofArmed = false
    m.sourceFailureWritten = false
end sub

sub QueueSourceOutcome(outcome as string)
    if m.sourceAttemptKey = invalid or m.sourceAttemptKey = "" then return
    m.sourceMemoryPending = MergeSourceOutcomes(m.sourceMemoryPending,[{key:m.sourceAttemptKey,outcome:outcome}])
    m.memorySaved = false
    ' A real new outcome may restart a bounded retry cycle; a queued timer or
    ' duplicate worker result cannot restart it on its own.
    m.sourceMemoryRetryCount = 0
    m.sourceMemoryRetryBlocked = false
    ArmSourceMemoryPump(100)
end sub

' Newer outcomes replace older ones only for the same opaque file key. Keep
' at most 64 latest distinct keys, including when a failed batch is restored.
function MergeSourceOutcomes(older as dynamic, newer as dynamic) as object
    result = []
    for each batch in [older,newer]
        if Type(batch) <> "roArray" then continue for
        for each entry in batch
            if Type(entry) <> "roAssociativeArray" then continue for
            if GetInterface(entry.key,"ifString") = invalid or entry.key = "" then continue for
            if entry.outcome <> "working" and entry.outcome <> "network" and entry.outcome <> "incompatible" then continue for
            for index = result.Count() - 1 to 0 step -1
                if result[index].key = entry.key then result.Delete(index)
            end for
            if result.Count() >= 64 then result.Shift()
            result.Push({key:entry.key,outcome:entry.outcome})
        end for
    end for
    return result
end function

sub ArmSourceMemoryPump(delayMs as integer)
    if m.sourceMemoryPump = invalid or m.sourceMemoryRetryBlocked = true then return
    m.sourceMemoryRetryGuard = TimerGuard_Start(m.sourceMemoryPump,delayMs)
end sub

sub RememberSourceFailure()
    if m.sourceFailureWritten = true then return
    m.sourceFailureWritten = true
    if m.sourceProofTimer <> invalid then m.sourceProofTimer.control = "stop"
    outcome = "network"
    if Type(m.resolvedPlayback) = "roAssociativeArray" and Type(m.resolvedPlayback.audioPolicy) = "roAssociativeArray"
        policy = m.resolvedPlayback.audioPolicy
        if policy.known = true and policy.compatible = false then outcome = "incompatible"
    end if
    QueueSourceOutcome(outcome)
end sub

sub ArmSourceProof()
    if m.playbackActive <> true or m.retryPending = true or m.sourceAccepted <> true or m.video = invalid then return
    if m.video.state <> "playing" or m.video.mute = true then return
    if m.sourceProofTimer = invalid or m.sourceProofWritten = true or m.sourceProofArmed = true then return
    m.sourceProofSamples = invalid
    m.sourceProofSeconds = 0
    m.sourceProofArmed = true
    m.sourceProofTimer.control = "start"
end sub

sub onSourceProofTick()
    if m.playbackActive <> true or m.retryPending = true or m.sourceAccepted <> true or m.video = invalid then return
    if m.sourceProofWritten = true then return
    if m.video.state <> "playing"
        m.sourceProofSamples = invalid
        m.sourceProofSeconds = 0
        m.sourceProofArmed = false
        if m.sourceProofTimer <> invalid then m.sourceProofTimer.control = "stop"
        return
    end if
    audio = CurrentEnglishAudioCheck()
    if audio.verified <> true or m.video.mute = true then return
    if not m.video.HasField("positionInfo") or Type(m.video.positionInfo) <> "roAssociativeArray" then return
    current = {audio:PlaybackInfo_ResumeOffset(m.video.positionInfo.audio),video:PlaybackInfo_ResumeOffset(m.video.positionInfo.video)}
    if current.audio <= 0 or current.video <= 0 then return
    if Type(m.sourceProofSamples) = "roAssociativeArray"
        audioStep = current.audio - m.sourceProofSamples.audio
        videoStep = current.video - m.sourceProofSamples.video
        ' A seek or inherited old samples cannot pass a fresh progress check.
        if audioStep > 0 and audioStep <= 8 and videoStep > 0 and videoStep <= 8
            m.sourceProofSeconds = m.sourceProofSeconds + 5
        else
            m.sourceProofSeconds = 0
        end if
    end if
    m.sourceProofSamples = current
    if m.sourceProofSeconds >= 10
        m.sourceProofWritten = true
        m.sourceProofArmed = false
        if m.sourceProofTimer <> invalid then m.sourceProofTimer.control = "stop"
        QueueSourceOutcome("working")
        RememberWorkingProvider()
    end if
end sub

sub RememberWorkingProvider()
    if Type(m.playParams) <> "roAssociativeArray" or m.playParams.diagnostic = true or m.playParams.diagnosticControl = true then return
    if m.stores = invalid or m.stores.settings = invalid then return
    key = ProviderPriority_StreamKey(m.playParams.stream)
    if key = "" then return
    try
        m.stores.settings.callFunc("SettingsRecordWorkingProviderKey",key)
    catch e
        ' Optional scheduling memory never changes accepted playback.
    end try
end sub

sub onSourceMemoryPump()
    if m.sourceMemoryTask <> invalid then return
    if m.sourceMemoryRetryBlocked = true then return
    if Type(m.sourceMemoryPending) <> "roArray" or m.sourceMemoryPending.Count() = 0 then return
    if not TimerGuard_Ready(m.sourceMemoryPump,m.sourceMemoryRetryGuard) then return
    m.sourceMemoryRetryGuard = invalid
    m.sourceMemoryInFlight = m.sourceMemoryPending
    m.sourceMemoryPending = []
    try
        m.sourceMemoryTask = AsyncTask_Launch(m.top,"SourceMemoryWriteTask","onSourceMemorySaved",{events:m.sourceMemoryInFlight},NextPlayerWorkerId("sourceMemory"))
    catch e
        m.sourceMemoryTask = invalid
    end try
    if m.sourceMemoryTask = invalid then FinishSourceMemoryWrite(false)
end sub

sub onSourceMemorySaved(event as object)
    if m.sourceMemoryTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.sourceMemoryTask.id then return
    result = event.GetData()
    if Type(result) <> "roAssociativeArray" then return
    m.sourceMemoryTask = invalid
    AsyncTask_Reap(task,m.top,false)
    FinishSourceMemoryWrite(result.saved = true)
end sub

sub FinishSourceMemoryWrite(saved as boolean)
    if Type(m.sourceMemoryPending) <> "roArray" then m.sourceMemoryPending = []
    delayMs = 100
    if saved
        m.sourceMemoryRetryCount = 0
        m.sourceMemoryRetryBlocked = false
    else
        m.sourceMemoryPending = MergeSourceOutcomes(m.sourceMemoryInFlight,m.sourceMemoryPending)
        if m.sourceMemoryRetryCount = invalid then m.sourceMemoryRetryCount = 0
        m.sourceMemoryRetryCount = m.sourceMemoryRetryCount + 1
        m.sourceMemoryRetryBlocked = m.sourceMemoryRetryCount > 3
        ' Initial attempt plus at most three timed retries (1,2,4 seconds).
        delayMs = 1000
        if m.sourceMemoryRetryCount = 2 then delayMs = 2000
        if m.sourceMemoryRetryCount >= 3 then delayMs = 4000
    end if
    m.sourceMemoryInFlight = []
    m.memorySaved = saved and m.sourceMemoryPending.Count() = 0
    if m.sourceMemoryRetryBlocked = true
        if m.sourceMemoryPump <> invalid then m.sourceMemoryPump.control = "stop"
    else if m.sourceMemoryPending.Count() > 0
        ArmSourceMemoryPump(delayMs)
    end if
end sub
