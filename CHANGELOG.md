# Changes

## 0.6.0 — feature preview, not released

- Add Replay on live Sources to browse another installed sports provider, retaining the event name for manual comparison. Keep native IDs, source pools and recovery isolated; reuse the existing navigation stack and preserve movie controls.
- Include provider-declared `sports` catalogs alongside TV/channel catalogs. Exercise custom type registration, catalog selection, native stream lookup and direct resolution in production-boundary tests.
- Add a bounded, private-profile reliability probe with fresh same-event resolution, request-stage failures and optional PC decode measurements. Record repeated StremVerse playlist 403, shared upstreams, a decodable holding card and failed Nebula media plus separate sustained 720p NHL checks through StremVerse and CNCVerse. Disclose the shared gateway rather than claim independent delivery. Correct Highfly status to require legitimate configured-manifest testing.
- Make installed provider catalogs the Sports entry point. Preserve original event IDs, media types and private configuration; pin live fallback to the selected provider/event instead of assuming ESPN IDs are understood.
- Add explicit live playback with near-edge start, no movie resume/next episode and a visible English/unlabelled-audio choice. Keep unknown language distinct from English verification and preserve decoder/progress/receiver checks.
- Refresh live source lists after 30 seconds at interactive handoff boundaries; retain bounded recovery and Back cancellation. Explain browser-only results; preserve query URLs and per-item headers; recognize bounded extensionless HLS/DASH responses.
- Verify real free StremVerse playlists/segments and PC H.264/AAC decoding (288p and 1080p). Record failed/403 sources and lack of Roku, audible-language, sustained-reliability or rights sign-off. No service, proxy or provider is silently installed.

- Add Sports navigation, 13 league schedules, date/status filters and installed TV/sports catalog shortcuts. Distinguish schedule-only, upcoming and provider-backed entries; never infer video from a listing.
- Fetch schedules directly on Roku with one retained worker, a 10-second request budget, 1 MiB response ceiling, bounded rows/fields and stale/duplicate callback protection.
- Add a dependency-free standalone sports add-on publisher for operator-authorized public HLS/DASH feeds. Reuse existing native source ranking, audio preferences and bounded recovery; no accounts, media proxy, default streams or paid hosting required.
- Reject expired feed sources during discovery and resolution. Preserve expiry through candidate budgeting.
- Add paused-Down manual next episode with accepted-progress saving, fresh sources, one-use navigation authorization and cancellation guards. Preserve automatic-next preference and existing remote controls.
- Add production-boundary regression tests, actual local HTTP protocol tests and reproducible public provider probes. Document unresolved broadcast rights/delivery and physical Roku validation rather than claim universal sports coverage.

## 0.5.29 — 2026-10-17

Fair catalog previews and correct smaller-page browsing. Experimental prerelease; catalog availability is separate from stream delivery.

- Share the existing eight base Home requests across installed providers before taking a second row from one provider. Retain eight maximum genre requests, twelve populated rows and 24-poster previews; keep later genre descriptors available.
- Pass validated catalog page sizes through Discover's screen, task and store. Use raw provider offsets, respect explicit end markers, stop empty/repeated pages, and preserve case-sensitive opaque IDs.
- Document an optional account-free TMDB catalog configuration that returns IMDb-compatible movie/show and episode IDs. No provider or account is bundled or silently added.
- Preserve practical-UHD selection, English/audio checks, playback recovery, voice, subtitles, next episode and acknowledged persistence.

## 0.5.28 — 2026-10-17

Prefer practical UHD encodes during automatic selection and clarify private checkpoint observations. Experimental prerelease; no source-speed or complete hardware certification.

- Defer UHD files labelled or declared above 35 GiB until ordinary/unknown-size UHD candidates have had a turn. Apply this after source memory and within host diversification, before the bounded automatic pool is truncated. Large UHD remains eligible before 1080p; manual order and compatibility checks are unchanged.
- Parse bounded numeric file-size hints before unambiguous GB/GiB/MB/MiB labels. Missing or conflicting evidence remains unknown. File size is a startup heuristic, not measured video bitrate, native quality proof or a permanent rejection.
- Add passive acceptance/checkpoint guard diagnostics to distinguish a timer notification from a save attempt. Preserve acknowledged persistence and all existing save guards.
- Document the observed large-file delivery mismatch, the limited steady-playing window and researched Roku alternatives without claiming universal free 4K or lifetime access.

