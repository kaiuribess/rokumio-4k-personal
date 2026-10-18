' Playback facts only. No URL, header, source title, or player error text is
' emitted: all can contain account keys. Source quality is an unverified label.
function PlaybackInfo_SourceLabel(stream as dynamic) as string
    if Type(stream) <> "roAssociativeArray" then return "Unspecified"
    text = ""
    for each key in ["name", "title", "description"]
        value = PlaybackInfo_Text(stream[key])
        text = text + " " + LCase(value)
    end for
    if Type(stream.behaviorHints) = "roAssociativeArray" then
        text = text + " " + LCase(PlaybackInfo_Text(stream.behaviorHints.filename))
    end if
    if PlaybackInfo_HasToken(text, "2160p") or PlaybackInfo_HasToken(text, "4k") or PlaybackInfo_HasToken(text, "uhd") then return "2160p / UHD (source label)"
    if PlaybackInfo_HasToken(text, "1080p") then return "1080p (source label)"
    if PlaybackInfo_HasToken(text, "720p") then return "720p (source label)"
    return "Unspecified"
end function

' A bitrate such as 384kbps contains "4k" but is not a resolution label.
function PlaybackInfo_HasToken(text as string, token as string) as boolean
    letters = "abcdefghijklmnopqrstuvwxyz0123456789"
    at = text.InStr(token)
    while at >= 0
        beforeOk = at = 0
        if at > 0 then beforeOk = letters.InStr(text.Mid(at - 1, 1)) < 0
        after = at + token.Len()
        afterOk = after >= text.Len()
        if after < text.Len() then afterOk = letters.InStr(text.Mid(after, 1)) < 0
        if beforeOk and afterOk then return true
        text = text.Mid(at + 1)
        at = text.InStr(token)
    end while
    return false
end function

function PlaybackInfo_ResumeOffset(value as dynamic) as dynamic
    kind = Type(value)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return 0
    if value > 0 and value < 2147483647 then return value
    return 0
end function

function PlaybackInfo_SubtitleUrl(track as dynamic) as string
    if Type(track) <> "roAssociativeArray" then return ""
    for each key in ["url", "downloadUrl"]
        url = PlaybackInfo_Text(track[key])
        scheme = LCase(url)
        if scheme.Left(8) = "https://" or scheme.Left(7) = "http://" then return url
    end for
    return ""
end function

function PlaybackInfo_Text(value as dynamic) as string
    if value = invalid then return ""
    kind = Type(value)
    if kind = "String" or kind = "roString" then return value.Trim()
    return ""
end function

function PlaybackInfo_Codec(value as dynamic, audio = false as boolean) as string
    codec = LCase(PlaybackInfo_Text(value))
    if codec = "" or codec = "none" or codec = "unknown" then return "Not reported"
    if audio
        if codec = "eac3" then return "Dolby Digital Plus (E-AC3)"
        if codec = "ac3" then return "Dolby Digital (AC3)"
        if codec = "dts" then return "DTS"
        if codec = "aac" or codec = "aac_adif" or codec = "aac_adts" or codec = "aac_latm" then return "AAC"
        if codec = "pcm" then return "PCM"
        if codec = "flac" then return "FLAC"
        if codec = "mat" then return "Dolby MAT / TrueHD"
    else
        if codec = "hevc" or codec = "hevc_b" then return "HEVC / H.265"
        if codec = "mpeg4_10b" or codec = "mpeg4_15" or codec = "avc" then return "AVC / H.264"
        if codec = "vp9" then return "VP9"
        if codec = "av1" then return "AV1"
    end if
    ' Do not display arbitrary values from a provider or player diagnostic.
    return "Other reported codec"
end function

function PlaybackInfo_Segment(segment as dynamic) as string
    if Type(segment) <> "roAssociativeArray" then return "Playing resolution: not reported by Roku for this source."
    width = segment.width
    height = segment.height
    if not PlaybackInfo_PositiveDimension(width) or not PlaybackInfo_PositiveDimension(height) then
        return "Playing resolution: not reported by Roku for this source."
    end if
    label = "Playing segment: " + Int(width).ToStr() + " x " + Int(height).ToStr()
    hdr = LCase(PlaybackInfo_Text(segment.hdrModeStr))
    if hdr = "hdr10" then label = label + " | HDR10"
    if hdr = "hdr10+" then label = label + " | HDR10+"
    if hdr = "hlg10" then label = label + " | HLG"
    if hdr = "dolby_vision" then label = label + " | Dolby Vision"
    if hdr = "none" then label = label + " | SDR"
    return label
