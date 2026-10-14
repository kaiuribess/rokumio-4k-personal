# Playback compatibility, evidence and limitations

## Direct playback pipeline

The metadata/catalog add-on supplies title and episode information. A stream add-on supplies candidate URLs. Source selection ranks candidates using explicit quality/audio hints, device checks and prior working file identities. A background task resolves/preflights a candidate; Roku's native Video node fetches and decodes the media. The English audio guard and rendered-progress checks determine whether that candidate is accepted. A bounded recovery queue tries alternatives when startup fails.

Direct HTTPS sources do not require a PC during viewing. The source picker supports direct HTTPS sources only. Upstream resolver code is retained, but raw torrent/hash-only playback is not enabled by the legacy server connectivity settings. The project does not implement a local torrent engine or a general native audio/video transcoder.

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
| Paging/provider priority in 0.5.16 | Production tests cover later manual choices, full retained retry pools, stale navigation, two-slot priority, opaque key persistence and sustained-progress recording; native remote/performance untested |
| Surround output, HDR variants and full-length reliability | Not certified for 0.5.16 or every display/receiver/source |

One earlier clear HEVC MP4 control failed despite plausible metadata. Multichannel AAC also failed on the tested Stick/projector path. Those counterexamples are why the project does not claim that labels or header inspection guarantee playback.

## Genuine 4K versus output mode

Use actual encoded/native-decoded dimensions when available. HLS/DASH can expose the dimensions of the currently playing segment, and adaptive playback may choose a lower rendition. Progressive file inspection can reveal encoded dimensions, but successful parsing alone does not prove native decoding. A 3840×1600 cinema crop can be UHD; a 1920-wide source remains HD even if HDMI output is 2160p.