## 0.5.27 — 2026-10-17

More reliable UHD candidate selection and fresh source discovery. Experimental prerelease; source labels and a short native test do not guarantee sustained 4K delivery.

- Diversify delivery hostnames inside each automatic quality tier before repeating a host. Keep the highest-ranked/remembered UHD first, preserve the six-candidate initial pool and three-UHD-before-HD budget when fallback exists, and leave manual source order unchanged. Host buckets are transient and never logged or persisted.
- When automatic 4K-first playback inspects a candidate and proves it is HD, retain it as fallback while later eligible UHD candidates are checked. Deferral is bounded, does not mark the file broken, and leaves manual choices, strict UHD and accepted playback protected.
- Refresh aged completed provider results before a new selection without interrupting accepted playback or abandoning live requests. Preserve resume checkpoints, exclusions and the shared two-worker budget.
- Accept native boxed integer UHD counts instead of reporting zero on a valid worker result. Clamp counts to returned candidates, reject malformed types, and expose effective quality/comparison modes in private status diagnostics.
- Preserve saved 4K-first plus 1080p fallback, Compare providers, English track checks, source recovery, surround/projector preferences, source memory, subtitles, voice and next episode.

## 0.5.26 — 2026-10-17

Follow-up repairs from production-path review of the 0.5.25 candidate. This remains experimental; source coverage and uninterrupted native UHD are not guaranteed.

- Disown completed provider batches before a recovery reload. Their retained empty task slots previously blocked LoadStreams, leaving recovery to re-rank stale results. Preserve pending requests, the two-worker budget, accepted resume position, failed URL exclusions and the bounded discovery round. Regression tests reproduced eight failing checks before the repair.
- Give explicit foreign-language-only annotations priority over an English word in a title. Keep mixed-language sources eligible for actual English track verification.
- Retain unsuccessful source-memory outcome batches with bounded retries and same-file coalescing. Newer outcomes must win over older in-flight writes; persistence failure must not silently leave old working hints preferred.
- Accept boxed/64-bit native playback positions for relative voice seeks, parse bounded decimal offsets without float overflow, validate duration and preserve paused playback. Production callback regressions cover real boxed numeric objects and unchanged native control behavior.
- Retain the 0.5.25 progress watchdog, reduced audio scans and private delivery diagnostics. No new accounts, sources, streaming credentials or external server are bundled.

## 0.5.25 — 2026-10-17

Recovery for stalled native progress, callback efficiency and buffering diagnosis, based on default-branch commit `766701d`. Experimental prerelease; this patch has not yet been installed for physical verification and does not claim a measured playback-speed increase.

- Recover when accepted movie/episode playback remains labelled `playing` but its reported position and available media-clock fields stay unchanged for 45 seconds. A three-second timer uses current-source ownership and generation guards, restarts observation on movement/seek/pause/discontinuity, and discards gaps over nine seconds. Startup, diagnostics, live channels and disabled recovery are excluded. The existing bounded recovery coordinator preserves accepted resume progress; this is not proof of a slow host.
- Reduce repeated English-facts inspection from six passes to one per playing-state event. Reuse one snapshot without mutating provisional audio facts; preserve rendered-sample acceptance, source proof, pause/resume and explicit rejection/status behavior.
- Add passive network diagnostics with a ten-second cache, bounded connection/protocol/signal fields, transmit-failure/retry counters and general memory level. Unknown native throughput units remain explicitly unspecified. Counter differences are observations, not packet-loss rates or media-host speed tests. No network names, addresses, device identities or raw native records are retained.
- Retain at most 64 source-scoped native state/buffering event samples. Event snapshots and callback-time fields remain separate, receipt timing is labelled accurately, and stale generation/node events are rejected. The diagnostic observer does not control playback.
- Reuse the existing bounded range response for a declared total file size, including multi-gigabyte totals. Combine it only with a fresh source-correlated native duration event to estimate average container bits/second. Missing duration stays unknown; this is neither peak video bitrate nor download throughput, and adds no media request.
- Time actual periodic checkpoint work with fixed count/last/maximum scalar metrics. Clock failures cannot block saves or fabricate duration, and the existing 30-second cadence, dirty-write retry and durable acknowledgement remain unchanged.
- Add production callback and native-boundary regressions for playing-state freeze recovery, reduced audio work, checkpoint timing failures, private diagnostic fields, stale source events, network counter resets and source-specific size/duration estimates.

