# Release validation — 0.5.29

Prepared on October 17, 2026 from default-branch commit `b01fab3f244d0a637a2ecbbcca328ffd3c0bc46f`. Experimental prerelease; software, catalog/provider checks and native playback are separate evidence.

| Command/check | Result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; pinned development dependency tree unchanged. |
| `npm test` | Exit 0; 6,385 BrightScript assertions across 36 runs plus 142 cinema-policy assertions = **6,527**. Separate 56 Node cases, 29 MP4 checks and 50 playlist assertions passed. |
| `npm run build` | Exit 0. |
| `python scripts/verify-package.py` | Exit 0; 207 members, 52 XML components, 273 root/3 relative script references, 164 interfaces. |
| Focused production regressions | Home97, catalog store/worker/screen79, Discover64, Home refresh44 passed. |
| Independent source review | Case-sensitive IDs and later genre-descriptor previews were repaired during review; final request/row/poster bounds and raw-offset handling passed. |
| Literal private-data check | The authorized private key and complete configured URLs were absent from all 340 tracked files and 207 packaged members. Only ignored private setup files contain them. |
| `git diff --check` | Passed. |

Before repair, production Home regressions failed four checks: earlier providers spent the preview budget before TMDB, and a failed first provider took its second request before the next provider's first. The prior transpiled CatalogStore also classified a full advertised 20-item page as terminal. New tests execute real Home planning, catalog store, Discover task and screen callbacks, preserving eight base/eight genre requests, twelve rows, 24-poster previews, raw skip offsets, explicit end markers, stale-worker rejection and case-sensitive opaque identifiers. Empty or repeated pages terminate safely. No assertion was weakened.

The optional account-free TMDB ElfHosted configuration was checked with both IMDb flags enabled. Latest Releases movies and Trending movie/show rows returned IMDb IDs, and Family Guy metadata supplied 483 season/episode records with compatible IDs. The user confirmed one successful import. This configuration supplies metadata; generic catalog-only IMDb metadata fallback remains a separate limitation. See [catalog setup](FREE-SOURCES.md).

A separate owner-authorized TorBox/Comet configuration returned a valid manifest, 16 HTTPS movie candidates (eight UHD-labelled) and one episode candidate. The user confirmed one successful import. The first PC range check followed a redirect to a TorBox CDN, which returned HTTP403 with zero media bytes; it is not a native UHD/audio or sustained-delivery success. Direct Torrentio public-manifest and TorBox API checks from the PC were also refused, so those results alone do not identify invalid credentials. Personal configured paths, key, URLs and responses are excluded from repository, package and public reports. No subscription purchase, account deletion, credential rotation or remote Stremio-account modification was performed by this work.

---

# Release validation — 0.5.28

Prepared on October 17, 2026 from latest default-branch commit `98c2d3c04f7775d7ba4f3f8a46dafffcefa95844`. Experimental prerelease; no sustained native UHD or audible-surround certification.

| Command/check | Result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; pinned development dependencies unchanged. |
| `npm test` | Exit 0; 6,304 BrightScript assertions across 36 runs plus 142 cinema-policy assertions = **6,446**. Separate 56 Node test cases, 29 MP4 checks and 50 playlist assertions passed. |
| `npm run build` | Exit 0; no assertion was weakened. |
| `python scripts/verify-package.py` | Exit 0; 207 members, 52 XML components, 273 root/3 relative script references, 164 interface implementations. |
| Focused automatic-selection regression | 9 assertions failed before the size-policy repair. Final production worker/store/budget tests passed 247 assertions, including 74 new checks. |
| Focused checkpoint/native regressions | 151 reliability-flow, 157 delivery-info and 423 native-playback assertions passed. |
| Independent source review | No blocker in automatic size-class/memory/host ordering or passive checkpoint diagnostics. Save guards, cadence and durable acknowledgement remain unchanged. |
| `git diff --check` | Passed. |

The new size rule applies only to automatic selection. Ordinary/unknown UHD precedes files above 35 GiB, then HD follows, within the existing bounded pool/recovery policy. Tests cross actual source budgeting, the SourceSelectionTask callback and source-memory ordering; they include remembered giants, multiple hosts, native boxed/64-bit size values, threshold boundaries, malformed/conflicting labels, exact-URL exclusions, English eligibility, audio ranking and unchanged manual ordering. File size is a heuristic, not elementary video bitrate or throughput proof.

One normal 0.5.27 movie source reported a 3840x2160 encoded header, English HEVC/E-AC-3 metadata and 87,937,111,321 declared bytes over 8,700 seconds (about 80.9 Mbps average container rate). Its selection-time network estimate was about 36 Mbps, whose persistence was not established. A subsequent 59-sample/129.375-second window showed steady reported playback and advancing position, with no buffering-state sample; the user's intermittent-pause report remains relevant. Roku did not report decoded segment resolution for that source. This evidence supports investigating delivery fit, not declaring either universal failure or complete UHD success.

The old checkpoint timing count remained zero in that window. That alone does not prove registry failure: it was incremented only after several save guards. New passive fields separate callback-fire count, guard outcome, acceptance and requested timer control from persistence acknowledgement. They do not change saving behavior or claim a native timer is running. Regression tests preserve Write/Flush refusal handling and previous acknowledged progress.

