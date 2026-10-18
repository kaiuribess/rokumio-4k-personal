Harness_Suite("Native voice playback policy")
playing = { state: "playing", position: 120.5, duration: 600.0 }
paused = { state: "paused", position: 120.5, duration: 600.0 }
decision = VoicePlaybackDecision({ type: "transport", command: "pause" }, playing)
Harness_Equal(decision.control, "pause", "pause reaches native player")
Harness_Equal(decision.status, "success", "pause acknowledged")
decision = VoicePlaybackDecision({ type: "transport", command: "play" }, paused)
Harness_Equal(decision.control, "resume", "play resumes paused media")
Harness_Equal(decision.autoplayAfterSeek, true, "resume restores seek autoplay")
decision = VoicePlaybackDecision({ type: "transport", command: "resume" }, playing)
Harness_Equal(decision.status, "success", "already-playing resume acknowledged")
Harness_Equal(decision.control, invalid, "already-playing resume does not restart media")
decision = VoicePlaybackDecision({ type: "transport", command: "pause" }, paused)
Harness_Equal(decision.status, "error.redundant", "already-paused request acknowledged")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "forward", duration: "30" }, playing)
Harness_Equal(decision.seek, 150.5, "seek forwards relative to current position")
Harness_Equal(decision.control, invalid, "seek preserves playback state")
Harness_Equal(decision.autoplayAfterSeek, true, "playing seek keeps autoplay")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "backward", duration: "30" }, paused)
Harness_Equal(decision.seek, 90.5, "seek backwards relative to current position")
Harness_Equal(decision.control, invalid, "seek does not unpause paused media")
Harness_Equal(decision.autoplayAfterSeek, false, "paused seek disables implicit native autoplay")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "backward", duration: "300" }, playing)
Harness_Equal(decision.seek, 0, "seek clamps before start")
Harness_Equal(decision.status, "success.seek-start", "start clamp reported")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "forward", duration: "900" }, playing)
Harness_Equal(decision.seek, 599, "seek clamps before EOF")
Harness_Equal(decision.status, "success.seek-end", "end clamp reported")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "forward", duration: "900" }, { state: "playing", position: 10.0, duration: 0 })
Harness_Equal(decision.seek, 910, "unknown duration does not impose a false end")
decision = VoicePlaybackDecision({ type: "transport", command: "startover" }, paused)
Harness_Equal(decision.seek, 0, "start over seeks to zero")
Harness_Equal(decision.control, "resume", "start over resumes paused video")
Harness_Equal(decision.autoplayAfterSeek, true, "start over enables native autoplay")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "sideways", duration: "30" }, playing)
Harness_Equal(decision.status, "error.generic", "invalid direction rejected")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "forward", duration: "abc" }, playing)
Harness_Equal(decision.status, "error.generic", "invalid duration rejected")
Harness_Equal(decision.seek, invalid, "invalid duration cannot accidentally seek")
decision = VoicePlaybackDecision({ type: "transport", command: "seek", direction: "forward" }, playing)
Harness_Equal(decision.status, "error.generic", "missing duration rejected")
decision = VoicePlaybackDecision({ type: "transport", command: "pause" }, { state: "stopped" })
Harness_Equal(decision.status, "error.no-media", "stopped player is not active media")
decision = VoicePlaybackDecision({ type: "transport", command: "next" }, playing)
Harness_Equal(decision.status, "unhandled", "next episode is not falsely advertised")
decision = VoicePlaybackDecision({ type: "transport", command: "forward" }, playing)
Harness_Equal(decision.status, "unhandled", "basic forward falls through to Roku")
decision = VoicePlaybackDecision({ contentId: "rokumio-import" }, playing)
Harness_Equal(decision.status, "unhandled", "deep links are not treated as voice playback")
decision = VoicePlaybackDecision(invalid, playing)
Harness_Equal(decision.status, "unhandled", "invalid event safe")

