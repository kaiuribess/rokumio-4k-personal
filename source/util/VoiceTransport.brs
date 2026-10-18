' Pure policy for native voice playback; no network or SceneGraph calls.
' The caller applies control/seek and passes status to roInput.EventResponse.
function VoicePlaybackDecision(info as dynamic, playback as dynamic) as object
    result = { status: "unhandled" }
    if info = invalid or Type(info) <> "roAssociativeArray" then return result
    if info.type <> "transport" or info.command = invalid then return result
    command = info.command
    if command <> "play" and command <> "resume" and command <> "pause" and command <> "seek" and command <> "startover"
        return result
    end if
    if playback = invalid or Type(playback) <> "roAssociativeArray"
        result.status = "error.no-media"
        return result
    end if
    if playback.state <> "playing" and playback.state <> "paused"
        result.status = "error.no-media"
        return result
    end if

    if command = "play" or command = "resume"
        result.autoplayAfterSeek = true
        if playback.state = "paused" then result.control = "resume"
        result.status = "success"
        return result
    end if
    if command = "pause"
        if playback.state = "paused"
            result.status = "error.redundant"
            return result
        end if
        result.control = "pause"
        result.status = "success"
        return result
    end if
    if command = "startover"
        result.autoplayAfterSeek = true
        result.seek = 0
        if playback.state = "paused" then result.control = "resume"
        result.status = "success"
        return result
    end if

    ' A seek is a signed offset, never an absolute timestamp. Ignore malformed
    ' requests rather than seeking to zero accidentally after string coercion.
    if info.direction <> "forward" and info.direction <> "backward"
        result.status = "error.generic"
        return result
    end if
    value = info.duration
    if Type(value) <> "String" and Type(value) <> "roString"
        result.status = "error.generic"
        return result
    end if
    if Len(value) > 10 or not CreateObject("roRegex", "^[0-9]+$", "").IsMatch(value)
        result.status = "error.generic"
        return result
    end if
    ' Parse the bounded integer offset without single-precision rounding or
    ' overflow from ToFloat. Native event durations are decimal strings.
    offset = 0#
    for index = 1 to Len(value)
        offset = offset * 10# + Asc(Mid(value,index,1)) - 48
    end for
    if VoicePlayback_Number(offset) = invalid
        result.status = "error.generic"
        return result
    end if
    if info.direction = "backward" then offset = -offset
    position = VoicePlayback_Number(playback.position)
    if position = invalid
        result.status = "error.generic"
        return result
    end if
    target = position + offset
    result.status = "success"
    if target < 0
        target = 0
        result.status = "success.seek-start"
    end if
    duration = VoicePlayback_Number(playback.duration)
    if duration <> invalid and duration > 0 and target >= duration
        ' Avoid seeking exactly to EOF, which otherwise finishes the video.
        target = duration - 1
        if target < 0 then target = 0
        result.status = "success.seek-end"
    end if
    if VoicePlayback_Number(target) = invalid
        result.status = "error.generic"
        return result
    end if
    result.seek = target
    result.autoplayAfterSeek = playback.state = "playing"
    return result
end function

' SG numeric fields can arrive boxed. Accept their numeric interfaces while
' rejecting strings, booleans, negative/nonfinite values and absurd offsets.
' Arithmetic unboxes wrappers before assigning the native seek field.
function VoicePlayback_Number(value as dynamic) as dynamic
    kind = Type(value)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "LongInteger" and kind <> "roLongInteger" and kind <> "roInt64" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return invalid
    value = value + 0#
    if value >= 0 and value <= 2147483647 then return value
    return invalid
end function