The further free-source hunt found smaller explicitly UHD-labelled candidates but no independently verified sustained-UHD improvement. One No Way Home file exposed 3840x1608 HEVC metadata and AC3/TrueHD/DTS tracks; English language and native playback were unverified. Other bounded resolver checks returned HTTP 403/404 or HD metadata. Broader aggregation repeated the 4KHDHub family. No additional source, account, trial or payment was installed/activated during these checks. See [free sources and other clients](FREE-SOURCES.md).

---

# Release validation — 0.5.27

Prepared from latest default-branch commit `78739ac9cda30935e370053daae5adf871163a26`. This remains an experimental prerelease.

| Command/check | Result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; unchanged pinned development dependency tree. |
| `npm test` | Exit 0; 6,179 BrightScript assertions in 36 runs plus 142 cinema-policy assertions = **6,321**. Separate 56 Node test cases, 29 MP4 checks and 50 playlist assertions passed. |
| `npm run build` | Exit 0 after correcting two local variable/function-name collisions in the new coordinator code. No assertion was weakened. |
| `python scripts/verify-package.py` | Exit 0; 207 members, 52 XML components, 273 root/3 relative script references, 164 interface implementations. |
| Focused final coordinator regression | 417 assertions passed after the compiler-only local rename. |
| Independent review | Corrected new-session/exit clearing of measured-HD identities and a sliding refresh loop under sixteen slow providers. Final native-player suite independently passed 418 assertions. |
| `npm audit --json` | Exit 1; unchanged 9 development dependency entries from two underlying advisories (7 high, 2 moderate, 0 critical). Node dependencies are excluded from the install ZIP. |

The new regressions execute the real SourceSelectionTask worker with policy/source-memory stores; resolver/result/retry/native handoff and English-progress callbacks; and coordinator/screen entry, freshness, ranking and manual handoff boundaries. Coverage includes duplicate/host aliases, IPv6, exact-URL exclusions, bounded pools, retained HD after failed UHD, quality deferral without failure-memory writes, accepted-playback protection, stale callbacks, long-session returns, live-request preservation and a sixteen-provider/45-second deterministic schedule that must reach selection after one freshness sweep.

A native counter boundary also rejected real boxed `roInt` values: the provider UHD count now accepts bounded native integer wrappers and rejects non-integers, with production callback coverage. Effective quality/comparison modes are exposed as booleans in safe diagnostics.

Host diversity means distinct delivery hostnames, not independent infrastructure. The initial automatic pool still permits at most three UHD candidates when lower-quality fallback exists. A five-minute result-age budget is not knowledge of every provider's signed-link TTL. Native decoder/transport behavior and full-film reliability remain outside interpreter proof.

### Source and native checks during this investigation

Strict-UHD private tests for two movie IDs completed provider work without starting a compatible source in the observed window. These are failures to obtain usable UHD from that configuration, not proof of universal title unavailability or a Wi-Fi diagnosis. A PC-inspected public free-provider candidate contained a cropped 3840x1596 HEVC file. Its PC-resolved URL received HTTP 403 during native header acquisition and timed out before playback; no English/native-UHD success is claimed. A subsequent native Flix provider lookup returned 13 media candidates and attempted six without observed playing samples. Header requests included HTTP 403 and 206; some inspected files were 3840 pixels wide. Native errors/timeouts still prevented playback. This tests the automatic pool, not only the originally selected 14.02 GB file: the full-load worker did not use the private warm-task filter. The pre-counter-fix diagnostic package's zero UHD count was invalid evidence and is excluded. Detailed timing and package provenance are recorded separately in the release hardware report.

The user's saved normal preference remains 4K first with 1080p fallback, Compare providers and source recovery. Temporary diagnostic packages change only test startup/provider selection, do not install add-ons or write viewing history, and must be replaced with the exact successful CI package before completion. Private media URLs, proxy headers and temporary test data remain excluded from source, package and public reports.

A current primary-source review found no proven unlimited free UHD upgrade. Some aggregators repeat HDHub's underlying hosts. TorBox Essential is a $3/month candidate with a maintained connector, within the user's $5 ceiling; its official hosted Stremio add-on was disabled. No subscription, account authentication or payment was performed, and no account-backed native playback is certified. See [optional sources](FREE-SOURCES.md).

---

# Release validation — 0.5.26

Prepared on 2026-10-17 from default-branch commit `766701d9cfc6d9bc6a61f093591cc2ba382e9acf`, with the preceding 0.5.25 candidate and further production-path repairs. This remains an experimental prerelease.