Harness_Suite("MainScene applies native seek state")
video = { state: "paused", position: 120.5, duration: 600.0, autoplayAfterSeek: true }
m.playerScreen = {
    video: video
    FindNode: function(id as string) as object
        return m.video
    end function
}
m.stack = {
    top: function() as object
        return { id: "playerScreen" }
    end function
}
response = HandleVoiceTransport({ type: "transport", command: "seek", direction: "forward", duration: "30" })
Harness_Equal(video.seek, 150.5, "native seek receives target")
Harness_Equal(video.autoplayAfterSeek, false, "native paused seek disables automatic resume")
Harness_Equal(video.control, invalid, "native paused seek sends no resume control")
response = HandleVoiceTransport({ type: "transport", command: "play" })
Harness_Equal(video.control, "resume", "native play resumes")
Harness_Equal(video.autoplayAfterSeek, true, "native play restores autoplay for remote seeking")
video.control = invalid
response = HandleVoiceTransport({ type: "transport", command: "startover" })
Harness_Equal(video.seek, 0, "native start over seeks to beginning")
Harness_Equal(video.autoplayAfterSeek, true, "native start over enables autoplay")
Harness_Suite("MainScene accepts native numeric position wrappers for relative seeks")
boxedFloat = CreateObject("roFloat"):boxedFloat.SetFloat(120.5)
boxedDouble = CreateObject("roDouble"):boxedDouble.SetDouble(120.5#)
boxedLong = CreateObject("roLongInteger"):boxedLong.SetLongInt(120&)
boxedInt = CreateObject("roInt"):boxedInt.SetInt(120)
Harness_Equal(Type(boxedFloat),"roFloat","fixture uses a native boxed float")
Harness_Equal(Type(boxedDouble),"roDouble","fixture uses a native boxed double")
Harness_Equal(Type(boxedLong),"roLongInteger","fixture uses a native boxed64-bit integer")
for each position in [120,120.5,120.5#,120&,boxedFloat,boxedDouble,boxedLong,boxedInt]
    video.state = "playing":video.position = position:video.duration = 600:video.seek = invalid:video.control = invalid
    response = HandleVoiceTransport({type:"transport",command:"seek",direction:"forward",duration:"10"})
    Harness_Equal(response.status,"success","forward10 accepts " + Type(position))
    Harness_Equal(video.seek,position + 10#,"native forward target preserves numeric position")
    Harness_Ok(video.autoplayAfterSeek,"playing native seek keeps autoplay")
    video.state = "paused":video.seek = invalid
    response = HandleVoiceTransport({type:"transport",command:"seek",direction:"backward",duration:"5"})
    Harness_Equal(response.status,"success","backward5 accepts " + Type(position))
    Harness_Equal(video.seek,position - 5#,"native backward target preserves numeric position")
    Harness_Ok(not video.autoplayAfterSeek and video.control = invalid,"boxed position seek never unpauses paused media")
end for
Harness_Suite("Native seek numeric validation cannot crash or mutate playback")
for each bad in [invalid,"120",true,-1,{},[],2147483648#]
    video.state = "playing":video.position = bad:video.duration = 600:video.seek = invalid:video.control = invalid:video.autoplayAfterSeek = false
    response = HandleVoiceTransport({type:"transport",command:"seek",direction:"forward",duration:"10"})
    Harness_Equal(response.status,"error.generic","malformed or out-of-range native position is rejected")
    Harness_Ok(video.seek = invalid and video.control = invalid and not video.autoplayAfterSeek,"rejected position leaves native playback fields untouched")
end for
for each unknown in [invalid,"600",true,-1,{},[],2147483648#]
    video.state = "playing":video.position = 120.5:video.duration = unknown:video.seek = invalid
    response = HandleVoiceTransport({type:"transport",command:"seek",direction:"forward",duration:"10"})
    Harness_Equal(response.status,"success","unknown native duration cannot crash a valid relative seek")
    Harness_Equal(video.seek,130.5,"unknown duration cannot impose a fabricated end boundary")
end for
for each ending in [boxedFloat,boxedDouble,boxedLong,boxedInt,120&]
    video.state = "playing":video.position = 110:video.duration = ending:video.seek = invalid
    response = HandleVoiceTransport({type:"transport",command:"seek",direction:"forward",duration:"30"})
    Harness_Equal(response.status,"success.seek-end","boxed native duration still enforces the end boundary")
    Harness_Equal(video.seek,ending - 1#,"native EOF clamp preserves numeric duration")
end for
for each bad in ["", "-5", "1.5", "1e3", " 10", "10 ", String(10000,"9"), "2147483648", 10, true]
    video.state = "playing":video.position = 120:video.duration = 600:video.seek = invalid:video.control = invalid:video.autoplayAfterSeek = false
    response = HandleVoiceTransport({type:"transport",command:"seek",direction:"forward",duration:bad})
    Harness_Equal(response.status,"error.generic","malformed or oversized event offset is rejected")
    Harness_Ok(video.seek = invalid and video.control = invalid and not video.autoplayAfterSeek,"rejected offset never applies native playback mutations")
end for
video.state = "playing":video.position = 120:video.duration = 0:video.seek = invalid
response = HandleVoiceTransport({type:"transport",command:"seek",direction:"forward",duration:"2147483647"})
Harness_Equal(response.status,"error.generic","unknown-duration target overflow is rejected after safe offset parsing")
Harness_Equal(video.seek,invalid,"overflow cannot reach the native seek field")
video.position = 0
response = HandleVoiceTransport({type:"transport",command:"seek",direction:"forward",duration:"2147483647"})
Harness_Equal(video.seek,2147483647#,"bounded decimal parsing preserves the exact integer endpoint")
video.position = 2:video.duration = 600
response = HandleVoiceTransport({type:"transport",command:"seek",direction:"backward",duration:"5"})
Harness_Equal(response.status,"success.seek-start","backward native seek still clamps safely to zero")
Harness_Equal(video.seek,0,"start clamp remains exact")
Harness_Finish()
if m.failed > 0
    bad = invalid
    x = bad.poison
end if
