# Changes

## 0.5.14 — 2026-10-14

- Add a featured Home, five remote-friendly shortcuts, advertised genre shelves and Continue Watching. Down expands browsing to two visible rows; See all opens the exact full catalog/genre. Keep Search, Discover, Library, Add-ons, Settings, About and native microphone search.
- Bound Home to 12 populated preview rows and 24 titles per catalog, with eight base attempts, eight genre jobs and eight missing-manifest attempts. Load catalogs off the render thread, coalesce featured artwork after 250 ms, use a 640×274 image and defer hidden-screen grid construction. Full catalogs and pagination remain in Discover; metadata/episodes still load in Details.
- Add persistent Picture quality (4K-first with 1080p / 4K-only), Next episode and Source recovery choices. Validate booleans and preserve existing installation preferences. A per-title quality toggle overrides the default without changing the saved setting.
- Fix reproducible old queued timer events affecting newly armed startup, English-audio, retry, audio-repair and next-episode operations. Keep the startup deadline armed when an unaccepted native stream stops.
- Preserve the current source's last measured position/duration across native terminal resets, so an early ending recovers the same title instead of becoming false completion. Explicit active seeks to zero remain zero.
- Rank likely usable English MP3/PCM above repeatedly failing multichannel AAC hints in projector mode, and penalize Dolby alternatives that current receiver capability explicitly rejects. Actual native checks remain required.
- Release playback queues and handoff metadata on player exit. Keep bounded source preloading, 32-record hashed outcome memory, resume/library data and configured add-ons.
- Add production callback/policy coverage for timing, terminal position resets, persistence, preview caps, off-screen work, artwork cancellation and full-catalog navigation.

The complete software suite and compiled package checks pass. Illustrative Home layouts were reviewed. **0.5.14 has not been installed, frame-rate profiled or physically playback-tested.** It does not guarantee zero lag, audible English audio, every provider file, UHD/HDR or surround compatibility.

## 0.5.13 — 2026-10-14

- Rename the visible app to Crimson Cinema with a dark red palette, original icon/splash, clearer menu contrast and a small Rokumio/upstream credit on the separate About page. Preserve existing deep-link, DIAL and registry identifiers.
- Add **Check add-ons** in Add-ons and Settings: sequential 8-second manifest requests, progressive named results, a 120-second overall deadline, Play/Pause retry and Back cancellation. Reject stale results and old deadline events, preserving the selected row during updates.
- Distinguish access denied, missing endpoint, rate limiting, provider outages, timeout/network errors, changed/invalid manifests and incomplete checks. Keep private addresses and raw provider errors out of results. Catalog/subtitle-only add-ons and empty title responses are not falsely marked broken.
- Show the selected provider's source request status and flag partial provider failures while other sources remain available. Identify filtered choices, provider-account status clips and pending downloads separately.
- Replace a blind audio toggle with explicit **TV / projector speakers** or **HDMI soundbar / receiver** choices. Add **Audio connection**, fresh native output/codec reports, Stereo-setting guidance, generic HDMI wiring and documented AX700 setup.
- Add 81 production diagnostic/controller/audio assertions and a public add-on issue template and troubleshooting guide.

The complete software suite and compiled package checks pass. Authoring previews were reviewed; 0.5.13 has not been installed or physically tested. This update does not add transcoding or guarantee that every provider, file or receiver works.

## 0.5.12 — 2026-10-14

- Automatically continue to the next episode after an accepted natural finish, with a five-second countdown and Back cancellation.
- Preserve opaque provider episode ids, numeric ordering, series title/artwork, 4K-only filter and audio preference. Fetch fresh sources; never reuse the previous episode's signed URL or resume offset.
- Roll into the next regular season; keep specials within season zero. Stop at the final episode, missing/mismatched metadata, or a next episode with a known future release date.
- Prime missing series metadata off a Timer and reject stale worker/results, hidden-screen events and requests belonging to previous playback.
- Keep natural completion distinct from early-ending/source-recovery behavior. Save completed watch state even when the native terminal position resets to zero.
- Reuse the existing source screen so repeated episodes do not grow the navigation stack or duplicate static Player nodes.
- Correct the local diagnostic version from a stale 0.5.9 string to 0.5.12.
- Add 67 focused production callback/policy assertions, public build/setup/playback/development documentation and Open Sans redistribution license.

This release has software/package validation. The new episode transition has not yet been physically tested on Roku. It does not add transcoding, automatic app updates, skip-intro detection or guaranteed zero buffering.

## 0.5.11 — native projector/audio fixes

- Reset stale native audio-track selection between files; remove codec forcing that hid English alternatives.
- Preserve same-file English MP3/PCM options for bounded native track recovery, and guard HLS seamless track-selection behavior.
- Normalize AAC aliases/language uncertainty and exclude descriptive audio/commentary.
- Query current local decoder/passthrough capability rather than assume support from hardware marketing.
- Couple source audio/channel hints so an unrelated 2.0 string cannot turn AAC 5.1 into stereo.
- Preserve previous working source identities while discarding obsolete negative cache records.
- Reserve labelled UHD candidates in the bounded source prefetch cache; retain 1080p choices in all-quality mode.

## Earlier derivative work

The original community client is MIT licensed. This derivative adds direct-source format/header handling, manifest/import fixes, source ranking and automatic recovery, audio presets, voice keyboard/transport wiring, clearer cards, bounded native/file facts, resume handling and short-lived source preloading. Earlier device observations establish specific compatible paths, not universal playback support. See [compatibility evidence](docs/PLAYBACK.md).
