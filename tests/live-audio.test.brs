Harness_Suite("Live audio is playable without inventing English; movies remain strict")
RecoverySetup()
m.playParams.livePlayback = true:m.playParams.allowUnknownLiveAudio = true:m.playParams.metaType = "tv"
StartPlayback("https://example.test/live?temporary=fixture","hls")
Harness_Ok(m.video.content.live,"live native chrome enabled")
Harness_Equal(m.video.content.playStart,-12,"live start near edge never uses movie resume")
Harness_Equal(m.video.content.audioWhitelist,invalid,"live unknown mode does not hide untagged audio")
m.video.state="playing":m.video.audioFormat="aac":m.video.currentAudioTrack="a1"
m.video.availableAudioTracks=[{Track:"a1",Language:"und",Name:"Main"}]
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute,"unknown language may make provisional sound only in explicit live mode")
Harness_Ok(not m.sourceAccepted,"unknown-language native facts still require rendered proof")
Harness_Ok(not CurrentEnglishAudioFacts().verified,"unknown language is never certified English")
RecoveryAccept()
Harness_Ok(m.sourceAccepted,"advancing audio/video can accept the live stream")
Harness_Ok(not CurrentEnglishAudioCheck().verified,"accepted live audio is still not English-verified")
Harness_Equal(CurrentEnglishAudioCheck().reason,"live-language-unverified","honest language reason survives acceptance")
m.video.state="buffering":m.video.availableAudioTracks=[]
onEnglishAudioFactsChanged()
Harness_Ok(not CurrentEnglishAudioCheck().verified,"buffering continuity cannot relabel unknown audio English")
m.video.state="playing":m.video.availableAudioTracks=[{Track:"a1",Language:"spa",Name:"Main"}]
onEnglishAudioFactsChanged()
Harness_Ok(m.video.mute,"an explicit foreign track is not unknown")
m.video.availableAudioTracks=[{Track:"a1",Language:"eng",Name:"Main"}]
onEnglishAudioFactsChanged()
Harness_Ok(CurrentEnglishAudioFacts().verified,"real English tags can establish language later")
Harness_Ok(not m.video.mute,"English returns without replacing the event")
m.stores.library.calls=[]:m.stores.watch.calls=[]
SavePosition():PublishWatchState()
Harness_Equal(m.stores.library.calls.Count(),0,"live event writes no local movie resume")
Harness_Equal(m.stores.watch.calls.Count(),0,"live event writes no account watch state")
PrepareSourceMemoryAttempt({url:"https://example.test/live.m3u8"})
Harness_Equal(m.sourceAttemptKey,"","ephemeral live links are not persisted as working movie files")

for each scenario in ["movie","strict-live","foreign","receiver","commentary","missing-selected"]
    RecoverySetup()
    m.playParams.livePlayback = scenario <> "movie"
    m.playParams.allowUnknownLiveAudio = scenario <> "strict-live"
    m.video.availableAudioTracks=[{Track:"english",Language:"und",Name:"Main"}]
    if scenario="foreign" then m.video.availableAudioTracks[0].Language="fra"
    if scenario="commentary" then m.video.availableAudioTracks[0].commentary=true
    if scenario="missing-selected" then m.video.currentAudioTrack="different"
    if scenario="receiver" then m.video.audioFormat="truehd"
    onEnglishAudioFactsChanged()
    Harness_Ok(m.video.mute,"live exception cannot bypass " + scenario)
    Harness_Ok(not m.sourceAccepted,"no false acceptance for " + scenario)
end for

RecoverySetup()
m.playParams.livePlayback=true:m.playParams.allowUnknownLiveAudio=true
m.video.availableAudioTracks=[]:m.video.currentAudioTrack=""
onEnglishAudioFactsChanged()
Harness_Ok(not m.video.mute,"missing native track list can defer language while decoder is known")
Harness_Ok(not m.sourceAccepted,"missing tracks alone are no proof of audio progression")
m.video.audioFormat="none"
onEnglishAudioFactsChanged()
Harness_Ok(m.video.mute,"missing decoder never counts as live audio")