Read-only observations of installed 0.5.24 recorded three native-reported underruns, then unchanged native position and audio/video timestamps across 22 samples over 44.7 seconds while the same source remained labelled `playing`. This establishes stalled native progress, not its root cause or a performance result for 0.5.25; measured host speed was unavailable. Earlier physical evidence remains separately identified in [Validation](docs/VALIDATION.md).

## 0.5.24 — 2026-10-17

Repeated-buffering recovery and catalog freshness, based on default-branch commit `146141c`. Experimental prerelease; this is not a bandwidth increase or a guarantee of source availability.

- Recover from repeated short native-confirmed underruns that previously reset the continuous-stall timer indefinitely. After accepted playback, three underruns totaling at least fifteen seconds within two minutes can request another source while an underrun is still active. Normal pause, seek/startup buffering, disabled automatic recovery, live channels and diagnostics are excluded. Accepted resume progress and bounded discovery are preserved.
- Add allowlisted native delivery and buffering diagnostics. Source ownership/generation checks reject stale reports, and URLs remain private. Roku's network estimate is identified as a measurement at stream selection, not a continuous speed test. No undocumented buffer controls, transcoding or competing downloads are introduced.
- Include Home year-filtered New feeds when the provider explicitly advertises the runtime current year. Unsupported/missing required extras remain excluded, and existing request/row/title limits remain.
- Refresh Home and Discover after thirty minutes on active re-entry. Keep old titles while fetching, preserve selection where possible, retain prior data on failure, and cancel automatic refresh when leaving. No periodic catalog refresh runs underneath playback.
- Document catalog-versus-stream availability and TorBox's removal of its official hosted Stremio add-on. No accounts, subscriptions or providers are added automatically.

## 0.5.23 — 2026-10-17

Automatic source-selection repairs, starting from latest default-branch commit `1a7d351`. Experimental prerelease; physical playback sign-off remains incomplete.

- Skip recognized download-only, 10Gbps and explicitly non-English-only delivery entries. Keep mixed/unknown language candidates for real English track checks; filenames never authorize sound.
- Distinguish release resolution from provider branding and remaster labels. Rank 2160p, then 1080p, then other/unknown qualities; prefer English hints and remembered working files within a quality tier.
- Give pending providers up to four seconds to return UHD when only HD is ready. UHD starts a 750 ms comparison window; Compare providers still waits for all. Re-rank results that arrive before initial handoff, without replacing accepted playback.
- Limit each automatic pool to six candidates, reserving fallback slots after three UHD attempts when eligible HD is present. Full manual browsing remains available. Existing two-round remaining-provider/fresh-link recovery stays bounded and excludes attempted URLs.
- Skip recent temporary failures for ten minutes when a stable file fingerprint exists. Explicit fresh-link retry can reconsider temporary failures; proven file incompatibility remains excluded. Only opaque hashes/outcomes persist, never configured or signed URLs. Sources lacking a stable fingerprint still receive in-session exact-URL exclusion.
- Inspect opaque direct URLs with the existing bounded byte-range worker. An evidenced Matroska container sets native MKV playback; known MP4/HLS/DASH paths retain their existing handling. Reject malformed/oversized/nonzero ranges, clean temporary outputs, and keep native English/codec/progress guards authoritative.
- Count UHD on source workers rather than re-scan entire provider arrays on the render thread. Add callback integration regressions for delayed UHD, stale ranking, failed-source cooldown/retry and opaque MKV resolution.
- Document optional account-free HDHub/Pluto setup and their limits. No providers, accounts, media or credentials are silently bundled.

## 0.5.22 — 2026-10-15