| Command/check | Fresh result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; 207 installed, 208 audited; lifecycle scripts disabled. |
| `npm test` | Exit 0 after final runtime edits; 5,962 BrightScript assertions in 36 interpreter runs plus 142 cinema-policy assertions = **6,104**. Separate Node suites: 56 passing test cases; MP4 metadata: 29 checks; playlist handling: 50 assertions. |
| `npm run build` | Exit 0; compiled 0.5.26 developer-install ZIP. |
| `python scripts/verify-package.py` | Exit 0; 207 members, 52 XML components, 273 root/3 relative script references and 164 implemented interfaces. Integrity, manifest, paths, references and exclusions passed. |
| Secret/content and license review | Changed-source review passed; no credentials, private manifests or startup harness code added. MIT/upstream NOTICE, third-party licenses and Open Sans OFL retained. Final local ZIP review also passed: all 180 UTF-8-decodable members scanned without secret candidates, development files or media payloads; license files matched reviewed source. |
| `git diff --check` | Passed. |
| `npm audit --json` | Exit 1; unchanged 9 development dependency entries from two underlying advisories (7 high, 2 moderate, 0 critical). Node dependencies are excluded from the install ZIP. |

The completed-provider regression executes PrepareSourceRecovery, re-entry, cancellation and actual coordinator result delivery. Before the repair, eight checks failed: no fresh requests, stale ownership/pending state and old results retained. The fixed path preserves pending transfers, accepted resume, exclusions and the two-worker budget. Source-memory regressions execute production queue, write worker, RegistryIO and result callbacks with Write/Flush refusal, held/stale/duplicate results, launch failure, newest-per-file coalescing and bounded retries. Failed data stays pending in memory; permanent registry refusal or process termination can still prevent durability. Language regressions include foreign-only labels with English in a title and labels split across different fields; hints do not replace native track checks.

### Native English and seek regression

An ordinary-English private HLS control removed the diagnostic-language bypass while retaining no-history safeguards. Of 47 playing samples, the first waited for advancing audio; the remaining 46 passed the production English guard. Fresh native metadata reported 3840 x 2160 SDR HEVC/AAC and unmuted playback, and the sample finished. Pause/resume succeeded. Relative voice-transport seeks returned error.generic, prompting a further repair: numeric wrappers and 64-bit positions must be accepted, with safe duration/offset/target bounds. Production MainScene callback tests reproduced 20 failures before that repair; all 151 voice assertions then passed. A subsequent private harness reproduced rejection of the public MP4, automatically reached attempt 2 using the pinned public HLS control, and reported English with native 3840 x 2160 HEVC/AAC. The repaired transport returned success for pause, resume, forward seek and backward seek. Native instrumentation confirmed the handler associative array stores position/duration as `roFloat`, which the previous admission check rejected. The harness changes only startup, diagnostic test configuration and scalar type logging; no-history safeguards remain. Automatic native-error fallback was exercised, while diagnostic exclusions mean this is not a hardware test of the 45-second frozen-progress watchdog or periodic resume persistence. A first fallback experiment used a local HTTP candidate that the ordinary HTTPS candidate filter correctly omitted; that invalid test setup is excluded from recovery evidence. This exercises native language metadata and advancing media clocks, not acoustic language recognition or audible surround. The control playlist itself declares English.

### Bounded physical evidence from the 0.5.25 player

A private test harness used the exact CI 0.5.25 package with only `source/main.brs` changed to start the existing public control after normal app startup. That test package is not the release ZIP. The Apple HLS control reached native `finished`; 38 playing samples covered position 21.398 to 97.075 over 76.109 seconds. Every sampled audio/video timestamp advanced. Fresh native segment metadata reported 3840 x 2160 SDR with HEVC/AAC. The source-scoped event trace contained no post-start buffering or underrun, and memory level remained normal. The native connection estimate at stream selection was 34,012,160 bits/second; it is not a continuous host speed measurement.

