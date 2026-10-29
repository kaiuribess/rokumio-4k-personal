# Sports feature validation — 2026-10-29

Continued draft PR #9 on `feature/live-sports` from `f8dbbc41d01947674016076e91fd152c20f72b86`, preserving its schedule/publisher and manual next-episode work. At the final pre-commit fetch, main remained `e0f128e518fda22e9f2d3c44cd2b28ae951376c7`. Package: **0.6.0 feature preview**, not released or hardware-certified.

## Before / after evidence

| Boundary | Previous limitation | Change and regression evidence |
| --- | --- | --- |
| Discovery → stream lookup | The main Sports path used ESPN IDs. Unrelated providers cannot resolve them merely by supporting TV. | Sports defaults to installed provider catalogs. Production AddonsStore → CatalogStore → Discover → source resolution tests retain opaque event ID/type and configured address. Live discovery is pinned to that catalog owner; another broad TV provider cannot silently substitute a different game. |
| Catalog tile → sources | The ordinary Details path adds a metadata request before a live event's streams. | Explicit live catalog selections open the existing source picker directly. Other catalogs still use Details. Hidden/stale selection callbacks are ignored. |
| Native audio gate | Language-less live AAC fails the movie-oriented English requirement; sampled real HLS had no language tags. | A visible live-only option permits unlabelled audio after compatible native codec and advancing audio/video samples, while `englishVerified` remains false. Known foreign/descriptive/unsupported tracks, strict-live mode and movies retain their checks. Production acceptance and continuity callbacks are tested. |
| Media handoff/freshness | Extensionless playlists could lack a format hint; long-lived source caches can retain expired live links. | Bounded signature-checked HLS/DASH recognition, queries/per-item headers retained, 30-second live freshness on interaction. No background refresh interrupts accepted playback. |
| Live lifecycle | Movie resume, watch writes and next-episode behavior must not apply to live events. | Live content starts near the edge, skips resume/account checkpoints/source memory/next episode, and retains bounded same-event recovery and Back. Existing movie and manual next-episode regression suites pass. |

## Local software validation

| Command / check | Result |
| --- | --- |
| `npm ci --ignore-scripts` | Passed; 207 packages. Two existing high-severity development dependency entries remain. |
| `npm test` | Passed: 6,556 assertions across 37 standard harness invocations, 142 cinema-policy assertions, 50 media-playlist assertions, 66 Node test cases, plus component/static contract checks. Zero reported failures. |
| `node tests/sports.test.js` (included above) | 85 assertions: production worker callbacks and provider-native registration/catalog/source/resolve boundaries, composite IDs, header/query retention and browser-only diagnostics. |
| `node tests/discover-ui.test.js` (included above) | 76 assertions, including exact-catalog live routing, other-catalog isolation and hidden stale selections. |
| `node tests/source-prefetch.test.js` (included above) | 425 assertions, including owner-pinned live requests, 30-second expiry and no refresh while suspended. |
| `node tests/audio-recovery.test.js` (included above) | 137 assertions, including live acceptance without falsely certifying English, continuity, foreign rejection, and suppression of live resume/account/source-memory writes. |
| Native playback boundary suite (included above) | 437 assertions, including extensionless playlists through production resolver/native handoff; HTML, oversized HTTP 200 movie responses and unsupported media stay rejected. Device I/O is mocked. |
| `node tests/next-episode.test.js` (included above) | 98 assertions: production key callback, guarded timer, metadata policy, save and Scene routing; native boundaries mocked. |
| `node --test tools/sports-addon/build.test.js` (included above) | 10 cases, including actual localhost requests for generated manifest/catalog/meta/stream files. No fixture is presented as real sports media. |
| `python tests/probe-live-providers.test.py` | 5 offline cases: public destinations, headers, redirects, media classification and secret-safe errors. Required by CI. |
| `npm run build` | Passed without compiler errors. |
| `python scripts/verify-package.py` | Passed: 212 ZIP members, 54 XML components, 281 script references, 168 implemented declared interface functions; development files excluded. |
| Credential-pattern scan of repository and ZIP | Zero findings for private-key headers, GitHub tokens, JWTs and TorBox-key-shaped context in scanned files. A bounded pattern check, not proof arbitrary secrets cannot exist. No personal credential files accessed. |
| `git diff --check` | Passed. |
| Attribution/package review | Upstream MIT, NOTICE and third-party licenses retained. No upstream resolver code copied or npm dependency added. Research-only PyAV is absent from the app/ZIP. |