Account sync and data-integrity repairs, based on the latest default branch `bcd32111d9b0996b35285b1a684513d88f66b0c1`. Experimental prerelease; no physical device validation for this update.

- Import supported account entries even when an unrelated descriptor is unsupported or malformed. Exact duplicates are counted and skipped; conflicting duplicate manifests are invalid; distinct configurations sharing a manifest ID keep separate stable internal identities. Configuration paths/queries stay private and unchanged. Partial snapshots never authorize removals; complete snapshots reconcile configuration, order and account-owned removals while preserving local-only additions.
- Consume an available sync result when the finished notification arrives first. Keep empty initial and duplicate/stale notifications harmless. Show loading, complete, partial, failed, empty-account and unsaved outcomes with counts and Add-ons → Sync Stremio add-ons retry.
- Treat declared catalog lists independently of the manifest resource list. Include catalog/manifest changes and account order in Home, Search and Discover signatures; invalidate all consumers after imports. Offer explicit local-only Cinemeta onboarding after a complete account snapshot confirms catalogs are absent; never alter the remote collection or silently install providers.
- Require a successful account identity lookup before completing link-code login. Bound the pairing deadline using monotonic elapsed time. Report failed authentication persistence.
- Restore the account outbox only at startup/session reconciliation. Preserve newer intent during sync-status cleanup. After uncertain writes, block newer same-title edits until an explicit retry obtains a fresh baseline; subsequent coalescing cannot remove that gate. Unrelated titles remain independent.
- Bound automatic dirty-save retry to three timer rounds, retain dirty state and expose Settings → Retry device saves for every profile. Existing accepted-progress and 30-second playback checkpoints remain.
- Require TV confirmation within 60 seconds for browser add-on imports, in addition to the open-Add-ons, session, private-interface and Host/Origin gates. Expire abandoned requests; reject stale/cancelled confirmations. Add restrictive response CSP/security headers to the Roku form and a hash-based script policy to the optional localhost inspector.
- Add production callback integration tests spanning login/task/API/StoreHost/account stores and Search/Discover source controllers, plus snapshot, outbox, registry and security failure injection. Preserve playback selection, UHD/all filters, provider priorities, pagination, audio/subtitle preferences, voice, native controls, next episodes and source memory.

See [audit](docs/AUDIT-0.5.22.md), [security review](docs/SECURITY_REVIEW.md) and [validation](docs/VALIDATION.md). No credentials, content or streaming accounts are bundled. Existing development-tool advisories remain documented; they are excluded from the Roku ZIP.


## 0.5.21 — 2026-10-14

- Replace per-character substring allocation in the JSON depth guard with a linear UTF-8 byte scan. Preserve the response-byte and 32-level nesting budgets, including escaped quotes/backslashes. This addresses long catalog/series responses taking tens of seconds on the Stick.
- Pass the successfully fetched complete episode list from Details to Episodes. Full endpoint episode metadata takes precedence over empty/partial catalog previews; provider episode IDs and watched ordering are retained.
- Prepare episode groups once with native sorting and stable duplicate-coordinate ordering. Build and refresh at most 24 episode cards per timer callback, yielding after a small time budget. Back cancels requests and incomplete builds; old-account callbacks cannot complete them. No episode-count cutoff is introduced.
- Reopen an already built grid for the same Details snapshot without rebuilding it. Title, provider, account and metadata-refresh ownership invalidate reuse.
- Add Discover Play/Pause retry with a new page-zero request, canceled-result protection and clearer loading/error hints.
- Add production-controller and batching regressions covering 511/880-record lists, all later cards, preview merging, snapshot ownership, canceled work and UTF-8/escaped JSON.
- Retain the earlier native resume/checkpoint, UHD-first, source deadline, online-caption opt-in, account isolation and durable-save fixes. This is still an experimental prerelease, not a certification for every provider or audio/display route.

## 0.5.20 — 2026-10-14

- Fix stale adaptive resolution evidence after switching files. Native Video can retain its previous streamingSegment; codec changes no longer poll that field. Only a fresh segment notification during an active HLS/DASH handoff can establish displayed dimensions/HDR. A new handoff starts unknown; audio-only notifications preserve the last fresh video dimensions within that same file.
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
