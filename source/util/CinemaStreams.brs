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

function CinemaResolutionHint(stream as dynamic, patterns = invalid as dynamic) as integer
    if Type(stream) <> "roAssociativeArray" then return 0
    if patterns = invalid then patterns = CinemaResolutionPatterns()
    ' A release filename/descriptive resolution is more specific than a
    ' provider's badge. In particular, "4K remastered 1080p" is an HD file.
    filename = ""
    if Type(stream.behaviorHints) = "roAssociativeArray" then filename = CinemaOptionalText(stream.behaviorHints.filename)
    for each text in [filename, CinemaOptionalText(stream.title) + " " + CinemaOptionalText(stream.description), CinemaOptionalText(stream.quality), CinemaOptionalText(stream.name)]
        for each hint in patterns.resolutions
            if hint.pattern.IsMatch(text) then return hint.height
        end for
        ' Aliases keep the same field precedence as numeric resolution.
        ' Within one field, an explicit 1080p still beats "4K remastered".
        if patterns.fourK.IsMatch(text) then return 2160
    end for
    return 0
end function

function CinemaIs4KLabel(stream as dynamic, patterns = invalid as dynamic) as boolean
    return CinemaResolutionHint(stream, patterns) = 2160
end function

' An explicit language label is only a sorting/filter hint. Actual native
' track metadata still authorizes audio. Mixed or unspecified audio survives.
function CinemaEnglishHint(stream as dynamic, patterns = invalid as dynamic) as integer
    if patterns = invalid then patterns = CinemaSourcePatterns()
    text = CinemaStreamText(stream)
    foreignOnly = patterns.foreignOnly.IsMatch(text)
    if Type(stream) = "roAssociativeArray"
        if patterns.foreignName.IsMatch(CinemaOptionalText(stream.name)) then foreignOnly = true
    end if
    if foreignOnly
        ' A film/provider name containing English cannot cancel an explicit
        ' foreign-only audio annotation. Keep an actual English alternate or
        ' contradictory multilingual annotation eligible for native inspection.
        ' Keep annotation boundaries: title "Johnny English" followed by
        ' description "Audio: Hindi only" must not synthesize English Audio.
        if Type(stream) = "roAssociativeArray"
            for each field in ["name","title","description","quality"]
                if patterns.englishAudio.IsMatch(CinemaOptionalText(stream[field])) then return 1
            end for
            if Type(stream.behaviorHints) = "roAssociativeArray"
                if patterns.englishAudio.IsMatch(CinemaOptionalText(stream.behaviorHints.filename)) then return 1
            end if
        end if
        if patterns.multilingual.IsMatch(text) then return 0
        return -1
    end if
    if patterns.english.IsMatch(text) then return 1
    if patterns.multilingual.IsMatch(text) then return 0
    return 0
end function

' Torrentio emits HTTPS status clips and download-to-debrid placeholders as
' streams. Neither is a ready movie, even when its name includes 2160p.
' Match the inspected protocol shapes, not arbitrary movie words such as Error.
function CinemaSourceBlockReason(stream as dynamic, patterns = invalid as dynamic) as string
    if Type(stream) <> "roAssociativeArray" then return ""
    if patterns = invalid then patterns = CinemaSourcePatterns()
    name = LCase(CinemaOptionalText(stream.name))
    hints = stream.behaviorHints
    if Type(hints) = "roAssociativeArray"
        if hints.downloadOnly = true then return "download-only"
    end if
    ' Recognize delivery annotations, not movie words or ordinary filenames.
    ' notWebReady is deliberately unrelated: native MKV sources use it too.
    text = CinemaStreamText(stream)
    if patterns.downloadOnly.IsMatch(text) then return "download-only"
    if patterns.downloadName.IsMatch(name) then return "download-only"
    ' The provider's 10Gbps delivery variant is excluded even when its
    ' download-only warning is omitted. Do not scan arbitrary URL/filename text.
    if patterns.tenGbpsName.IsMatch(name) then return "download-only"
    for each field in ["title", "description"]
        for each line in CinemaOptionalText(stream[field]).Split(Chr(10))
            if patterns.downloadName.IsMatch(line.Trim()) then return "download-only"
        end for
    end for
    if CinemaEnglishHint(stream, patterns) < 0 then return "non-english"
    if patterns.download.IsMatch(name) then return "uncached"
    if name.InStr("torrentio") >= 0 and patterns.providerError.IsMatch(name) then return "provider-status"
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
    counts = { uncached: 0, status: 0, downloadOnly: 0, nonEnglish: 0 }
    if Type(streams) <> "roArray" then return counts
    patterns = CinemaSourcePatterns()
    for each stream in streams
        reason = CinemaSourceBlockReason(stream, patterns)
        if reason = "uncached" then counts.uncached = counts.uncached + 1
        if reason = "provider-status" then counts.status = counts.status + 1
        if reason = "download-only" then counts.downloadOnly = counts.downloadOnly + 1
        if reason = "non-english" then counts.nonEnglish = counts.nonEnglish + 1
    end for
    return counts
