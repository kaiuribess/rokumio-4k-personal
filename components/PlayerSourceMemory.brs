' Outcomes contain only hashed file identities. The write worker is serialized
' and launched from a timer, outside native Video observer callbacks.
sub InitSourceMemory()
    m.sourceProofTimer = m.top.FindNode("sourceProofTick")
    m.sourceMemoryPump = m.top.FindNode("sourceMemoryPump")
    if m.sourceProofTimer <> invalid then m.sourceProofTimer.ObserveField("fire","onSourceProofTick")
    if m.sourceMemoryPump <> invalid then m.sourceMemoryPump.ObserveField("fire","onSourceMemoryPump")
    m.sourceMemoryPending = []
    m.sourceMemoryTask = invalid
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
    if Type(m.sourceMemoryPending) <> "roArray" then m.sourceMemoryPending = []
    if m.sourceMemoryPending.Count() >= 64 then m.sourceMemoryPending.Shift()
    m.sourceMemoryPending.Push({key:m.sourceAttemptKey,outcome:outcome})
    if m.sourceMemoryPump <> invalid then m.sourceMemoryPump.control = "start"
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
    end if
end sub

sub onSourceMemoryPump()
    if m.sourceMemoryTask <> invalid then return
    if Type(m.sourceMemoryPending) <> "roArray" or m.sourceMemoryPending.Count() = 0 then return
    batch = m.sourceMemoryPending
    m.sourceMemoryPending = []
    m.sourceMemoryTask = AsyncTask_Launch(m.top,"SourceMemoryWriteTask","onSourceMemorySaved",{events:batch},NextPlayerWorkerId("sourceMemory"))
end sub

sub onSourceMemorySaved(event as object)
    if m.sourceMemoryTask = invalid then return
    task = event.GetRoSGNode()
    if task = invalid or task.id <> m.sourceMemoryTask.id then return
    result = event.GetData()
    if Type(result) <> "roAssociativeArray" then return
    m.sourceMemoryTask = invalid
    AsyncTask_Reap(task,m.top,false)
    if result.saved = true then m.memorySaved = true
    if m.sourceMemoryPump <> invalid and Type(m.sourceMemoryPending) = "roArray" and m.sourceMemoryPending.Count() > 0 then m.sourceMemoryPump.control = "start"
end sub
