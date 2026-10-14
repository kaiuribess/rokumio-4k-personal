' Stream selection for this personal, server-free build.
' Provider names and filenames are hints only; they never prove decoded quality.
function CinemaOptionalText(value as dynamic) as string
    if Type(value) = "String" or Type(value) = "roString" then return value.Trim()
    return ""
end function

function CinemaStreamText(stream as dynamic) as string
    if Type(stream) <> "roAssociativeArray" then return ""
    text = ""
    for each field in ["name", "title", "description", "quality"]
        value = stream[field]
        if Type(value) = "String" or Type(value) = "roString" then text = text + " " + value
    end for
    hints = stream.behaviorHints
    if Type(hints) = "roAssociativeArray"
        if Type(hints.filename) = "String" or Type(hints.filename) = "roString" then text = text + " " + hints.filename
    end if
    return LCase(text)
end function

function CinemaIsHttpsStream(stream as dynamic, patterns = invalid as dynamic) as boolean
    if Type(stream) <> "roAssociativeArray" then return false
    if Type(stream.url) <> "String" and Type(stream.url) <> "roString" then return false
    ' Exclude empty authorities, userinfo, whitespace and non-HTTPS sources.
    url = stream.url.Trim()
    if LCase(Left(url, 8)) <> "https://" then return false
    authority = Mid(url, 9).Split("/")[0].Split("?")[0].Split("#")[0]
    if authority = "" or authority.InStr("@") >= 0 then return false
    if patterns = invalid then whitespace = CreateObject("roRegex", "\s", "") else whitespace = patterns.whitespace
    return not whitespace.IsMatch(url)
end function

function CinemaIs4KLabel(stream as dynamic) as boolean
    pattern = CreateObject("roRegex", "(^|[^a-z0-9])(2160p?|4k|uhd)([^a-z0-9]|$)", "i")
    return pattern.IsMatch(CinemaStreamText(stream))
end function

' Torrentio emits HTTPS status clips and download-to-debrid placeholders as
' streams. Neither is a ready movie, even when its name includes 2160p.
' Match the inspected protocol shapes, not arbitrary movie words such as Error.
function CinemaSourceBlockReason(stream as dynamic, patterns = invalid as dynamic) as string
    if Type(stream) <> "roAssociativeArray" then return ""
    name = LCase(CinemaOptionalText(stream.name))
    providers = "(tb|rd|ad|dl|pm|oc|ed|hw|putio)"
    if patterns = invalid then download = CreateObject("roRegex", "\[" + providers + "[ ]+download\]", "i") else download = patterns.download
    if download.IsMatch(name) then return "uncached"
    if patterns = invalid then error = CreateObject("roRegex", "(^|[^a-z0-9])" + providers + "[ ]+error([^a-z0-9]|$)", "i") else error = patterns.providerError
    if name.InStr("torrentio") >= 0 and error.IsMatch(name) then return "provider-status"
    url = LCase(CinemaOptionalText(stream.url))
    if Left(url, 8) <> "https://" then return ""
    rest = Mid(url, 9)
    slash = rest.InStr("/")
    if slash < 0 then return ""
    host = Left(rest, slash).Split(":")[0]
    if host <> "torrentio.strem.fun" and host <> "torrentio.elfhosted.com" then return ""
    path = Mid(rest, slash + 1).Split("?")[0].Split("#")[0]
    for each clip in ["downloading_v3.mp4", "download_failed_v3.mp4", "failed_access_v3.mp4", "failed_rar_v3.mp4", "failed_too_big_v2.mp4", "failed_opening_v3.mp4", "failed_unexpected_v3.mp4", "failed_infringement_v3.mp4", "limits_exceeded_v2.mp4", "blocked_access_v2.mp4", "failed_unavailable_v1.mp4"]
        if path = "/videos/" + clip then return "provider-status"
    end for
    return ""
end function

function CinemaSkippedSources(streams as dynamic) as object
    counts = { uncached: 0, status: 0 }
    if Type(streams) <> "roArray" then return counts
    patterns = CinemaSourcePatterns()
    for each stream in streams
        reason = CinemaSourceBlockReason(stream, patterns)
        if reason = "uncached" then counts.uncached = counts.uncached + 1
        if reason = "provider-status" then counts.status = counts.status + 1
    end for
    return counts
end function

function CinemaQualityLabel(stream as dynamic) as string
    if CinemaIs4KLabel(stream) then return "2160p / 4K source label"
    hd = CreateObject("roRegex", "(^|[^a-z0-9])1080p?([^a-z0-9]|$)", "i")
    if hd.IsMatch(CinemaStreamText(stream)) then return "1080p source label"
    return "Resolution not supplied"