end function

function CinemaQualityLabel(stream as dynamic) as string
    height = CinemaResolutionHint(stream)
    if height = 2160 then return "2160p / 4K source label"
    if height > 0 then return height.ToStr() + "p source label"
    return "Resolution not supplied"
end function

function CinemaResolutionPatterns() as object
    resolutions = []
    for each height in [2160,1440,1080,720,576,480,360,240,144]
        resolutions.Push({height:height,pattern:CreateObject("roRegex", "(^|[^a-z0-9])" + height.ToStr() + "p?([^a-z0-9]|$)", "i")})
    end for
    return {resolutions:resolutions,fourK:CreateObject("roRegex", "(^|[^a-z0-9])(4k|uhd)([^a-z0-9]|$)", "i")}
end function

function CinemaSourcePatterns() as object
    quality = CinemaResolutionPatterns()
    languages = "(hindi|tamil|telugu|spanish|french|german|italian|portuguese|russian|japanese|korean|chinese|arabic)"
    return {
        resolutions: quality.resolutions
        whitespace: CreateObject("roRegex", "\s", "")
        fourK: quality.fourK
        english: CreateObject("roRegex", "(^|[^a-z])(english|eng)([^a-z]|$)", "i")
        englishAudio: CreateObject("roRegex", "(^|[^a-z])(english|eng)[ ._-]*(audio|alternate|track|aac|ac[ ._-]?3|e[ ._-]?ac[ ._-]?3|ddp|dd|mp3|pcm)([^a-z]|$)|(^|[^a-z])(audio|language)[ ]*:[ ]*(english|eng)([^a-z]|$)|\[(english|eng)\]", "i")
        multilingual: CreateObject("roRegex", "(^|[^a-z])(dual[ ._-]*audio|multi[ ._-]*(audio|language|lingual))([^a-z]|$)", "i")
        foreignOnly: CreateObject("roRegex", "\[(" + languages + "([ ]+audio)?[ -]+only|only[ -]+" + languages + ")\]|(^|[^a-z])audio[ ]*:[ ]*" + languages + "[ ]+only([^a-z]|$)", "i")
        foreignName: CreateObject("roRegex", "^(" + languages + "([ ]+audio)?[ -]+only|only[ -]+" + languages + ")$", "i")
        downloadOnly: CreateObject("roRegex", "\[(10[ ]*gbps([ ]+download[ -]+only)?|download[ -]+only)\]", "i")
        downloadName: CreateObject("roRegex", "^(10[ ]*gbps[ ]+)?download[ -]+only$", "i")
        tenGbpsName: CreateObject("roRegex", "(^|[^a-z0-9])10[ ]*gbps([^a-z0-9]|$)", "i")
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
    score = CinemaQualityRank(CinemaResolutionHint(stream, patterns))
    if CinemaEnglishHint(stream, patterns) > 0 then score = score + 400
    hevc = patterns.hevc
    if hevc.IsMatch(text) then score = score + 20
    ddplus = patterns.ddplus
    if audioMode = "projector"
        if patterns.aac.IsMatch(text)
            score = score + 100
            ' Prefer stereo within the quality tier. A stereo HD filename must
            ' not silently outrank all UHD sources when the setting says 4K first.
            ' Native file/audio checks still decide compatibility.
            if patterns.stereoAac.IsMatch(text) then score = score + 200
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
            if fourKOnly and include then include = CinemaResolutionHint(stream, patterns) = 2160
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
function CinemaPreferUhdFirst(streams as dynamic) as object
    if Type(streams) <> "roArray" then return []
    ordered = []
    patterns = CinemaSourcePatterns()
    for each stream in streams
        ordered.Push({rank:CinemaQualityRank(CinemaResolutionHint(stream,patterns)),stream:stream})
    end for
    ' A stable sort restores quality tiers after source memory without
    ' discarding its proven-working priority inside each tier.
    ordered.SortBy("rank", "r")
    result = []
    for each entry in ordered
        result.Push(entry.stream)
    end for
    return result
end function

function CinemaQualityRank(height as integer) as integer
    ' The user's preferred fallbacks are UHD then Full HD. Other known
    ' qualities follow; no audio/name hint may cross a resolution tier.
    heights = [2160,1080,1440,720,576,480,360,240,144]
    for index = 0 to heights.Count() - 1
        if height = heights[index] then return (heights.Count() - index) * 1000
    end for
    return 0
end function

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
    patterns = CinemaSourcePatterns()
    for each stream in streams
        if CinemaResolutionHint(stream,patterns) = 2160 then result.Push(stream)
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

' Retain only fields the native HTTPS player uses. Labels may be shortened;
' delivery URLs/headers are rejected when oversized, never silently truncated.
function CinemaBudgetStreams(raw as dynamic, countLimit = invalid as dynamic, byteLimit = invalid as dynamic) as object
    if countLimit = invalid then countLimit = 256
    if byteLimit = invalid then byteLimit = 262144
    if countLimit < 1 or countLimit > 256 then countLimit = 256
    if byteLimit < 1 or byteLimit > 262144 then byteLimit = 262144
    result = []
    if Type(raw) <> "roArray" then return result
    used = 0
    for each item in raw
        if Type(item) <> "roAssociativeArray" then continue for
        stream = {}
        unsafe = false
        for each field in ["url","infoHash","sourceMemoryProvider","streamFormat"]
            value = item[field]
            if GetInterface(value,"ifString") <> invalid
                if Len(value) > 8192 then unsafe = true else stream[field] = value
            end if
        end for
        if unsafe then continue for
        for each field in ["name","title","description","quality"]
            if GetInterface(item[field],"ifString") <> invalid then stream[field] = Left(item[field],512)
        end for
        if Type(item.fileIdx) = "Integer" or Type(item.fileIdx) = "roInt" then stream.fileIdx = item.fileIdx
        hints = item.behaviorHints
        if Type(hints) = "roAssociativeArray"
            safeHints = {}
            if hints.downloadOnly = true then safeHints.downloadOnly = true
            if GetInterface(hints.filename,"ifString") <> invalid and Len(hints.filename) <= 512 then safeHints.filename = hints.filename
            if Type(hints.videoSize) = "Integer" or Type(hints.videoSize) = "Double" or Type(hints.videoSize) = "Float" or Type(hints.videoSize) = "roInt" or Type(hints.videoSize) = "roDouble" or Type(hints.videoSize) = "roFloat" then safeHints.videoSize = hints.videoSize
            if Type(hints.proxyHeaders) = "roAssociativeArray"
                proxy = {}
                headerBytes = 0
                for each direction in ["request","response"]
                    values = hints.proxyHeaders[direction]
                    if Type(values) <> "roAssociativeArray" then continue for
                    if values.Count() > 16 then unsafe = true:exit for
                    clean = {}
                    for each key in values
                        value = values[key]
                        if GetInterface(value,"ifString") = invalid or Len(key) > 128 or Len(value) > 2048 then unsafe = true:exit for
                        headerBytes = headerBytes + Len(key) + Len(value)
                        if headerBytes > 4096 then unsafe = true:exit for
                        clean[key] = value
                    end for
                    proxy[direction] = clean
                end for
                safeHints.proxyHeaders = proxy
            end if
            stream.behaviorHints = safeHints
        end if
        if unsafe then continue for
        bytes = CreateObject("roByteArray")
        bytes.FromAsciiString(FormatJson(stream))
        if used + bytes.Count() > byteLimit then continue for
        result.Push(stream)
        used = used + bytes.Count()
        if result.Count() >= countLimit then exit for
    end for
    return result
end function

function CinemaProviderCountBudget(providerCount as integer) as integer
    if providerCount < 1 then providerCount = 1
    limit = Int(1024 / providerCount)
    if limit > 256 then limit = 256
    return limit
end function

function CinemaProviderByteBudget(providerCount as integer) as integer
    if providerCount < 1 then providerCount = 1
    limit = Int(1048576 / providerCount)
    if limit > 262144 then limit = 262144
    return limit
end function
