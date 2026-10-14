# Changes

## 0.5.20 — 2026-10-14

- Fix stale adaptive resolution evidence after switching files. Native Video can retain its previous streamingSegment; codec changes no longer poll that field. Only a fresh segment notification during an active HLS/DASH handoff can establish displayed dimensions/HDR. Missing or rejected evidence stays unknown.
- Add regression coverage for HLS-to-HLS switches, HD downgrades, DASH, stopped/exited/deferred playback and missing segment dimensions.
- Retain the 0.5.19 Back/checkpoint, shared source-request deadline, UHD-first and online-subtitle opt-in fixes. Controlled physical tests of that core passed native component saves, durable periodic/Back checkpoints, repeated screen exits, source-request cancellation, 3840×2160 HEVC/AAC HLS decoding and seek/pause. They exposed this additional resolution-display defect.

These checks do not certify every movie, acoustic language, surround, full-film endurance or a memory leak threshold. The tested route reported Stereo, not Dolby passthrough. See [Validation](docs/VALIDATION.md) for the exact evidence and limits.

## 0.5.19 — 2026-10-14

Hotfix for a physical Roku failure found immediately after installing 0.5.18. This remains experimental.

- Fix a confirmed Back/checkpoint crash: the resume record now crosses SceneGraph callFunc as one object, rather than an overlong positional call. The store validates the record and reports persistence acknowledgement. Account replay uses the same boundary. A new syntax-tree check covers every production callFunc and executes the real store forwarding path in checkpoint tests.
- Give GET/HEAD retries one shared monotonic request budget, including backoff. Negative native transport statuses cannot multiply a source lookup into three full 45-second waits. Slow providers and native buffering still have their own costs.
- Show elapsed source lookup time and Back cancellation text; stop its timer when hidden or cancelled. The read-only status endpoint includes counts and phase state without configured provider URLs. App version comes from the installed manifest.
- Make 4K first prioritize UHD labels ahead of HD stereo hints and remembered HD files. English/native audio checks remain mandatory; HD alternatives remain available when fallback is enabled. Labels still do not establish actual encoded/decoded quality.
- Add Settings → Online subtitles, off by default on new and upgraded installations. Embedded captions and Roku Options remain available. Opting in restores online subtitle choices, whose release/timing may not match the selected file.

0.5.18 installed and launched, then a real source played AVC/AAC English with 1920×800 header metadata and advancing A/V timestamps before the resume-save interface error locked Back. This is a confirmed runtime regression, not a provider buffering diagnosis. A full movie, receiver surround, UHD sources and long-session memory have not been signed off.

## 0.5.18 — 2026-10-14

This is a reliability release responding to the deeper 0.5.17 audit. It remains an experimental prerelease without physical Roku sign-off.

- Separate Stremio caches and pending edits by an opaque account identity. Ignore unowned legacy account caches; disown old account workers, pairing results, import results and local screen writes on a session change. Clear provider discovery and rebuild Home when the account changes.
- Replace global pending write slots with a bounded per-item/per-kind queue. Coalesce only edits to the same item, wait for an initial account snapshot, retain unsuccessful writes, and preserve the pending outbox in account-owned storage. Settings → Retry saved changes refreshes the account baseline before replaying; uncertain writes restored after restart await explicit retry.
- Check both registry Write and Flush. Retain dirty state, restore prior buffered values after refused transactions where possible, and retry outside native Video callbacks. Admission counts all registry sections against a conservative 30 KiB uncompressed budget; native compressed registry limits remain authoritative.
- Fix the seconds/milliseconds boundary between Roku playback and Stremio library state, including synced resume and re-add paths. Preserve unsynced episode marks/unmarks with the durable outbox and reapply pending local resume after a fresh account pull.
- Add dirty-only local resume checkpoints every 30 seconds during accepted playback. Failed flushes cannot advance acknowledged progress. Diagnostics, live channels, unaccepted sources and old account screens cannot save a checkpoint.
- Reconcile validated account add-on snapshots as a whole: replace changed configurations, remove absent account-owned providers, apply order and retain intentional local additions. Invalid/failed snapshots preserve the previous usable collection.
- Acquire HTTP bodies into temporary files with endpoint-specific decoded size checks before reading/parsing, plus JSON-depth checks. Bound retained source fields and share 1,024 candidates/1 MiB of serialized source data across the active title's providers, with individual limits of 256/256 KiB. Provider/manifest collections are bounded; subtitles have a 64-track merged cap. Temporary transfer files can overshoot between checks; this is not a hard socket or total application-memory cap.
- Construct and rank automatic provider pools in a worker. Exhausting an early playback pool resumes queued discovery or refreshes an exhausted batch, excludes attempted exact delivery URLs in memory, retains the checkpoint and permits at most two automatic recovery rounds. Explicit retry requests fresh discovery. Late results cannot replace accepted playback.
- Never automatically replay POST failures; GET/HEAD negative transport failures retain bounded retries. Require transport and application success for Stremio write acknowledgements.
- Require HTTPS for public provider manifests, including cached/off-thread admission. An explicit local development setting permits HTTP private numeric IPs/localhost entered on Roku; the browser setup page continues to require HTTPS.
- Publish the exact tested CI ZIP with checksum, package verification and commit/run provenance rather than a separate release rebuild.