end function

function PlaybackInfo_PositiveDimension(value as dynamic) as boolean
    if value = invalid then return false
    kind = Type(value)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return false
    return value > 0 and value <= 16384 and Int(value) = value
end function

function PlaybackInfo_ErrorMessage(code as dynamic, category as dynamic, unsupported as boolean) as string
    if unsupported then return "Format not supported. Choose HEVC video with DD+ or AC3 audio. Press Back for another source."
    kind = LCase(PlaybackInfo_Text(category))
    if kind = "drm" or code = -6 then return "This source requires playback authorization this app cannot provide. Press Back for another source."
    if kind = "http" or code = -1 or code = -2 then return "Source unavailable or timed out. Check your provider, or press Back for another source."
    return "Playback failed. Press Back and choose another source."
end function

' Device output and capabilities are kept separate from the playing picture.
' A 2160p HDMI signal can carry an upscaled lower-resolution source.
function PlaybackInfo_OutputMode(value as dynamic) as string
    mode = LCase(PlaybackInfo_Text(value))
    allowed = ["2160p60", "2160p50", "2160p30", "2160p25", "2160p24", "2160p", "2160p60b10", "2160p50b10", "2160p30b10", "2160p25b10", "2160p24b10", "2160p60dv", "2160p30dv", "1080p60", "1080p60b10", "1080p60dv", "1080p50", "1080p30", "1080p25", "1080p24", "1080p", "1080i60", "1080i", "720p60", "720p50", "720p", "480p", "480i", "576p", "576i"]
    for each known in allowed
        if mode = known then return mode
    end for
    return "not reported"
end function

function PlaybackInfo_Capability(value as dynamic) as string
    kind = Type(value)
    if kind <> "Boolean" and kind <> "roBoolean" then return "not reported"
    if value then return "yes"
    return "no"
end function

function PlaybackInfo_DeviceFacts(info as dynamic) as string
    if Type(info) <> "roAssociativeArray" then info = {}
    return "HDMI output at start: " + PlaybackInfo_OutputMode(info.outputMode) + " (signal only)" + Chr(10) + "Capabilities at start: HEVC " + PlaybackInfo_Capability(info.hevcSupported) + " | HDR10 " + PlaybackInfo_Capability(info.hdr10Supported)
end function

' Average container rate is a size/duration estimate. It is neither the peak
' video bitrate nor the host's measured download speed. No URL/filename exits.
function PlaybackInfo_FileFacts(media as dynamic, duration as dynamic) as object
    result = {declaredFileBytes:invalid,nativeDurationSeconds:invalid,averageContainerBitsPerSecond:invalid,measurement:"server-declared-size-divided-by-native-duration"}
    if Type(media) = "roAssociativeArray"
        size = media.declaredFileBytes
        if PlaybackInfo_BoundedNumber(size,1,1099511627776#)
            ' Int returns a 32-bit value on Roku; check only the small residual
            ' so ordinary multi-gigabyte totals do not overflow or saturate.
            millions = Int(size / 1000000#)
            residual = size - millions * 1000000#
            if Int(residual) = residual then result.declaredFileBytes = size
        end if
    end if
    ' Caller supplies only a fresh, source-generation-correlated duration
    ' event. Polling the reused Video node can return a previous file's value.
    if PlaybackInfo_BoundedNumber(duration,1,604800) then result.nativeDurationSeconds = duration
    if result.declaredFileBytes <> invalid and result.nativeDurationSeconds <> invalid
        rate = result.declaredFileBytes * 8# / result.nativeDurationSeconds
        if PlaybackInfo_BoundedNumber(rate,1,2147483647) then result.averageContainerBitsPerSecond = rate
    end if
    return result
end function

function PlaybackInfo_BoundedNumber(value as dynamic, minimum as double, maximum as double) as boolean
    kind = Type(value)
    if kind <> "Integer" and kind <> "roInt" and kind <> "roInteger" and kind <> "LongInteger" and kind <> "roLongInteger" and kind <> "Float" and kind <> "roFloat" and kind <> "Double" and kind <> "roDouble" then return false
    return value >= minimum and value <= maximum
end function
