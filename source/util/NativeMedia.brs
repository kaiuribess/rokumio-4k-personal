
' Inspect a bounded MKV header on the worker. No filenames or signed URLs logged.
function NativeMedia_Read(resolved as object, workerId as string) as object
    unknown = {complete:false,tracks:[],reason:"not-MKV"}
    if resolved.streamFormat <> "mkv" then return unknown
    unknown.reason = "header-unavailable"
    transfer = CreateObject("roUrlTransfer")
    port = CreateObject("roMessagePort")
    transfer.SetMessagePort(port)
    transfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    transfer.EnablePeerVerification(true)
    transfer.EnableHostVerification(true)
    transfer.SetUrl(resolved.url)
    if Type(resolved.headers) = "roArray"
        for each header in resolved.headers
            colon = header.InStr(":")
            if colon > 0 then transfer.AddHeader(Left(header,colon),Mid(header,colon+2))
        end for
    end if
    transfer.AddHeader("Range","bytes=0-1048575")
    transfer.AddHeader("Accept-Encoding","identity")
    path = "tmp:/mediaHeader-" + workerId + ".bin"
    fs = CreateObject("roFileSystem")
    data = invalid
    try
        unknown.reason = "request-not-started"
        if transfer.AsyncGetToFile(path)
            unknown.reason = "request-timeout"
            for tick = 1 to 100
                event = Wait(100,port)
                stat = fs.Stat(path)
                if not NativeMedia_HasSize(stat) then stat = fs.Stat(path + ".tmp")
                if NativeMedia_HasSize(stat)
                    if stat.size > 2097152 then exit for
                end if
                if Type(event) = "roUrlEvent"
                    unknown.reason = "header-response"
                    print "[inspect] header HTTP "; event.GetResponseCode()
                    if event.GetResponseCode() = 206
                        headers = event.GetResponseHeaders()
                        range = ""
                        for each name in headers
                            if LCase(name) = "content-range" then range = headers[name]
                        end for
                        stat = fs.Stat(path)
                        if Left(LCase(range),8) = "bytes 0-" and NativeMedia_HasSize(stat) and stat.size <= 1048576
                            data = CreateObject("roByteArray")
                            if not data.ReadFile(path) then data = invalid
                        end if
                    end if
                    exit for
                end if
            end for
        end if
    catch e
        unknown.reason = "header-read-error"
        print "[inspect] native read error code "; e.number
        data = invalid
    end try
    transfer.AsyncCancel()
    fs.Delete(path)
    if data = invalid
        print "[inspect] "; unknown.reason
        return unknown
    end if
    print "[inspect] header bytes "; data.Count()
    parsed = NativeMedia_Parse(data)
    print "[inspect] complete "; parsed.complete; " tracks "; parsed.tracks.Count()
    return parsed
end function

function NativeMedia_Vint(data as object, cursor as integer, limit as integer, isId as boolean) as dynamic
    if cursor < 0 or cursor >= limit then return invalid
    first = data[cursor]
    marker = 128
    count = 1
    while marker > 0 and (first and marker) = 0
        marker = Int(marker / 2)
        count = count + 1
    end while
    if marker = 0 or count > 8 or (isId and count > 4) or cursor + count > limit then return invalid
    value = CDbl(first and (marker-1))
    if isId then value = first
    allOnes = (first and (marker-1)) = marker-1
    for i = 1 to count-1
        value = value * 256 + data[cursor+i]
        if data[cursor+i] <> 255 then allOnes = false
    end for
    return {value:value,length:count,unknown:allOnes and not isId}
end function

function NativeMedia_Element(data as object, cursor as integer, limit as integer) as dynamic
    id = NativeMedia_Vint(data,cursor,limit,true)
    if id = invalid then return invalid
    size = NativeMedia_Vint(data,cursor+id.length,limit,false)
    if size = invalid then return invalid
    start = cursor + id.length + size.length
    return {id:id.value,start:start,finish:start+size.value,unknown:size.unknown}
end function

