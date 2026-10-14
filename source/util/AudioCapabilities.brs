' Fresh audio output facts. A preset never supplies a decoder or receiver.
' Queries run inside the app after installation, never against a remote device.
function AudioCapabilities_ReadDevice() as object
    facts = {codecs:{},channels:{},output:""}
    device = invalid
    try
        device = CreateObject("roDeviceInfo")
    catch e
        return facts
    end try
    if device = invalid then return facts
    try
        output = device.GetAudioOutputChannel()
        if Type(output) = "String" or Type(output) = "roString" then facts.output = output
    catch e
    end try
    for each codec in ["aac", "mp3", "pcm", "ac3", "eac3", "dts"]
        query = {codec:codec}
        if codec = "ac3" or codec = "eac3" or codec = "dts" then query.passthru = 1
        try
            answer = device.CanDecodeAudio(query)
            if Type(answer) = "roAssociativeArray"
                kind = Type(answer.result)
                if kind = "Boolean" or kind = "roBoolean" then facts.codecs[codec] = answer.result
            end if
        catch e
            ' Unknown or unsupported APIs remain unknown, not a false verdict.
        end try
    end for
    try
        decoders = device.GetAudioDecodeInfo()
        facts.channels = AudioCapabilities_ChannelLimits(decoders)
    catch e
    end try
    return facts
end function

function AudioCapabilities_ChannelLimits(decoders as dynamic) as object
    limits = {}
    if Type(decoders) <> "roAssociativeArray" then return limits
    number = CreateObject("roRegex", "^[1-8]:[0-9]+:[0-9]+:[01]:?$", "")
    for each name in decoders
        value = decoders[name]
        if Type(value) = "String" or Type(value) = "roString"
            if number.IsMatch(value)
                codec = AudioCapabilities_CodecKey(name)
                if codec = "dd+" then codec = "eac3"
                if codec = "dd" then codec = "ac3"
                if codec = "aac" or codec = "mp3" or codec = "pcm" or codec = "ac3" or codec = "eac3" or codec = "dts" then limits[codec] = Val(value.Split(":")[0])
            end if
        end if
    end for
    return limits
end function

function AudioCapabilities_ExplicitlyUnsupported(facts as dynamic, codec as dynamic) as boolean
    if Type(facts) <> "roAssociativeArray" or Type(facts.codecs) <> "roAssociativeArray" then return false
    if Type(codec) <> "String" and Type(codec) <> "roString" then return false
    key = AudioCapabilities_CodecKey(codec)
    if not facts.codecs.DoesExist(key) then return false
    value = facts.codecs[key]
    kind = Type(value)
    return (kind = "Boolean" or kind = "roBoolean") and value = false
end function

function AudioCapabilities_CodecKey(codec as string) as string
    key = LCase(codec.Trim())
    if key = "aac_adif" or key = "aac_adts" or key = "aac_latm" then return "aac"
    return key
end function

function AudioCapabilities_Text(facts as dynamic) as string
    if Type(facts) <> "roAssociativeArray" then return "Audio output capabilities not reported"
    output = "Not reported"
    if Type(facts.output) = "String" or Type(facts.output) = "roString"
        if facts.output <> "" then output = facts.output
    end if
    return "Audio output: " + output + " (device report; does not prove speaker sound)"
end function
