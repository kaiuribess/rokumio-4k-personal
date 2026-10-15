# Release validation — 0.5.21

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