The 4K-only filter starts with provider labels. Complete inspected MKV metadata proving all enabled video is known below UHD is rejected in this mode. Mixed/unknown dimensions remain uncertain. No claim is made that all adaptive segments can be forced to 2160p. [Roku Video fields](https://developer.roku.com/dev/docs/video) and [content metadata](https://developer.roku.com/dev/docs/content-metadata) describe the platform boundary.

## English audio and receiver modes

The app excludes explicit commentary/audio-description tracks and prefers supported English dialogue. Untagged or mislabelled language remains uncertain; a file can incorrectly declare English. Projector mode prioritizes likely stereo-compatible sources and keeps available same-file MP3/PCM alternatives visible. Receiver mode consults native decode/passthrough capabilities and prefers suitable surround hints.

The player clears stale audio-track selectors between files and uses bounded native track recovery. It cannot manufacture a missing English track, transform stereo into discrete 5.1, or transcode a codec the Stick cannot decode. Provider labels can confuse AAC 2.0 and AAC 5.1; inspect actual tracks and receiver input where possible.

Version 0.5.14 improves alternative ordering when multichannel AAC hints previously crowded out likely usable English MP3/PCM. Receiver mode penalizes Dolby alternatives explicitly rejected by current native capability. These remain selection hints; native English/audio/progress checks are still required. No audio is converted locally.

Saved quality, autoplay and source-recovery choices apply to new playback. Disabling automatic recovery does not disable English track checks or allow a failed file to be accepted. Terminal native position/duration resets use the last source-scoped observation for same-title recovery, while intentional active seeks to zero are respected.

Automatic Play now offers Start sooner or Compare providers. Early selection can start from available candidates while other add-ons are queued/pending, so its initial recovery pool can be smaller. Compare providers collects the wider pool before selecting. Queued source-list work pauses during playback. When its early candidate pool fails, automatic recovery returns to discovery without a manual Back press, resumes waiting providers or refreshes an exhausted batch, and excludes previously attempted exact delivery URLs. Recovery permits at most two automatic rounds; an explicit Play/Pause retry refreshes discovery. Successful playback remains untouched. Provider results arriving behind Player never replace the accepted source. An available URL/2160p label is still a candidate; native English/audio/decoded-progress checks follow before acceptance.

With HD fallback allowed, Start sooner can choose an early 1080p candidate before a slower provider returns UHD. For quality-focused selection, use Compare providers plus 4K-only, then examine actual playback facts. Priority only reorders waiting provider requests; it cannot ensure the preferred provider has the best file. Native English-track/progress observations do not constitute acoustic language recognition or a full-film stability test.

Source paging exposes later retained eligible candidates while keeping 48 real cards per page. Manual playback still receives the full retained fallback pool. Warm prefetch remains capped at 256 candidates/provider; fresh requests now share the same retained-data budget across the active title. Individual providers retain at most 256 candidates/256 KiB, with a shared 1,024-candidate/1 MiB serialized-data budget. Oversized responses fail controllably. These are application payload budgets, not measured total native memory usage.

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

## Reliable saves and account changes

The local registry is small. This release checks both Write and Flush, keeps failed changes dirty, and shows a storage failure while retrying. Guest resume progress is checkpointed every 30 seconds during accepted playback, with no writes for diagnostics/live channels or unaccepted sources. A sudden interruption can lose the progress since the last acknowledged checkpoint; a persistent storage failure can leave a longer gap. Recent positions are not a promise that the entire film/audio route has been tested.

Stremio caches and pending edits belong to an opaque account identity. On an identity change, old callbacks/local writes are rejected and the previous discovery cache is cleared. Unowned legacy account caches are ignored; reconnect/re-import a manually configured account provider if needed. Guest data remains separate. Account add-on sync updates configuration/removal/order as one validated snapshot and retains explicit local additions.

Cloud changes are optimistic until acknowledged by the server. Distinct titles have distinct pending jobs; unsuccessful writes remain unsynced. Settings → Retry saved changes refreshes the baseline and retries them. Restored uncertain writes await this explicit retry. The queue has 127 waiting jobs plus one active write and is subject to the registry budget; exceeding either limit produces a visible fault. Persistent offline/storage failures cannot guarantee that every recent edit survives a forced process termination. Logout clears the previous owner's pending queue; finish syncing wanted edits before switching accounts.

Public manifest configuration requires HTTPS. Settings → Local development HTTP defaults to Off and admits only private numeric IPs/localhost when explicitly enabled; type such development URLs on Roku. Public HTTP links are rejected, and old public HTTP provider records are not restored. The browser import page remains HTTPS-only.

Roku resume/history and the outbox use seconds. The Stremio API uses milliseconds; conversions happen at the account boundary. This fixes future synced positions and resume imports, but cannot infer the intended value of an incorrectly written older cloud checkpoint.

## 0.5.19 playback changes

4K first now keeps UHD-labelled candidates ahead of HD stereo hints and previously remembered HD files. Native file/audio checks can reject incompatible UHD files; an HD fallback is possible when permitted. 4K only remains label-based initially and rejects known below-UHD inspected MKV video.

Online subtitle downloads are off by default. Enable Settings → Online subtitles to add those tracks to native Options; they are matched by title/episode and may not match the exact release or timing. Embedded captions follow Roku caption preferences. Press * while playing to change caption mode/track. The app does not silently change Roku global caption settings.

The source status now displays elapsed time and cancellation guidance. Each source-list HTTP request has a shared 45-second acquisition/retry budget; the two-worker queue, JSON processing, file inspection and native buffering are separate stages. This is a bounded wait policy, not an instant-start promise.


## 0.5.20 resolution evidence

The native Video node can retain read-only segment facts after a file ends. Codec/state changes must not reuse those facts to label the next file 4K. The player now accepts dimensions/HDR only from a fresh segment event during active HLS/DASH playback, and preserves the last valid video event across audio-only notifications within that file. Every new handoff clears the prior file’s dimensions. Progressive file headers and HDMI output remain separate evidence. The on-device switch check that exposed this defect used a genuine UHD control followed by a lower-resolution HLS control; details are in [Validation](VALIDATION.md).
