' Audio repair is scoped to this source and runs only before it is accepted.
' Native sample progress is decoder evidence, never proof of audible speakers.
sub InitAudioRecovery()
    m.audioProgressTimer = m.top.FindNode("audioProgressTick")
    m.audioRecoveryTimer = m.top.FindNode("audioTrackRepair")
    if m.audioProgressTimer <> invalid then m.audioProgressTimer.ObserveField("fire", "onAudioProgressTick")
    if m.audioRecoveryTimer <> invalid then m.audioRecoveryTimer.ObserveField("fire", "onAudioTrackRepair")
    m.audioRecoveryGeneration = 0
    ResetAudioRecovery()
end sub

sub ResetAudioRecovery()
    if m.audioRecoveryGeneration = invalid then m.audioRecoveryGeneration = 0
    m.audioRecoveryGeneration = m.audioRecoveryGeneration + 1
    if m.audioProgressTimer <> invalid then m.audioProgressTimer.control = "stop"
    if m.audioRecoveryTimer <> invalid then m.audioRecoveryTimer.control = "stop"
    m.audioRecoveryPending = false
    m.audioProgressArmed = false
    m.audioRecoveryTrack = ""
    m.audioRecoveryQueuedGeneration = -1
    m.audioRepairGuard = invalid
    m.audioRecoveryTried = []
    m.audioRecoveryInitialOffset = 0
    m.audioProvenTrack = ""
    m.audioProvenCodec = ""
    m.lastEnglishCodec = ""
    m.audioExplicitRejection = false
    ClearAudioProgress()
end sub

sub ClearAudioProgress()
    m.audioProgressSamples = invalid
    m.audioProgressIntervals = 0
    m.audioProgressPassed = false
end sub

sub BeginAudioRecovery()
    ResetAudioRecovery()
    if Type(m.playParams) = "roAssociativeArray" then m.audioRecoveryInitialOffset = PlaybackInfo_ResumeOffset(m.playParams.position)
end sub

function AudioRecovery_TrackId() as string
    if m.video = invalid or not m.video.HasField("currentAudioTrack") then return ""
    return PlaybackInfo_Text(m.video.currentAudioTrack)
end function

function AudioRecovery_Codec() as string
    if m.video = invalid or not m.video.HasField("audioFormat") then return ""
    return LCase(PlaybackInfo_Text(m.video.audioFormat)).Trim()
end function

function AudioRecovery_CodecAllowed(value as dynamic, mode as string) as boolean
    if EnglishAudio_ProjectorCodec(value) then return true
    codec = LCase(PlaybackInfo_Text(value)).Trim()
    return mode = "surround" and (codec = "ac3" or codec = "eac3")
end function

sub ArmAudioProgress()
    if m.audioProgressArmed = true then return
    if m.audioProgressTimer = invalid then return
    m.audioProgressArmed = true
    m.audioProgressTimer.control = "start"
end sub

function AudioRecovery_TrackKey() as string
    id = AudioRecovery_TrackId()
    if id <> "" then return id
    ' The metadata fallback is limited to an inspected, unambiguous English
    ' file; no inferred native Track ID is ever written to the Video node.
    return "file-English-audio"
end function

function AudioRecovery_HasTried(id as string) as boolean
    if Type(m.audioRecoveryTried) <> "roArray" then return false
    for each previous in m.audioRecoveryTried
        if previous = id then return true
    end for
    return false
end function

sub AudioRecovery_MarkTried(id as string)
    if id = "" or AudioRecovery_HasTried(id) then return
    if Type(m.audioRecoveryTried) <> "roArray" then m.audioRecoveryTried = []
    if m.audioRecoveryTried.Count() < 4 then m.audioRecoveryTried.Push(id)
end sub

