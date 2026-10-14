# Playback compatibility, evidence and limitations

## Direct playback pipeline

The metadata/catalog add-on supplies title and episode information. A stream add-on supplies candidate URLs. Source selection ranks candidates using explicit quality/audio hints, device checks and prior working file identities. A background task resolves/preflights a candidate; Roku's native Video node fetches and decodes the media. The English audio guard and rendered-progress checks determine whether that candidate is accepted. A bounded recovery queue tries alternatives when startup fails.

Direct HTTPS sources do not require a PC during viewing. This code also retains upstream streaming-server support for torrent/hash-only sources; that separate mode requires an external server. The project does not implement a local torrent engine or a general native audio/video transcoder.

## What is established

| Capability | Evidence / boundary |
| --- | --- |
| Add-on catalog/meta/stream protocol handling | Automated protocol fixtures and mock-server tests; every provider can still have incompatible behavior |
| Remote UI, source sorting and asynchronous loading | Production callbacks exercised with simulated native boundaries; not a complete Roku OS simulator |
| Native UHD decoding on a Streaming Stick+ 3830RW | An earlier 0.5.8 public Apple HLS control produced native 3840×2160 HEVC/AAC-stereo segment and advancing audio/video timestamp observations on an Optoma UHD50X path |
| Arbitrary 4K films and sound | Not established by that control; the original tests were source-specific, and native field progression is not an acoustic listening test |
| Automatic next episode in 0.5.12 | 67 focused software assertions cover ordering, season rollover, stale events, cancellation, completion saving and fixed-depth navigation; physical-device transition not yet tested |
| Add-on checks and audio setup in 0.5.13 | Production-policy/controller tests cover manifest categories, privacy, progressive updates, cancellation, stale deadlines and explicit audio choices; native screens/receiver path not physically tested in this release |
| Home, preferences and playback stability in 0.5.14 | Production tests cover bounded preview work, complete-catalog routing, settings persistence, stale timer ownership, audio-repair delay and native terminal position resets; physical rendering/scheduling untested |
| Early automatic Play and source scheduling in 0.5.15 | Simulated callback tests cover grace/cancellation, provider queue ownership and shared worker budget; no physical latency or frame-rate measurement |
| Surround output, HDR variants and full-length reliability | Not certified for 0.5.15 or every display/receiver/source |

One earlier clear HEVC MP4 control failed despite plausible metadata. Multichannel AAC also failed on the tested Stick/projector path. Those counterexamples are why the project does not claim that labels or header inspection guarantee playback.

## Genuine 4K versus output mode

Use actual encoded/native-decoded dimensions when available. HLS/DASH can expose the dimensions of the currently playing segment, and adaptive playback may choose a lower rendition. Progressive file inspection can reveal encoded dimensions, but successful parsing alone does not prove native decoding. A 3840×1600 cinema crop can be UHD; a 1920-wide source remains HD even if HDMI output is 2160p.

The 4K-only filter starts with provider labels. Complete inspected MKV metadata proving all enabled video is known below UHD is rejected in this mode. Mixed/unknown dimensions remain uncertain. No claim is made that all adaptive segments can be forced to 2160p. [Roku Video fields](https://developer.roku.com/dev/docs/video) and [content metadata](https://developer.roku.com/dev/docs/content-metadata) describe the platform boundary.

## English audio and receiver modes

The app excludes explicit commentary/audio-description tracks and prefers supported English dialogue. Untagged or mislabelled language remains uncertain; a file can incorrectly declare English. Projector mode prioritizes likely stereo-compatible sources and keeps available same-file MP3/PCM alternatives visible. Receiver mode consults native decode/passthrough capabilities and prefers suitable surround hints.

The player clears stale audio-track selectors between files and uses bounded native track recovery. It cannot manufacture a missing English track, transform stereo into discrete 5.1, or transcode a codec the Stick cannot decode. Provider labels can confuse AAC 2.0 and AAC 5.1; inspect actual tracks and receiver input where possible.

Version 0.5.14 improves alternative ordering when multichannel AAC hints previously crowded out likely usable English MP3/PCM. Receiver mode penalizes Dolby alternatives explicitly rejected by current native capability. These remain selection hints; native English/audio/progress checks are still required. No audio is converted locally.

Saved quality, autoplay and source-recovery choices apply to new playback. Disabling automatic recovery does not disable English track checks or allow a failed file to be accepted. Terminal native position/duration resets use the last source-scoped observation for same-title recovery, while intentional active seeks to zero are respected.

Automatic Play now offers Start sooner or Compare providers. Early selection can start from available candidates while other add-ons are queued/pending, so its initial recovery pool can be smaller. Compare providers collects the wider pool before selecting. Queued source-list work pauses during playback and resumes on returning to the picker. Provider results arriving behind Player never replace the accepted source. An available URL/2160p label is still a candidate; native English/audio/decoded-progress checks follow before acceptance.

## Practical failure cases

| Problem | Behavior / next step |
| --- | --- |
| Expired URL, incompatible encoding or startup failure | Automatic bounded alternate-source attempts; refresh links on the source screen |
| No compatible candidates | A clear stopped state/source list; no endless guarantee of finding one |
| Long rebuffer or measured premature end | Recover within the current title/episode; does not count as natural completion |
| Missing episode metadata | No guessed next episode; return to series/episodes to refresh metadata |
| Final episode or next episode has a future release date | Autoplay ends; specials are not appended to regular-season playback |
| Insufficient Wi-Fi/provider throughput | Preloading can reduce lookup work, but cannot remove network buffering |
| Unsupported audio in every candidate | Another compatible original source or a different playback/transcoding system is required |

No provider subscription is included or required by the client itself. Some providers require accounts/payment, and neither manifest import nor static testing guarantees their catalog, cache, 4K availability or reliability. Verify a specific compatible source before treating a service as a guaranteed solution.