The LAN setup page still requires the Add-ons screen and retains its Host/Origin protections. A short-lived pairing code/TV confirmation remains a hardening recommendation. Native installation/upgrade, audible stereo/surround, full-film stability, seeking, episode transitions and memory profiling remain hardware validation work; software tests do not certify these.

## 0.5.17 — 2026-10-14

- Fixed Home catalog re-entry: switching Movies/Shows/See all resets the prior page offset and results, so valid new pages replace the old titles.
- Fixed Discover pagination for short pages and malformed metadata. The store/task/screen carry the consumed raw count separately from usable tiles; near-end loading also works with fewer than four rows.
- Save accepted watched progress on the recovery timer before clearing the decoder. Exiting an unsuccessful replacement keeps the checkpoint; successful replacements can save later progress normally.
- Manual Left/Right provider changes cancel both the automatic grace timer and pending ranking worker, matching manual source-page navigation.
- Saved titles and Continue Watching retain a validated opaque metadata-provider key. Restoration uses current installed configuration; older/account entries use compatible type/id-prefix matching instead of sending custom identifiers to Cinemeta. No configured URL is added to history.
- Warm results preserve bounded account/pending-download counts through adoption. Both status and empty-source explanations retain errors without keeping the unlimited raw response.
- Working-source proof restarts after accepted playback resumes, using fresh samples and retaining diagnostic exclusions.
- Public setup rejects `/playback-test` mutations. Normal imports retain their Add-ons-screen gate. Connections have 10-second idle and 30-second absolute deadlines swept from the nonblocking main loop.
- Repaired punctuation in Add-on checks. Clarified legacy server settings as connectivity checks: this build selects direct HTTPS sources and does not enable raw torrent/hash-only playback.
- Added complete-flow regressions for catalog/store/task transitions, custom saved-series routing, recovery/proof resumption, manual provider precedence, warm diagnostics and setup controls.

Software/package validation does not certify audible English, surround/HDR, sustained UHD decoding or native rendering. This experimental prerelease has not been installed or physically tested.

## 0.5.16 — 2026-10-14

- Replace the inaccessible 48-source cutoff with true pages of 48 real source cards, fixed More/Previous controls and global source/count information. Preserve the full retained candidate array for playback fallback. Provider/filter/refresh changes reset or clamp pages; returning from Player restores the page and focus.
- Guard page navigation and stale/duplicate selections so an old More/Previous event cannot launch a movie. Explicit browsing cancels automatic selection; late provider results do not steal current page focus.
- Prioritize waiting requests by saved preferred provider, then most recently working provider, then stable installation order. Keep original provider indices, the shared two-worker cap and abandoned-transfer ownership. Warm selection can include a preferred provider beyond the first four installed.
- Add **Settings → Preferred source**, with Automatic and a scrolling list of installed stream providers. Reject stale Settings subsection events with distinct native list generations. Save only opaque provider fingerprints from public add-on ID/hostname; configured paths, queries and userinfo are excluded.
- Record the last working provider only after the existing English-track/unmuted/native A/V progress gate, excluding diagnostic playback. Retry refused preference writes. Priority changes retain ready source results and do not start work behind Player.
- Distinguish **Queued** from **Requesting sources** per provider and in overall counts. Preserve Start sooner and Compare providers, 4K-only filtering and all previous playback preferences.
- Add paging, priority, persistence and progress-gate tests. The complete suite passes **4,704 BrightScript/cinema assertions**, plus separate Node media/transport/mock suites.

This release has software/package validation and independent code review; it has not been installed or physically profiled/tested. Start sooner can use a smaller/HD pool; Compare providers plus 4K-only is the quality-focused option. Initial source labels do not certify decoded UHD. Existing warm cache limits and uncapped ordinary response bytes remain documented.

## 0.5.15 — 2026-10-14

- Remove the mandatory all-provider barrier for automatic Play. **Start sooner** briefly compares ready candidates and can begin while another provider is pending; **Compare providers** retains the full comparison as a saved setting. Quality/audio filters still apply. Later provider results never replace accepted playback.
- Share a two-worker source-list budget between warm preloading and explicit source loading. Queue every eligible provider rather than discard providers. Pause queued requests while Player is in front and resume on return. Abandoned running lookups retain their slot until completion, because STOP does not prove that the network transfer ended.
- Preserve request tokens, duplicate-result guards, manual source precedence and fresh-link refresh. Cancel/re-rank automatic selection when the quality filter changes. Empty early selections can reconsider newly arriving candidates rather than declare failure while providers are pending.
- Add direct install-ZIP links and clearer sharing/update instructions. Developer mode, each user's private source configuration and manual updates remain necessary.
- Update the supported interpreter/compiler patches, remove the abandoned archive-extraction dependency and eliminate the critical development advisory. Residual development advisories remain documented; Node development dependencies are excluded from the installed Roku ZIP.

Early playback can have fewer initial recovery alternatives than Compare providers. Source-list workers are bounded; total network sockets, response bytes and device frame rate are not certified by this change. This release has software/package validation and has not been installed or physically tested.

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