function NativeMedia_UInt(data as object, field as object) as integer
    if field.finish - field.start > 4 then return -1
    value = 0
    for i = field.start to field.finish-1
        value = value * 256 + data[i]
    end for
    return value
end function

function NativeMedia_Text(data as object, field as object) as string
    if field.finish-field.start > 128 then return ""
    text = ""
    for i = field.start to field.finish-1
        if data[i] < 32 or data[i] > 126 then return ""
        text = text + Chr(data[i])
    end for
    return text
end function

' Matroska Name is UTF-8, unlike CodecID/Language. Validate a small printable
' UTF-8 range before ToAsciiString (whose invalid-UTF-8 result is undefined).
' Unreadable present text remains uncertainty, never an empty dialogue claim.
function NativeMedia_Name(data as object, field as object) as object
    result = {known:false,text:""}
    size = field.finish-field.start
    if size < 0 or size > 256 or field.start < 0 or field.finish > data.Count() then return result
    bytes = CreateObject("roByteArray")
    cursor = field.start
    while cursor < field.finish
        first = data[cursor]
        length = 1
        secondMin = 128
        secondMax = 191
        if first >= 32 and first <= 126
            length = 1
        else if first >= 194 and first <= 223
            length = 2
            if first = 194 then secondMin = 160 ' Exclude Unicode control bytes.
        else if first >= 224 and first <= 239
            length = 3
            if first = 224 then secondMin = 160 ' No overlong encoding.
            if first = 237 then secondMax = 159 ' No UTF-16 surrogate values.
        else if first >= 240 and first <= 244
            length = 4
            if first = 240 then secondMin = 144 ' No overlong encoding.
            if first = 244 then secondMax = 143 ' Maximum U+10FFFF.
        else
            return result
        end if
        if cursor + length > field.finish then return result
        if length > 1
            if data[cursor+1] < secondMin or data[cursor+1] > secondMax then return result
            for i = 2 to length-1
                if data[cursor+i] < 128 or data[cursor+i] > 191 then return result
            end for
        end if
        for i = 0 to length-1
            bytes.Push(data[cursor+i])
        end for
        cursor = cursor + length
    end while
    result.known = true
    result.text = bytes.ToAsciiString()
    return result
end function

function NativeMedia_Fields(data as object, start as integer, finish as integer) as dynamic
    fields = {}
    cursor = start
    for count = 1 to 512
        if cursor = finish then return fields
        field = NativeMedia_Element(data,cursor,finish)
        if field = invalid or field.unknown or field.finish > finish or field.finish <= cursor then return invalid
        key = field.id.ToStr()
        if fields.DoesExist(key) then return invalid
        fields[key] = field
        cursor = Int(field.finish)
    end for
    return invalid
end function