Use the install ZIP and its **SHA-256 from the same successful CI artifact** linked in PR #9. CI runs install/tests/build/package verification, then creates `artifact-provenance.json` and a checksum before uploading `rokumio-4k-personal`. A local rebuild is not the publication identity. This PR does not publish a Release, deploy a service, merge or install on Roku.

## Real provider and media evidence

[Sanitized October 29 evidence](research/live-providers-2026-10-29.json) records public manifest fields, event names/ID hashes, origins, statuses and media facts. Temporary media URLs, request header values and video samples are excluded.

- Nuvio and all three supplied Highfly manifests returned **403** from this PC/network. No challenge bypass attempted. Source/issues/community reports were inspected as leads, not playback proof.
- StremVerse's exact Crimson free catalog route returned **107 events**. Four initial stream responses included empty, browser-only and direct-media results. Original composite IDs reached its stream endpoint unchanged.
- A Copa del Rey event's HTTPS HLS with query and provider-supplied headers delivered three segments and decoded **300 video / 517 audio frames at 512×288 H.264/AAC**. A separate visual check showed an actual football match. Two short checks roughly ten minutes apart succeeded; they were not one sustained viewing test.
- HB Koge vs Barcelona delivered three segments and decoded **225 video / 387 audio frames at 1920×1080 H.264/AAC**. A later fresh request returned **403**. Both sampled audio streams lacked language tags; no audible English or surround claim follows.
- Other sources failed with 403/network errors. Public HTTP sources are not admitted by the HTTPS integration or repeatable probe. Browser-only promotional entries are not handed to the player.
- StreamFree listed source **embed pages**, which cannot be handed to native Video. No new resolver, paid proxy or permanent PC service introduced.

Reproduce bounded current checks with `python scripts/probe-live-providers.py --event-index 3 --event-index 9 --output verification/live-providers.json`. Indices select the current catalog and will change. Optional `--decode` needs a separate PyAV installation (tested with 19.0.2). The probe does not install providers, authenticate, solve challenges or process encrypted playlists. Public reachability does not establish broadcast rights; no provider is bundled or silently installed.

Earlier [schedule probe evidence](research/sports-probe-2026-10-29.json) remains dated evidence: 13 selected scoreboard responses were HTTP 200, boxing was HTTP 400 and excluded, a Red Bull HLS prefix was reachable, and Streamed.pk announced closure. These do not establish broad live-event video coverage.

## Known development advisories

The existing two high-severity affected dependency entries are `decode-uri-component` and its caller `source-map-resolve`. These are development-tool findings, not two independent installed-Roku vulnerabilities. This feature does not change the dependency graph; those files are excluded from the ZIP. See [Development](DEVELOPMENT.md). No clean audit is claimed.

## Physical acceptance still required

No Sports playback, audible output, UI layout or remote behavior was tested on a physical Roku in this phase. PC decoding and production callback tests are separate evidence.

1. Install the exact CI ZIP yourself; verify upgrade retains movies, shows, TorBox and add-ons. Explicitly import only a provider you are authorized to use.
2. Open Sports → provider Live Events → event → source. Test Back during catalog/source loading and Live versus Recorded mode. Listings alone must not imply available video.
3. Watch long enough to exercise playlist renewal, bitrate changes and expired links. Check native decoded resolution and listen through the actual projector/surround route. Test unlabelled-live and strict-English modes.
4. Exercise failed primary/working same-event alternate, fresh-link recovery and Back during recovery. Verify bounded attempts, no cross-event switch and no late result interrupting accepted playback.
5. Exit/reopen live playback: it should start near the live edge without movie resume, Continue Watching pollution or next-episode behavior.
6. Recheck a movie and series. Pause an accepted episode and press Down when “Down: next episode now” appears; verify progress saves and native seeking/captions still work. Test automatic next episode separately.

The direct-media path now has real PC decode evidence. **Stable delivery, authorized broad league coverage and sustained native Roku playback remain unresolved acceptance gates.** The later 403 is a concrete provider limitation. [Sports setup and research](SPORTS.md) explains the opt-in path and alternatives examined.
