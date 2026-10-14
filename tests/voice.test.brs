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
Harness_Finish()
if m.failed > 0
    bad = invalid
    x = bad.poison
end if
