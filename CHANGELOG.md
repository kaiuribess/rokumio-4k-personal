# Changes

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
