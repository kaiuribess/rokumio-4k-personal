function AudioSetup_Guide(mode as string) as string
    nl = Chr(10)
    if mode = "surround"
        return "SOUNDBAR / RECEIVER" + nl + nl + "1. Roku into the soundbar's HDMI IN." + nl + "2. HDMI OUT / eARC to the projector or TV." + nl + "3. Select HDMI on the soundbar." + nl + "4. Set Roku digital audio to Auto; keep volume modes Off." + nl + nl + "English Dolby Digital / DD+ sources are preferred. Stereo sources remain stereo. Use the soundbar remote for volume during setup."
    end if
    return "TV / PROJECTOR SPEAKERS" + nl + nl + "Roku stays connected to the display. Use Roku digital audio Stereo." + nl + nl + "English AAC stereo, MP3 or usable PCM sources are preferred." + nl + nl + "For a soundbar with HDMI input, connect Roku to its HDMI IN, then choose HDMI surround here."
end function

function AudioSetup_CodecStatus(facts as dynamic, codec as string) as string
    if Type(facts) <> "roAssociativeArray" or Type(facts.codecs) <> "roAssociativeArray" then return "Not reported"
    value = facts.codecs[codec]
    if Type(value) <> "Boolean" and Type(value) <> "roBoolean" then return "Not reported"
    if value then return "Supported on this connection"
    return "Not supported on this connection"
end function

function AudioSetup_Report(facts as dynamic, mode as string) as object
    nl = Chr(10)
    output = "Not reported"
    if Type(facts) = "roAssociativeArray"
        if Type(facts.output) = "String" or Type(facts.output) = "roString"
            if facts.output <> "" then output = facts.output
        end if
    end if
    report = "Roku output: " + output + nl + nl + "Dolby Digital: " + AudioSetup_CodecStatus(facts,"ac3") + nl + "Dolby Digital Plus: " + AudioSetup_CodecStatus(facts,"eac3") + nl + "AAC: " + AudioSetup_CodecStatus(facts,"aac")
    advice = "These are current device capability reports; they do not prove audible sound or discrete surround."
    if mode = "surround" and LCase(output) = "stereo" then advice = "Roku currently reports Stereo. Connect the soundbar HDMI IN, select that input, and change Roku digital audio to Auto. Then check again."
    if mode = "surround" and LCase(output) <> "stereo" and AudioSetup_CodecStatus(facts,"eac3") = "Supported on this connection" then advice = "DD+ is reported supported. Select an English DD+ / 5.1 source and check the soundbar's input display during playback. A stereo source cannot prove 5.1 or Atmos."
    return {summary:report,advice:advice}
end function
