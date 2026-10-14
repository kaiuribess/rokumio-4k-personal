' Local test controls for this development app only. No provider keys or URLs
' are returned, and diagnostic playback never writes watch history.
function RunPlaybackDiagnostic(kind as string, movieId = "" as string) as boolean
    if kind <> "stereo-control" and kind <> "4k-control" and kind <> "4k-hls-control" and kind <> "movie" and kind <> "stop" then return false
    if kind = "movie"
        pattern = CreateObject("roRegex", "^tt[0-9]{5,12}$", "")
        if not pattern.IsMatch(movieId) then return false
    end if
    state = m.playerScreen.callFunc("PlaybackStatus")
    if state.active = true and state.diagnostic <> true then return false
    m.stack.PopTo("homeScreen")
    if kind = "stereo-control" or kind = "4k-control" or kind = "4k-hls-control"
        controlUrl = "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"
        if kind = "4k-control" then controlUrl = "https://test.playready.microsoft.com/media/profficialsite/tearsofsteel_4k_60s_24fps.12000kbps.3840x2160.h265-8b.2ch.128kbps.aac.mp4"
        if kind = "4k-hls-control" then controlUrl = m.setupAddress + "/4k-control.m3u8"
        m.stack.Push("playerScreen", {
            stream:{url:controlUrl,name:"Public stereo audio control"}
            candidates:[]
            serverAddress:""
            audioMode:"projector"
            diagnostic:true
            diagnosticControl:true
            name:"Stereo audio diagnostic"
            metaType:"movie"
            metaId:"diagnostic"
            videoId:"diagnostic"
            position:0
        })
        return true
    end if
    if kind = "movie"
        pattern = CreateObject("roRegex", "^tt[0-9]{5,12}$", "")
        if not pattern.IsMatch(movieId) then return false
        m.stack.Push("streamsScreen", {metaType:"movie",metaId:movieId,videoId:movieId,name:"Playback test",autoPlay:true,diagnostic:true})
        return true
    end if
    if kind = "stop"
        return true
    end if
    return false
end function

function ReadPlaybackDiagnostic() as object
    device = CreateObject("roDeviceInfo")
    info = {version:"0.5.17",playback:m.playerScreen.callFunc("PlaybackStatus")}
    try
        info.audioOutput = device.GetAudioOutputChannel()
        info.aac = device.CanDecodeAudio({codec:"aac"})
        info.aacMkv = device.CanDecodeAudio({codec:"aac",container:"mkv"})
        info.ac3 = device.CanDecodeAudio({codec:"ac3",channels:6,passthru:1})
    catch e
        info.capabilitiesUnavailable = true
    end try
    return info
end function