function NativeMedia_Parse(data as object) as object
    result = {complete:false,tracks:[]}
    limit = data.Count()
    if limit < 5 or limit > 1048576 then return result
    root = NativeMedia_Element(data,0,limit)
    if root = invalid or root.id <> &h1a45dfa3 or root.finish >= limit then return result
    segment = NativeMedia_Element(data,Int(root.finish),limit)
    if segment = invalid or segment.id <> &h18538067 then return result
    cursor = segment.start
    for count = 1 to 512
        field = NativeMedia_Element(data,cursor,limit)
        if field = invalid or field.unknown or field.finish > limit then return result
        if field.id = &h1f43b675 then return result
        if field.id = &h1654ae6b
            cursor = field.start
            while cursor < field.finish and result.tracks.Count() < 64
                entry = NativeMedia_Element(data,cursor,Int(field.finish))
                if entry = invalid or entry.unknown or entry.finish > field.finish then return result
                if entry.id = &hae
                    fields = NativeMedia_Fields(data,entry.start,Int(entry.finish))
                    if fields = invalid then return result
                    if not fields.DoesExist("131") or not fields.DoesExist("134") then return result
                    track = {kind:0,codec:"",language:"eng",languageDeclared:false,channels:1,channelsDeclared:false,enabled:true,width:0,height:0,commentary:false,HasAccessibilityDescription:false,Name:"",NameKnown:true}
                    if fields.DoesExist("131") then track.kind = NativeMedia_UInt(data,fields["131"])
                    if fields.DoesExist("134") then track.codec = NativeMedia_Text(data,fields["134"])
                    if track.kind <= 0 or track.codec = "" then return result
                    for each flagKey in ["21935","21932","185"]
                        if fields.DoesExist(flagKey)
                            value = NativeMedia_UInt(data,fields[flagKey])
                            if value <> 0 and value <> 1 then return result
                            if flagKey = "21935" then track.commentary = value = 1
                            if flagKey = "21932" then track.HasAccessibilityDescription = value = 1 ' FlagVisualImpaired 0x55AC.
                            if flagKey = "185" then track.enabled = value = 1
                        end if
                    end for
                    if fields.DoesExist("21358")
                        name = NativeMedia_Name(data,fields["21358"])
                        track.Name = name.text
                        track.NameKnown = name.known
                    end if
                    for each languageKey in ["2274716","2274717"]
                        if fields.DoesExist(languageKey)
                            track.language = NativeMedia_Text(data,fields[languageKey])
                            track.languageDeclared = true
                        end if
                    end for
                    if fields.DoesExist("225")
                        audio = NativeMedia_Fields(data,fields["225"].start,Int(fields["225"].finish))
                        if audio = invalid then return result
                        if audio.DoesExist("159")
                            track.channels = NativeMedia_UInt(data,audio["159"])
                            track.channelsDeclared = true
                            if track.channels <= 0 or track.channels > 32 then return result
                        end if
                    else if track.kind = 2
                        return result ' Audio element is mandatory for an audio track.
                    end if
                    if fields.DoesExist("224")
                        video = NativeMedia_Fields(data,fields["224"].start,Int(fields["224"].finish))
                        if video = invalid then return result
                        if video.DoesExist("176") then track.width = NativeMedia_UInt(data,video["176"])
                        if video.DoesExist("186") then track.height = NativeMedia_UInt(data,video["186"])
                    end if
                    result.tracks.Push(track)
                end if
                cursor = Int(entry.finish)
            end while
            result.complete = cursor = field.finish and result.tracks.Count() > 0
            return result
        end if
        cursor = Int(field.finish)
    end for
    return result
end function

function NativeMedia_AudioPolicy(media as dynamic, mode as string) as object
    result = {known:false,compatible:true,reason:"metadata-unavailable",englishOnlyAac:false,englishOnlyMp3:false,hasStereoEnglishAac:false}
    if Type(media) <> "roAssociativeArray" or media.complete <> true then return result
    if Type(media.tracks) <> "roArray" then return result
    result.known = true
    result.compatible = false
    result.reason = "no-compatible-English-audio"
    aacCount = 0
    allAacSafe = true
    mp3Count = 0
    allMp3Safe = true
    uncertain = false
    for each track in media.tracks
        if track.kind = 2 and track.enabled
            codec = LCase(track.codec)
            english = EnglishAudio_IsEnglish(track.language) and EnglishAudio_IsDialogue(track)
            aacFamily = Left(codec,5) = "a_aac"
            aac = NativeMedia_IsSupportedAac(codec)
            stereo = track.channels > 0 and track.channels <= 2
            if aacFamily
                aacCount = aacCount + 1
                if not aac or not english or not stereo or track.languageDeclared <> true then allAacSafe = false
            end if
            if codec = "a_mpeg/l3"
                mp3Count = mp3Count + 1
                if not english or not stereo or track.languageDeclared <> true then allMp3Safe = false
            end if
            if english
                allowed = (aac or codec = "a_mpeg/l3") and stereo
                if mode = "surround" and (codec = "a_ac3" or codec = "a_eac3") then allowed = true
                if aac and allowed and track.languageDeclared = true then result.hasStereoEnglishAac = true
                if allowed then result.compatible = true
            end if
            ' No inspection of PCM sample depth/endianness/private codec data
            ' means no supported-PCM claim and no permanent file rejection.
            ' Unknown AAC profiles/codecs or an unreadable present Name likewise
            ' defer to selected native track, actual decoder and progress checks.
            ' Unknown language tags are case-insensitive and may be padded.
            ' Normalization permits native verification, never English approval.
            language = LCase(track.language.Trim())
            unknownLanguage = language = "" or language = "und" or language = "mul"
            potentialEnglish = EnglishAudio_IsEnglish(track.language) or unknownLanguage
            if potentialEnglish
                knownCodec = aac or codec = "a_mpeg/l3" or codec = "a_ac3" or codec = "a_eac3" or codec = "a_truehd" or Left(codec,5) = "a_dts"
                if not knownCodec or track.NameKnown = false or unknownLanguage then uncertain = true
            end if
        end if
    end for
    result.englishOnlyAac = aacCount > 0 and allAacSafe
    result.englishOnlyMp3 = mp3Count > 0 and allMp3Safe
    if not result.compatible and uncertain
        result.known = false
        result.compatible = true
        result.reason = "audio-metadata-uncertain"
    end if
    for each track in media.tracks
        if track.kind = 1 and track.enabled and track.width > 0 and track.height > 0
            if track.width < 1920 and track.height < 1080
                result.compatible = false
                result.known = true
                result.reason = "below-HD"
            end if
        end if
    end for
    if result.compatible and result.known then result.reason = "compatible-English-audio"
    if not result.compatible
        result.englishOnlyAac = false
        result.englishOnlyMp3 = false
    end if
    return result