A separate private harness starting the public Microsoft HEVC/AAC direct fragmented-MP4 control obtained no playing samples and logged native error -5 (internal 3), although a PC HEAD request returned HTTP 200. A bounded 1 MiB header inspection found clear fragmented MP4 with a `hev1` sample entry, HEVC Main 8-bit level 5.0 and AAC stereo. This is a failed control, not evidence that MP4/HEVC is universally unsupported: [Roku lists MP4 HEVC/AAC support](https://developer.roku.com/dev/docs/media). Fragment layout and `hev1` are observed differences, not a proven cause. [Microsoft identifies the sample as clear content](https://learn.microsoft.com/en-us/playready/advanced/testcontent/playready-3x-test-content#hevc-8-bit-video-protected-audio-clear); the hostname alone is not DRM evidence.

These control paths intentionally bypass ordinary English-language authorization and exclude automatic recovery/history writes. They do not prove English movie selection, audible sound, surround, HDR, a long MKV, real-source recovery, full-film endurance or the exact unmodified 0.5.26 package. Only fresh native segment data supports the UHD observation; HDMI output and source labels do not. The normal CI package must replace the temporary harness after testing. Publish the exact tested CI artifact unchanged with checksum and provenance, and record further device evidence separately with its precise scope.

---

# Historical 0.5.25 candidate validation

Prepared on 2026-10-17 from latest default-branch commit `766701d9cfc6d9bc6a61f093591cc2ba382e9acf`. The software verification below passed. This remains an experimental prerelease. The exact CI artifact was subsequently installed: the installer reported matching size and MD5, Install Success, and runtime status version 0.5.25. Passive network diagnostics returned bounded facts. An attempted developer-debugger control launch did not yield a successful playback test and made the status service unresponsive; that debugging attempt is excluded from playback evidence. It does not establish a stream failure. No playback-speed, audible-surround or full-film proof was obtained.

| Command/check | Fresh result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; 207 packages installed, 208 audited; dependency lifecycle scripts disabled. |
| `npm test` | Exit 0; 5,778 BrightScript assertions in 35 interpreter runs plus 129 cinema-policy assertions = **5,907**. Separate Node suites: 56 passing test cases; MP4 metadata: 29 checks; playlist handling: 50 assertions. Native-interface/static checks passed. |
| `npm run build` | Exit 0; compiled version 0.5.25 developer-install ZIP. |
| `python scripts/verify-package.py` | Exit 0; 207 members, 52 XML components, 273 root/3 relative script references and 164 implemented interface functions. Integrity, manifest, paths, references and development-file exclusion passed. |
| Secret/content and license review | PASS; reviewed changed public source and 171 text members of the final local ZIP, with synthetic fixtures classified separately. No credential/configured-URL candidates or bundled movie/audio payloads found. MIT/upstream NOTICE, third-party licenses and Open Sans OFL preserved. |
| `git diff --check` | Passed. |
| `npm audit --json` | Exit 1; unchanged 9 development dependency entries from 2 underlying advisories (7 high, 2 moderate, 0 critical). Node dependencies are excluded from the Roku ZIP; see DEVELOPMENT.md. |

New regressions execute production audio/state callbacks and checkpoint/store boundaries. They check one facts pass per event, preserved provisional sound/rendered acceptance/rejection messages, dirty checkpoint acknowledgement, failed clocks, bounded scalar metrics and unchanged skip guards. The new playing-state progress suite covers eligible 45-second stalls through the existing recovery/persistence path, normal movement, pause/seek/discontinuity, stale timer/source events, callback gaps, disabled recovery and live/diagnostic/startup exclusions. Native diagnostic tests cover stale source/node/generation events, distinct event/current snapshots, bounded trace retention, source-correlated duration, malformed/missing size facts and exact multi-gigabyte parsing. Passive network tests cover cache reuse including failures, reset/nonmonotonic counters, type changes, numeric bounds, private-field exclusion and caller-mutation isolation. The totals above include the new progress, network and file-facts runners in the ordinary npm chain. Focused regression work also caught and corrected single-precision large-file parsing and stale prior-source duration attribution before the full passing run.

## Existing-device evidence collected before this patch

Installed 0.5.24 was observed read-only during an existing movie. Three native-reported underruns were recorded. A later 22-sample window spanning 44.7 seconds retained `state=playing` while the native position and both audio/video timestamps stayed unchanged, on the same source attempt. That is evidence of stalled native progress without a reported buffering state, which the older buffering-state watchdog alone could not detect. Current measured host throughput remained unavailable; a raw native stream bitrate is not a download-speed measurement. These observations do not identify a provider/Wi-Fi/app cause or prove a physical improvement from 0.5.25, audible surround or sustained native UHD. No competing speed-test download, live setting change or replacement source was used to generate this evidence.

Publication must promote the exact successful CI ZIP unchanged, with its SHA-256, package-check.json and artifact-provenance.json, then compare the public asset byte-for-byte. Local and CI ZIP hashes may differ because of build metadata. Physical verification of the new event context/duration, checkpoint timing, normal controls, actual audio route and long-film endurance remains required. All earlier hardware results below retain their original version and scope.

---

# Historical 0.5.24 validation

Validated in software on 2026-10-17, starting from default-branch commit `146141c87217811d57a9f2e05fc8b7429cc043cd`. This remains an experimental prerelease. Read-only observations of an already-playing 0.5.23 stream informed the diagnosis; 0.5.24 was not installed during that movie.

| Command/check | Fresh result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; 207 packages installed, 208 audited. |
| `npm test` | Exit 0; 5,329 BrightScript assertions in 32 interpreter runs plus 129 cinema-policy assertions = **5,458**. Separate Node suites: 56 passing test cases. MP4 metadata: 29 checks; playlist handling: 50 assertions. Remaining native-interface/static checks passed. |
| `npm run build` | Exit 0; compiled version 0.5.24 developer-install ZIP. |
| `python scripts/verify-package.py` | Exit 0; 205 members, 52 XML components, 271 root/3 relative script references, 164 implemented interface functions. Integrity, manifest, references and development-file exclusion passed. |
| Secret/content and license review | PASS for changed public source and final local ZIP; intentional regression fixtures classified separately. No personal credentials or signed media URLs found. MIT/upstream NOTICE, third-party licenses and Open Sans OFL preserved. |
| `git diff --check` | Passed. |
| `npm audit --json` | Exit 1; unchanged 9 development dependency entries from 2 underlying advisories (7 high, 2 moderate, 0 critical). These dependencies are excluded from the Roku ZIP; see DEVELOPMENT.md. |

Repeated-underrun regressions execute production native-state/status callbacks, timer recovery, accepted-progress persistence and exhausted-pool discovery. They cover both native callback orders, duplicate events, pause/seek/startup exclusions, disabled recovery, live/diagnostic playback, stale timers, rolling-window clipping and the 32-episode bound. Delivery regressions execute the actual observer and status serializer with stale source/generation/node events, missing/malformed native fields and private URL fixtures. Home/Discover tests cover required current-year extras, unchanged request limits, thirty-minute re-entry refresh, failure retention, focus cancellation and selection bounds.

The initial full test run exposed a next-episode test-loader dependency missing the new production buffering helper. The loader now includes the actual helper; the full chain was rerun successfully without weakening assertions.

The observed 0.5.23 stream resumed after short buffering episodes and had inspected 3840 x 2160 HEVC file headers, English track metadata and E-AC3. Roku did not report current decoded segment dimensions. Neither those facts nor the reported HDMI mode proves sustained UHD, audible English/surround or the cause of buffering. No host throughput measurement was available, and no competing download, source change or live setting change was used. The new delivery estimate is native information recorded at stream selection, not a continuous speed test or a bandwidth increase.

Publication promotes the exact successful CI ZIP unchanged, with checksum, package-check.json and artifact-provenance.json; the public asset is then compared byte-for-byte. Local and CI ZIP hashes can differ because of build-platform metadata. Physical checks of the new native event context, buffering recovery, remote responsiveness, audio route, HDR/UHD and long-film endurance remain required. A catalog listing does not guarantee a playable source or current release availability.

---

# Historical 0.5.23 validation

Validated in software on 2026-10-17, starting from latest default-branch commit `1a7d351`. This remains an experimental prerelease. Existing public provider responses were inspected separately; these checks do not establish native playback, audible English/surround or sustained UHD on the Roku.

| Command/check | Fresh result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; 207 packages installed, 208 audited. |
| `npm test` | Exit 0; 5,177 BrightScript assertions in 31 interpreter runs plus 129 cinema-policy assertions = **5,306**. Separate Node suites: 56 passing test cases. MP4 metadata: 29 checks; playlist handling: 50 assertions. Remaining native-interface/static checks passed. |
| `npm run build` | Exit 0; compiled version 0.5.23 developer-install ZIP. |
| `python scripts/verify-package.py` | Exit 0; 203 members, 52 XML components, 269 root/3 relative script references, 164 implemented interface functions. Integrity, manifest, references and development-file exclusion passed. |
| Secret/content and license review | PASS for current public files and built ZIP; matches reviewed as synthetic test fixtures. No private credentials or signed media URLs found. MIT/upstream NOTICE, third-party licenses and Open Sans OFL preserved. |
| `git diff --check` | Passed. |
| `npm audit --json` | Exit 1; unchanged 9 development dependency entries from 2 underlying advisories (7 high, 2 moderate, 0 critical). These dependencies are excluded from the Roku ZIP; see DEVELOPMENT.md. |

New executable regressions cover provider branding versus actual resolution hints, download-only and non-English-only filtering, bounded automatic UHD/HD pools, delayed UHD within the grace period, stale ranking results, worker-produced UHD counts, recent-failure cooldown and explicit fresh retry. Native resolver tests execute the production callback with injected file/transport boundaries for opaque MKV detection, malformed ranges, cleanup and preserved playable URLs after inspection failure. Existing account isolation, durable outbox, registry failure, checkpoint, source recovery, subtitle, voice and next-episode suites remain in the full test chain.

The automatic pool is six candidates, with at most three UHD candidates when eligible fallback exists. This bounds each pool, not total startup time: native checks, network timeouts and the existing two bounded discovery rounds still take time. Ten-minute temporary-failure suppression requires a stable file fingerprint; opaque URLs without one retain only in-session exact-URL exclusion. Source labels and inspected dimensions remain distinct from native decoded video evidence. Unknown audio language remains subject to the English verification guard.

Publication promotes the exact successful CI ZIP unchanged, with its checksum, package-check.json and artifact-provenance.json. The public ZIP is downloaded and compared against that artifact. The local build is not substituted. Optional public providers are documented in [Free sources](FREE-SOURCES.md), without silent installation, bundled credentials or promises of every title, permanent uptime or universal 4K.

Physical upgrade, remote responsiveness, audible English/projector/surround output, full-film endurance, HDR and sustained native UHD still require device checks for this version. Previous native observations below apply only to their named versions.

---

# Historical 0.5.22 validation

Validated in software on 2026-10-15, starting from latest default-branch commit `bcd32111d9b0996b35285b1a684513d88f66b0c1`. This remains an experimental prerelease. No physical Roku, authenticated Stremio account, personal credential or movie stream was accessed for this update. Earlier physical observations below apply to their identified versions only.

| Command/check | Fresh result |
|---|---|
| `npm ci --ignore-scripts` | Exit 0; 207 packages installed, 208 audited. Dependency lifecycle scripts disabled. |
| `npm test` | Exit 0; 5,065 BrightScript assertions in 31 interpreter runs plus 71 cinema-policy assertions = **5,136**. Separate Node suites report 56 test cases, all passing; other native-interface/static checks also passed. |
| `npm run build` | Exit 0; compiled developer-install ZIP. |
| `python scripts/verify-package.py` | Exit 0; version 0.5.22, 203 members, 52 XML components, 269 root/3 relative script references and 164 implemented interface functions. Integrity, manifest, references, interfaces, paths and development-file exclusion passed. |
| `python scripts/release-provenance.py` | Exit 0; records ZIP hash/size, commit and CI identity. Publication uses the successful CI artifact unchanged, not the local ZIP. |
| Secret-pattern/content review | PASS; current public working source, all reachable historical blobs and install ZIP members, with reviewed synthetic fixtures separated. No candidate values printed or credential validation performed. |
| License checks | MIT LICENSE and upstream NOTICE preserved; third-party licenses and Open Sans OFL retained in package. Lawful-use/no-account-bundling wording remains. |
| `npm audit --json` | Exit 1: 9 affected development dependency entries, representing 2 underlying advisories (7 high, 2 moderate, 0 critical). Documented in DEVELOPMENT.md; no incompatible override or downgrade. These Node dependencies are excluded from the Roku ZIP. |

The new account-sync integration suite executes production link-code worker, addon sync worker, Stremio API store, StoreHost forwarders, login/session/logout and result/finished callbacks, Add-ons row building/selection, and Search/Discover source controllers. Deterministic native task, registry, transport, timer, dialog and node boundaries replace actual devices/network. It has 98 assertions covering initial/slow/partial/failed/empty sync, catalog-only manifests, duplicate/stale notifications, catalog refresh at unchanged URLs, delayed A after B login, repeated login/logout/relaunch, local-only onboarding, dirty-save retry and TV consent. Store regressions add configured-instance identity/reload, safe partial adoption and registry refusal coverage. Account pump tests now include failed writes superseded by newer edits and coalescing that must retain the reconciliation gate.

Existing recovery/checkpoint/resource suites remain: distinct A/B/C edits, server acknowledgement/failure and restored outbox, Write/Flush refusal, accepted progress versus failed replacements, periodic checkpoints, oversized decoded files, excessive nesting/fields/subtitles and early-pool exhaustion followed by a working queued-provider candidate. Playback/audio/voice/next-episode/source-memory suites still pass. Static assertions changed only where the intended contract changed, with executable regressions replacing the old assumptions (ordered catalog signatures and safe fixed error messages, for example); failure assertions were not disabled.

Native Task scheduling, real decompression cancellation, audible English or surround, sustained UHD/HDR and full-film stability remain unverified for 0.5.22. Temporary network files can overshoot polling limits. Dirty state cannot guarantee preservation across permanent storage refusal, logout with unsynced changes or power loss before an acknowledged checkpoint. Account snapshots over device limits are reported partial rather than silently complete.

Before stable status, check clean install/upgrade, a real account's received collection, a full movie, consecutive episodes, repeated seeking/navigation, Back during loading, failed/expired-source recovery, repeated-navigation memory, audible stereo and actual AX700 HDMI surround. A label or codec capability flag is not proof of current-file decoded UHD or audible surround.

The release includes the exact successful CI ZIP, SHA-256 text, package-check.json and artifact-provenance.json. The public asset is downloaded and compared byte-for-byte with the CI artifact after publication. See [audit](AUDIT-0.5.22.md), [security review](SECURITY_REVIEW.md) and [installation](INSTALL.md).

---

# Historical 0.5.21 validation

Validated on 2026-10-14. This remains an experimental prerelease. Controlled native checks passed; full-workflow hardware sign-off remains incomplete.

- The full test chain passed **4,927 BrightScript assertions plus 71 cinema policy assertions: 4,998 total**. Separate Node media, transport, mock-provider and setup-server suites also passed; their counts are separate.
- New tests execute production store and controller code against native boundary doubles: held A results/publishers/imports after switching to B; A in flight with distinct B/C edits; failed writes and restart outbox recovery; fresh baseline before explicit retry; independent Write/Flush refusals; cross-section registry budgeting; account add-on configuration/removal/order; public HTTP rejection; oversized decoded response files, long fields, deep JSON and subtitle floods; early-pool discovery recovery; periodic durable checkpoints, seek to zero and old-screen exit isolation.
- CI builds once after tests and verifies the install ZIP: 201 members, 52 XML components, 267 package-root plus 3 relative script references, 159 implemented interface functions, valid inheritance, manifest artwork and licensing, and no development files.
- CI records the exact ZIP hash, commit and run ID in artifact-provenance.json. Publication promotes that artifact directly, with its checksum and package-check.json. The public ZIP must be downloaded and checked against the CI bytes; a local rebuild is not substituted.
- Public working source, reachable Git history and the install ZIP receive secret-pattern/content review. Dummy fixture values are classified separately. This is pattern/content review, not credential validation.
- `npm audit` was rerun: two underlying development-tool advisories affect nine dependency entries (2 moderate, 7 high, 0 critical). No incompatible override is used. Those Node dependencies are excluded from the Roku installation ZIP.

The file-acquisition tests supply decoded native file sizes and scripted events; they do not run the actual Roku HTTP/decompression implementation. Cancellation is best effort and temporary files can overshoot between polling checks. Candidate limits bound serialized application payloads, not every internal/native allocation or aggregate network connection. The registry admission budget is deliberately uncompressed; native storage limits and acknowledgements remain authoritative.

Account saves are optimistic until acknowledged. Failed/uncertain cloud writes remain pending, with explicit retry against a fresh baseline. Restored uncertain writes wait for that retry. Persistent storage/network failures, a full outbox, forced termination before an acknowledged checkpoint, or logout with unsynced edits cannot guarantee preservation of every recent change. Older unowned Stremio caches are ignored; manually configured account providers may need re-importing.

The LAN setup page retains the private-interface, Host/Origin and open-Add-ons protections. A short-lived pairing code/TV confirmation is still a hardening recommendation. This release does not claim that an origin check authenticates every native LAN client.

**Full-workflow sign-off remains incomplete.** Physical use of 0.5.18 exposed a reproducible Back/checkpoint crash: an overlong callFunc resume write exceeded Roku’s native parameter limit, followed by a corrupted function context. The new hotfix replaces that boundary with one record. A production syntax-tree check inspects all 254 callFunc uses and both resume callers; the checkpoint/account tests now execute the real StoreHost forwarding method and record validation. Negative native retry statuses share one total acquisition/backoff deadline. Loading feedback, UHD-over-HD ranking and online-caption opt-in have regression coverage. Stable status requires clean install and upgrade, a full movie, consecutive episode transitions, repeated seeking, Back during loading, failed/expired-source recovery and repeated-navigation memory measurements. Stereo and surround require audible tests on the actual HDMI route. No software assertion count certifies audible English, genuine sustained UHD, HDR, AX700 surround or uninterrupted playback of every provider file.

Use the compiled release ZIP and its SHA-256 file, not GitHub's source archive. See [Changes](../CHANGELOG.md), [Playback](PLAYBACK.md) and [Development](DEVELOPMENT.md) for the repair details and practical limits.

The complete-flow tests also caught a pre-existing time-unit boundary bug. Roku history/Video positions use seconds; Stremio `timeOffset` and `duration` use milliseconds ([official LibraryItemState](https://stremio.github.io/stremio-core/src/stremio_core/types/library/library_item.rs.html)). The account pump now converts outbound packets without mutating the seconds-valued outbox; sync/re-add paths convert incoming wire checkpoints back to native seconds. Regression tests cover a write/pull round trip. Existing incorrectly written cloud progress cannot be reconstructed automatically.

## Controlled device checks on 2026-10-14

The exact 0.5.19 CI ZIP was installed successfully, then a private instrumented copy of its compiled core ran bounded tests on a Streaming Stick+ 3830RW with an Optoma UHD50X route. Instrumentation invoked the production screen stack, timers and component interfaces; isolated guest-registry fixtures were restored/removed afterwards. It was not a remote-key injection or acoustic listening test. The instrumented ZIP was never published.

- Native one-record resume forwarding returned acknowledgement, retained component context, and a fresh LibraryStore recovered the written position.
- Settings, Add-ons and Search each opened/exited twice. Back canceled an active configured-provider request and returned Home; abandoned results did not start playback.
- The UHD HLS control reported HEVC, AAC, native segment **3840×2160 SDR**, unmuted state and advancing audio/video timestamps. This is separate from the reported 2160p HDMI signal.
- Seek, pause and resume worked. The 30-second checkpoint recovered position 16 from a fresh store; Back after subsequent playback recovered position 39 and returned Home without the prior native crash.
- A subsequent lower-resolution HLS control exposed stale 4K segment information retained by Video. Version 0.5.20 now obtains dimensions only from segment events, with software regressions and a repeat native switch check required before completion.
- Short resource samples were about 39.4 MiB during navigation, 53.9 MiB during decoding and 48.1 MiB after cleanup. Different cache/decoder states make these observations insufficient to establish absence of a leak or long-session stability.

The current route reported Stereo with two-channel AAC/MP3/PCM support and no AC3/EAC3 passthrough. Capability flags and timestamp progression do not prove audible output or test an AX700 receiver path. Full-film/endurance, consecutive real episodes, live multi-account switching, clean install without retained configuration, surround/HDR listening/viewing and repeated long navigation remain outside these controlled checks.

The configured movie provider was tested separately in an isolated diagnostic session (no user history/account writes). A 120-second 4K-only window did not produce accepted English/stereo playback: several UHD MKV headers were present, but inspected audio incompatibility or unconfirmed native audio rejected candidates. A normal quality/fallback window reached an English AAC/AVC MKV with **1920×1080 header dimensions**, unmuted state and advancing audio/video samples on attempt 21. This demonstrates a compatible HD fallback for that title, not reliable instant UHD movie playback. Untagged language stays blocked rather than being declared English from a filename. Diagnostic mode suppressed further discovery after the initial candidate pool; these windows were bounded observations, not proof that every provider candidate was exhausted.

## Final 0.5.20 native repeat

The CI core at commit `82e4d301557f749c9c0853e15e71332307d7de8f` (run `38640266683`) passed a controlled instrumented repeat on the same Stick. The final release ZIP is 871,486 bytes, SHA-256 `7b188eb0d9717e2ac58bdcd3d5bc2a6d1226a9c0d0013c2fcb97b1f9eecce2a8`.

| Check | Observed result |
| --- | --- |
| Native resume record/context/persistence | Acknowledged; fresh-store reload recovered position 7 |
| UHD control | Fresh native 3840×2160 SDR segment; HEVC and AAC; advancing A/V samples |
| Seek and pause | Position 20.362; paused position remained 20.362 |
| Actual resume command | Continued to 60.416, rather than restarting at zero |
| Periodic checkpoint and Back | Fresh-store positions 38 and 60; Back returned Home |
| Subsequent fixed HD control | Fresh 1920×1080 SDR; AVC/AAC, unmuted and advancing A/V; no inherited UHD claim |
| Navigation/source cancellation | Twelve enter/exit transitions and Back during a live provider request passed in the companion native run |
| Teardown | Both playback exits returned Home; original library restored and isolated fixture data removed; no native runtime error in the final run log |

The first pause test incorrectly used `play`, which restarts the control; it was corrected to Roku's documented `resume` command and repeated before the continuation claim above ([Video control](https://developer.roku.com/dev/docs/video)). An older Bip Bop stereo fixture did not establish advancing video/audio acceptance in a repeat, so the final switch used fixed UHD and HD renditions from the same [public Apple advanced HLS example](https://developer.apple.com/streaming/examples/). Those are control observations, not a guarantee for arbitrary movies or audible English.

A later native resource sample reached 184.5 MiB during UHD playback (about 17.9 MiB anonymous and 166.4 MiB file-backed); after both controls exited it fell to 51.3 MiB (18.4 MiB anonymous, 32.8 MiB file-backed). This records the larger measured peak as well as cleanup. It is not a memory-limit or long-session leak certification. No private URLs, account configuration, identifiers or raw logs are published.

## Catalog and episode regression repair — 0.5.21

A private native navigation run reproduced Family Guy search succeeding while Details and Episodes each remained pending after 45-second windows. The original Discover catalog remained pending at 20 seconds and returned 48 movies by the 45-second observation. A later instrumented candidate exposed a separate native execution timeout while constructing The Simpsons episode grid in one render callback. This was a real native failure, not inferred from a test count.

The repair uses byte scanning for the JSON depth guard, reuses complete fetched metadata, groups episodes in one pass with native sorting, and creates or refreshes nodes in timer batches (at most 24 cards and a 12 ms soft callback budget). A single native operation can exceed that soft budget; it is not a hard real-time promise. All episodes remain in the final grid. Guest fixture checks restored the original in-memory library and deleted their separate registry section. No provider playback was started by these navigation checks.

The first successful batched native run observed 48 Discover movies, 50 shows, 50 Comedy shows and a successful retry in approximately one-second sampling windows. Search found Family Guy in about one second, full metadata contained 511 episodes, and the completed grid contained 511 cards across 25 seasons in about 3.3 seconds. The Simpsons completed 880 cards across 39 seasons in about 8.5 seconds without the previous callback timeout. Back canceled a pending episode lookup and returned Home. These are bounded observations on one Stick/network with built-in metadata catalogs, not guaranteed timings for every provider.

A failed private diagnostic installation also reset that device's local application data. The normal release does not include private configuration. Deleting the development app or a failed installation may require the owner to re-import their provider and reselect preferences. Never use unpublished diagnostic ZIPs as the public installation package. Native final-package startup and the exact CI artifact promotion are recorded separately before publication.

The final native navigation repeat loaded Family Guy's 511 cards in 3.318 seconds and The Simpsons' 880 cards in 7.544 seconds. Reopening the completed Family Guy snapshot retained all 511 cards and returned from the open operation in 219 ms; badge refresh continued in bounded batches. Back during a card build returned to Details, and Back during a metadata request returned Home with no remaining episode task. Final-session native logs contained no runtime errors; the test library was restored and fixture data removed. Timings include sampling/dispatch overhead and are observations, not service guarantees. These checks invoked production component interfaces, rather than injecting physical remote keys, and did not test audible playback or a complete film.

## Published 0.5.21 package

Code commit `ade0953838348093ac30a616a6803c214114d3f0` passed [CI run 38662711746](https://github.com/kaiuribess/rokumio-4k-personal/actions/runs/38662711746). Its exact ZIP is **873,164 bytes**, SHA-256 `07d1c1742119986724683c7424296790b0a1f81a4f6fbf63a8fdeace9506fb00`. All 201 member contents matched the locally instrumented production-core baseline after line-ending normalization (28 members differed only by CRLF/LF). The four published assets were downloaded independently and matched CI bytes. Source/history/package pattern review left zero unreviewed findings.

The exact normal CI ZIP installed successfully on the device, reported version 0.5.21, and started without native runtime errors. Private navigation instrumentation was removed and the app was left idle. The failed diagnostic installation had reset local profile/provider configuration; a local profile and the prior surround preference were restored, but the configured stream provider still needed a private re-import. Navigation checks therefore do not constitute a fresh test of that provider's playback. Roku reported 5.1 surround output at the final check; that is not audible surround certification.