end function

function CinemaSourcePatterns() as object
    return {
        whitespace: CreateObject("roRegex", "\s", "")
        fourK: CreateObject("roRegex", "(^|[^a-z0-9])(2160p?|4k|uhd)([^a-z0-9]|$)", "i")
        hevc: CreateObject("roRegex", "(^|[^a-z0-9])(hevc|h[ ._-]?265|x265)([^a-z0-9]|$)", "i")
        ddplus: CreateObject("roRegex", "(ddp|dd\+|e[ ._-]?ac[ ._-]?3|dolby digital plus)", "i")
        aac: CreateObject("roRegex", "(^|[^a-z0-9])aac([ ._-]?[1-8][ ._-][01])?([^a-z0-9]|$)", "i")
        stereoAac: CreateObject("roRegex", "(^|[^a-z0-9])(aac[ ._-]?(1[ ._-]0|2[ ._-]0|2ch|stereo)|(1[ ._-]0|2[ ._-]0|2ch|stereo)[ ._-]?aac)([^a-z0-9]|$)", "i")
        multichannelAac: CreateObject("roRegex", "(^|[^a-z0-9])(aac[ ._-]?(5[ ._-]1|7[ ._-]1|6ch|8ch)|(5[ ._-]1|7[ ._-]1|6ch|8ch)[ ._-]?aac)([^a-z0-9]|$)", "i")
        stereo: CreateObject("roRegex", "(^|[^a-z0-9])(2[ ._-]0|stereo)([^a-z0-9]|$)", "i")
        dd: CreateObject("roRegex", "(^|[^a-z0-9])(ac[ ._-]?3|dd|dolby digital)([^a-z0-9]|$)", "i")
        incompatibleProjector: CreateObject("roRegex", "(^|[^a-z0-9])(dts[a-z-]*|truehd|ddp|dd\+|e[ ._-]?ac[ ._-]?3|ac[ ._-]?3|dolby digital)([^a-z0-9]|$)", "i")
        dv: CreateObject("roRegex", "(^|[^a-z0-9])(dv|dolby vision)([^a-z0-9]|$)", "i")
        download: CreateObject("roRegex", "\[(tb|rd|ad|dl|pm|oc|ed|hw|putio)[ ]+download\]", "i")
        providerError: CreateObject("roRegex", "(^|[^a-z0-9])(tb|rd|ad|dl|pm|oc|ed|hw|putio)[ ]+error([^a-z0-9]|$)", "i")
    }
end function

function CinemaStreamRank(stream as dynamic, patterns = invalid as dynamic, audioMode = "surround" as string) as integer
    if patterns = invalid then patterns = CinemaSourcePatterns()
    text = CinemaStreamText(stream)
    score = 0
    if patterns.fourK.IsMatch(text) then score = score + 1000
    hevc = patterns.hevc
    if hevc.IsMatch(text) then score = score + 20
    ddplus = patterns.ddplus
    if audioMode = "projector"
        if patterns.aac.IsMatch(text)
            score = score + 100
            ' In automatic projector mode, a stereo AAC hint gets tried before
            ' an unknown 4K audio layout. Native file/audio checks still decide
            ' compatibility; this ranking must never authorize audio by itself.
            if patterns.stereoAac.IsMatch(text) then score = score + 1200
        end if
    else
        if ddplus.IsMatch(text) then score = score + 100
        if patterns.dd.IsMatch(text) then score = score + 70
    end if
    ' Prefer HDR10 or SDR over DV-only, and compatible audio over TrueHD-only.
    dv = patterns.dv
    if dv.IsMatch(text) and text.InStr("hdr10") < 0 then score = score - 60
    if text.InStr("truehd") >= 0 and not ddplus.IsMatch(text) then score = score - 45
    return score
end function

function CinemaChooseStreams(streams as dynamic, fourKOnly as boolean, audioMode = "surround" as string, checkAudioHints = true as boolean) as object
    result = []
    if Type(streams) <> "roArray" then return result
    patterns = CinemaSourcePatterns()
    ranked = []
    for each stream in streams
        if CinemaIsHttpsStream(stream, patterns) and CinemaSourceBlockReason(stream, patterns) = ""
            include = true
            if audioMode = "projector" and checkAudioHints
                text = CinemaStreamText(stream)
                if (patterns.incompatibleProjector.IsMatch(text) or patterns.ddplus.IsMatch(text)) and not patterns.aac.IsMatch(text) then include = false
            end if
            if fourKOnly and include then include = patterns.fourK.IsMatch(CinemaStreamText(stream))
            if include
                ' Score each source once. Re-ranking every comparison exhausted
                ' the Roku render thread when providers returned hundreds of files.
                ranked.Push({ rank: CinemaStreamRank(stream, patterns, audioMode), stream: stream })
            end if
        end if
    end for
    ' Roku's native SortBy is stable, including reverse order. Equal hints
    ' therefore retain the provider's original order without mutating its records.
    ranked.SortBy("rank", "r")
    for each entry in ranked
        result.Push(entry.stream)
    end for
    return result