function AudioRecovery_Alternatives() as object
    candidates = []
    if m.video = invalid or not m.video.HasField("availableAudioTracks") then return candidates
    tracks = m.video.availableAudioTracks
    if Type(tracks) <> "roArray" then return candidates
    stereo = CreateObject("roRegex", "(^|[^a-z0-9])(2[ ._-]0|stereo)([^a-z0-9]|$)", "i")
    multichannel = CreateObject("roRegex", "(^|[^a-z0-9])(5[ ._-]1|7[ ._-]1|6ch|8ch)([^a-z0-9]|$)", "i")
    dolbyPlus = CreateObject("roRegex", "(ddp|dd\+|e[ ._-]?ac[ ._-]?3|dolby digital plus)", "i")
    dolby = CreateObject("roRegex", "(^|[^a-z0-9])(ac[ ._-]?3|dd|dolby digital)([^a-z0-9]|$)", "i")
    for each track in tracks
        if Type(track) = "roAssociativeArray" and EnglishAudio_IsEnglish(track.Language) and EnglishAudio_IsDialogue(track)
            id = PlaybackInfo_Text(track.Track)
            if id <> "" and Len(id) <= 512 and not AudioRecovery_HasTried(id)
                duplicate = false
                for each entry in candidates
                    if entry.id = id then duplicate = true
                end for
                if not duplicate and candidates.Count() < 32
                    name = LCase(PlaybackInfo_Text(track.Name))
                    rank = 0
                    ' Names only rank alternatives. Their actual decoder and
                    ' rendered samples still must pass after selecting the ID.
                    if name.InStr("aac") >= 0
                        rank = rank + 50
                        if stereo.IsMatch(name) then rank = rank + 40
                        if multichannel.IsMatch(name) then rank = rank - 40
                    end if
                    if name.InStr("mp3") >= 0 then rank = rank + 70
                    if name.InStr("pcm") >= 0 then rank = rank + 60
                    if stereo.IsMatch(name) and (name.InStr("mp3") >= 0 or name.InStr("pcm") >= 0) then rank = rank + 10
                    if Type(m.playParams) = "roAssociativeArray" and m.playParams.audioMode = "surround"
                        if dolbyPlus.IsMatch(name)
                            rank = rank + 220
                            if Type(m.devicePlaybackInfo) = "roAssociativeArray"
                                if AudioCapabilities_ExplicitlyUnsupported(m.devicePlaybackInfo.audioCapabilities,"eac3") then rank = rank - 400
                            end if
                        else if dolby.IsMatch(name)
                            rank = rank + 120
                            if Type(m.devicePlaybackInfo) = "roAssociativeArray"
                                if AudioCapabilities_ExplicitlyUnsupported(m.devicePlaybackInfo.audioCapabilities,"ac3") then rank = rank - 400
                            end if
                        end if
                    end if
                    candidates.Push({id:id,rank:rank})
                end if
            end if
        end if
    end for
    candidates.SortBy("rank", "r")
    return candidates
end function

function QueueAudioTrackRepair() as boolean
    if m.sourceAccepted = true or m.playbackActive <> true or m.retryPending = true or m.audioGuardBlocked = true then return false
    if m.video = invalid or m.video.state <> "playing" or m.audioRecoveryTimer = invalid then return false
    if m.audioRecoveryPending = true then return true
    current = AudioRecovery_TrackId()
    for each alternative in AudioRecovery_Alternatives()
        if alternative.id = current then AudioRecovery_MarkTried(current)
    end for
    if Type(m.audioRecoveryTried) = "roArray" and m.audioRecoveryTried.Count() >= 4 then return false
    alternatives = AudioRecovery_Alternatives()
    if alternatives.Count() = 0 then return false
    m.audioRecoveryTrack = alternatives[0].id
    m.audioRecoveryQueuedGeneration = m.audioRecoveryGeneration
    m.audioRecoveryPending = true
    if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
    m.audioGuardArmed = false
    m.video.mute = true
    m.status.text = "Trying another English audio track…" + Chr(10) + "Back cancels"
    m.audioRepairGuard = TimerGuard_Start(m.audioRecoveryTimer,100)
    return true
end function