end function

function NativeMedia_IsSupportedAac(codec as string) as boolean
    ' Generic AAC still needs the native decoder. Legacy LC/SBR mappings are
    ' accepted; unsupported Main/SSR/LTP profiles never authorize empty tracks.
    return codec = "a_aac" or codec = "a_aac/mpeg2/lc" or codec = "a_aac/mpeg2/lc/sbr" or codec = "a_aac/mpeg4/lc" or codec = "a_aac/mpeg4/lc/sbr"
end function

function NativeMedia_Resolution(media as dynamic) as string
    if Type(media) <> "roAssociativeArray" or media.complete <> true then return "Encoded resolution not inspected"
    for each track in media.tracks
        if track.kind = 1 and track.enabled and track.width > 0 and track.height > 0
            return "Encoded file: " + track.width.ToStr() + " × " + track.height.ToStr() + " (header metadata)"
        end if
    end for
    return "Encoded resolution not inspected"
end function

' Only negative evidence: every enabled video track has inspected dimensions
' below both UHD axes. Cropped 3840-wide movies are not rejected. An absent,
' incomplete, malformed or mixed-resolution inspection cannot establish that
' the chosen video is below UHD and is left to native playback facts.
function NativeMedia_KnownBelowUhd(media as dynamic) as boolean
    if Type(media) <> "roAssociativeArray" or media.complete <> true then return false
    if Type(media.tracks) <> "roArray" then return false
    foundVideo = false
    for each track in media.tracks
        if Type(track) <> "roAssociativeArray" then return false
        if track.kind = 1
            if track.enabled = true
                if not NativeMedia_HasSize({size:track.width}) or not NativeMedia_HasSize({size:track.height}) then return false
                if track.width <= 0 or track.height <= 0 then return false
                if track.width >= 3840 or track.height >= 2160 then return false
                foundVideo = true
            else if track.enabled <> false
                return false
            end if
        end if
    end for
    return foundVideo
end function

function NativeMedia_Reason(media as dynamic) as string
    if Type(media) <> "roAssociativeArray" then return "not-requested"
    if media.complete = true then return "complete"
    if media.reason <> invalid then return media.reason
    return "metadata-incomplete"
end function

function NativeMedia_HasSize(info as dynamic) as boolean
    if Type(info) <> "roAssociativeArray" then return false
    kind = Type(info.size)
    return kind = "Integer" or kind = "LongInteger" or kind = "roInt" or kind = "roInteger" or kind = "roLongInteger" or kind = "Float" or kind = "Double" or kind = "roFloat" or kind = "roDouble"
end function