end function

' Status counts never need a ranking or sort.
function CinemaCountReadyStreams(streams as dynamic) as integer
    if Type(streams) <> "roArray" then return 0
    count = 0
    patterns = CinemaSourcePatterns()
    for each stream in streams
        if CinemaIsHttpsStream(stream, patterns) and CinemaSourceBlockReason(stream, patterns) = "" then count = count + 1
    end for
    return count
end function

' Reuse the worker's sorted ready list when the remote toggles the 4K filter.
function CinemaFilterReadyStreams(streams as dynamic, fourKOnly as boolean) as object
    if Type(streams) <> "roArray" then return []
    if not fourKOnly then return streams
    result = []
    pattern = CreateObject("roRegex", "(^|[^a-z0-9])(2160p?|4k|uhd)([^a-z0-9]|$)", "i")
    for each stream in streams
        if pattern.IsMatch(CinemaStreamText(stream)) then result.Push(stream)
    end for
    return result
end function

function CinemaSourceNotice(stream as dynamic, audioMode = "surround" as string) as string
    text = CinemaStreamText(stream)
    note = "Quality from source label; check playback details."
    if audioMode = "projector" then note = "Projector audio: prefer AAC stereo; source labels are hints."
    if text.InStr("truehd") >= 0
        note = "TrueHD unsupported on Roku; choose a DD/DD+ track."
    end if
    dv = CreateObject("roRegex", "(^|[^a-z0-9])(dv|dolby vision)([^a-z0-9]|$)", "i")
    if dv.IsMatch(text) and text.InStr("hdr10") < 0
        note = "Dolby Vision label: HDR10 fallback not confirmed."
    end if
    return note
end function

' Three readable lines, never provider filenames, emoji or private URLs.
function CinemaCleanSourceLines(stream as object, audioMode as string) as object
    text = CinemaStreamText(stream)
    patterns = CinemaSourcePatterns()
    tags = []
    if patterns.aac.IsMatch(text)
        label = "AAC hint"
        stereo = patterns.stereoAac.IsMatch(text)
        multichannel = patterns.multichannelAac.IsMatch(text)
        if stereo and multichannel
            label = "AAC mixed-layout hints"
        else if stereo
            label = "AAC 1-2 channel hint"
        else if multichannel
            label = "AAC multichannel hint"
        end if
        tags.Push(label)
    end if
    if patterns.ddplus.IsMatch(text) then tags.Push("DD+ hint") else if patterns.dd.IsMatch(text) then tags.Push("DD hint")
    if tags.Count() = 0 then tags.Push("Audio checked during playback")
    if patterns.hevc.IsMatch(text) then tags.Push("HEVC")
    if text.InStr("hdr10+") >= 0 then tags.Push("HDR10+") else if text.InStr("hdr10") >= 0 or text.InStr("hdr") >= 0 then tags.Push("HDR")
    line = ""
    for each tag in tags
        if line <> "" then line = line + "  ·  "
        line = line + tag
    end for
    lines = [line, "English audio checked before sound is enabled"]
    if Type(stream.behaviorHints) = "roAssociativeArray"
        size = stream.behaviorHints.videoSize
        if Type(size) = "Integer" or Type(size) = "LongInteger" or Type(size) = "Float" or Type(size) = "Double" or Type(size) = "roLongInteger"
            if size > 0 then lines.Push(Str(Int(CDbl(size) / 1073741824.0 * 10 + 0.5) / 10.0).Trim() + " GB")
        end if
    end if
    if lines.Count() < 3
        sizePattern = CreateObject("roRegex", "([0-9]+([.][0-9]+)?)[ ]*(gib|gb|mib|mb)([^a-z]|$)", "i")
        matches = sizePattern.Match(text)
        if matches.Count() > 3 then lines.Push(matches[1] + " " + UCase(matches[3]))
    end if
    if lines.Count() < 3 then lines.Push("Automatic fallback if this source cannot play")
    return lines
end function