sub onAudioTrackRepair()
    if m.audioRecoveryPending <> true then return
    if m.audioRecoveryQueuedGeneration <> m.audioRecoveryGeneration then return
    if not TimerGuard_Ready(m.audioRecoveryTimer,m.audioRepairGuard) then return
    m.audioRecoveryPending = false
    if m.playbackActive <> true or m.retryPending = true or m.sourceAccepted = true or m.audioGuardActive <> true or m.audioGuardBlocked = true then return
    if m.video = invalid or m.video.state <> "playing" then return
    id = m.audioRecoveryTrack
    allowed = false
    for each candidate in AudioRecovery_Alternatives()
        if candidate.id = id then allowed = true
    end for
    if not allowed then return
    AudioRecovery_MarkTried(id)
    ClearAudioProgress()
    ' IDs come directly from the native English dialogue choices. The user
    ' requested automatic audio repair; assignment is deferred out of native
    ' Video observer callbacks and capped at four unique IDs per source.
    m.video.audioTrack = id
    if m.video.HasField("seek") then m.video.seek = m.audioRecoveryInitialOffset
    m.video.mute = true
    m.audioGuardArmed = true
    m.audioGuard = TimerGuard_Start(m.audioGuardTimer,10000)
    ArmAudioProgress()
end sub

sub AudioRecovery_SyncState()
    if m.video = invalid then return
    state = m.video.state
    if state = "playing"
        if m.sourceAccepted <> true then ArmAudioProgress()
        return
    end if
    if m.audioProgressTimer <> invalid then m.audioProgressTimer.control = "stop"
    m.audioProgressArmed = false
    if m.audioRecoveryTimer <> invalid then m.audioRecoveryTimer.control = "stop"
    m.audioRecoveryPending = false
    if m.audioGuardTimer <> invalid then m.audioGuardTimer.control = "stop"
    m.audioGuardArmed = false
    if m.sourceAccepted <> true then ClearAudioProgress()
end sub

sub onAudioProgressTick()
    if m.playbackActive <> true or m.retryPending = true or m.audioGuardActive <> true or m.audioGuardBlocked = true or m.audioRecoveryPending = true then return
    if m.video = invalid or m.video.state <> "playing" then return
    facts = CurrentEnglishAudioFacts()
    if facts.verified <> true
        ClearAudioProgress()
        return
    end if
    if not m.video.HasField("positionInfo") or Type(m.video.positionInfo) <> "roAssociativeArray" then return
    current = {audio:PlaybackInfo_ResumeOffset(m.video.positionInfo.audio),video:PlaybackInfo_ResumeOffset(m.video.positionInfo.video),track:AudioRecovery_TrackKey(),codec:AudioRecovery_Codec()}
    if current.audio <= 0 or current.video <= 0 then return
    if Abs(current.audio-current.video) > 3
        ClearAudioProgress()
        return
    end if
    if Type(m.audioProgressSamples) = "roAssociativeArray"
        audioStep = current.audio - m.audioProgressSamples.audio
        videoStep = current.video - m.audioProgressSamples.video
        sameTrack = current.track = m.audioProgressSamples.track and current.codec = m.audioProgressSamples.codec
        ' Duplicate samples, seek jumps and retained previous-file facts cannot
        ' establish two consecutive intervals of new rendered audio and video.
        if sameTrack and audioStep > 0 and audioStep <= 3 and videoStep > 0 and videoStep <= 3
            m.audioProgressIntervals = m.audioProgressIntervals + 1
        else
            m.audioProgressIntervals = 0
            m.audioProgressPassed = false
        end if
    end if
    m.audioProgressSamples = current
    if m.audioProgressIntervals >= 2
        m.audioProgressPassed = true
        m.audioProvenTrack = current.track
        m.audioProvenCodec = current.codec
        onEnglishAudioFactsChanged()
    end if
end sub

sub StopAudioRecoveryTimers()
    if m.audioProgressTimer <> invalid then m.audioProgressTimer.control = "stop"
    m.audioProgressArmed = false
    if m.audioRecoveryTimer <> invalid then m.audioRecoveryTimer.control = "stop"
    m.audioRecoveryPending = false
end sub
