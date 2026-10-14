' Track language comes from Roku media metadata, never a movie filename.
function EnglishAudio_IsEnglish(value as dynamic) as boolean
    if Type(value) <> "String" and Type(value) <> "roString" then return false
    language = LCase(value.Trim()).Replace("_", "-")
    return CreateObject("roRegex", "^(eng|en|en-[a-z0-9]{1,8}(-[a-z0-9]{1,8})*)$", "").IsMatch(language)
end function

function EnglishAudio_ProjectorCodec(value as dynamic) as boolean
    if Type(value) <> "String" and Type(value) <> "roString" then return false
    codec = LCase(value.Trim())
    ' Only the documented native AAC aliases qualify. An arbitrary aac_
    ' prefix is not evidence that Roku has a compatible audio decoder.
    return codec = "aac" or codec = "aac_adif" or codec = "aac_adts" or codec = "aac_latm" or codec = "pcm" or codec = "mp3"
end function

function EnglishAudio_Check(tracks as dynamic, selected as dynamic, codec as dynamic, audioMode as string) as object
    result = { verified: false, reason: "unknown-language", englishTracks: [] }
    if Type(tracks) <> "roArray" then return result
    current = invalid
    for each track in tracks
        if Type(track) = "roAssociativeArray" and EnglishAudio_IsEnglish(track.Language) and EnglishAudio_IsDialogue(track)
            if Type(track.Track) = "String" or Type(track.Track) = "roString"
                if track.Track <> "" then result.englishTracks.Push(track)
            end if
        end if
        if Type(track) = "roAssociativeArray" and (Type(selected) = "String" or Type(selected) = "roString") and selected <> ""
            if track.Track = selected then current = track
        end if
    end for
    if current = invalid then return result
    if not EnglishAudio_IsDialogue(current)
        result.reason = "non-dialogue-audio"
        return result
    end if
    if not EnglishAudio_IsEnglish(current.Language)
        result.reason = "non-english"
        return result
    end if
    if Type(codec) <> "String" and Type(codec) <> "roString" then return result
    codec = LCase(codec.Trim())
    if codec = "" or codec = "unknown" then return result
    if codec = "none"
        result.reason = "no-playable-audio"
        return result
    end if
    if audioMode = "projector" and not EnglishAudio_ProjectorCodec(codec)
        result.reason = "projector-codec"
        return result
    end if
    if audioMode = "surround" and not EnglishAudio_ProjectorCodec(codec) and codec <> "ac3" and codec <> "eac3"
        result.reason = "unsupported-audio"
        return result
    end if
    result.verified = true
    result.reason = "english"
    return result
end function

function EnglishAudio_IsDialogue(track as dynamic) as boolean
    if Type(track) <> "roAssociativeArray" then return false
    ' Header tracks mark an unreadable present Name explicitly. Native Roku
    ' track objects do not have this marker and retain their normal semantics.
    if track.NameKnown = false then return false
    if track.HasAccessibilityDescription = true or track.commentary = true then return false
    name = ""
    if Type(track.Name) = "String" or Type(track.Name) = "roString" then name = LCase(track.Name)
    if name.InStr("commentary") >= 0 then return false
    ' Track labels can reject an explicit accessibility rendition, but never
    ' establish English. Bound abbreviations so ordinary words such as
    ' "Badlands" or "radio" do not become false AD matches.
    descriptive = CreateObject("roRegex", "(^|[^a-z0-9])(audio[ ._-]*descriptions?|descriptive[ ._-]+audio|ad|dvs)([^a-z0-9]|$)", "i")
    return not descriptive.IsMatch(name)
end function
