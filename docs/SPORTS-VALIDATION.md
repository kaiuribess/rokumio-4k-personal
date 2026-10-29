# Sports feature validation — 2026-10-29

Based on default branch commit `e0f128e518fda22e9f2d3c44cd2b28ae951376c7`, fetched before creating `feature/live-sports`. Package version: **0.6.0 feature preview**. This is not a released or hardware-certified build.

## Local software validation

| Command / check | Result |
| --- | --- |
| `npm ci --ignore-scripts` | Passed; 207 packages installed. Existing development dependency advisories described below. |
| `npm test` | Passed. 6,473 assertions across 37 standard harness invocations, 142 cinema-policy assertions, 50 media-playlist assertions, 66 Node test cases, plus component/static contract checks. |
| `node tests/next-episode.test.js` (included above) | 98 assertions: production key callback, guarded timer, metadata policy, save and Scene routing; native boundaries mocked. |
| `node tests/sports.test.js` (included above) | 67 assertions: production worker callbacks, queued date changes, empty/failed/duplicate/stale notifications, response limits, AddonsStore registration and matching, catalog routing, source ranking, direct resolver and expiry. |
| `node --test tools/sports-addon/build.test.js` (included above) | 10 passing cases, including actual localhost HTTP requests for generated manifest/catalog/meta/stream files and refusal to overwrite an output directory. No mock URL is fetched as real media. |
| `npm run build` | Passed with no compiler errors. |
| `python scripts/verify-package.py` | Passed: 212 ZIP members, 54 XML components, 281 resolved script references, 168 implemented declared interface functions; development files excluded. |
| Private literal scan of tracked files and ZIP | Passed, zero matches for the known private key and configured manifests. No credential values printed. |
| `git diff main --check` | Passed. |
| Attribution/package review | Upstream MIT, NOTICE and third-party license files retained. No third-party resolver code copied; no new npm dependency. |

The local ZIP hash is deliberately not the publication identity: CI builds its own ZIP. Use the SHA-256 in the **same CI artifact** as the downloaded install ZIP. The existing workflow runs install/tests/build/package verification and creates `artifact-provenance.json` plus a checksum before upload. Do not substitute a rebuilt ZIP. This PR does not publish a Release, deploy a feed, or install on a live Roku.

## Network evidence

`python scripts/probe-sports.py --media --output verification/sports-provider-probe.json` completed using public endpoints, no account or API key. [Recorded output](research/sports-probe-2026-10-29.json).

- All 13 selected dated scoreboards returned HTTP 200 and arrays. Empty arrays were retained as valid empty schedules; this does not prove full competition coverage.
- The boxing endpoint returned HTTP 400 and is excluded from the league selector.
- One public Red Bull master/variant and bounded segment prefix responded. Manifest codecs/resolutions and MPEG-TS sync were checked; no native decode, audible-English or rights verification occurred. It is not a bundled provider.
- Streamed.pk announced closure and its old API path returned HTML. No resolver bypass was attempted.

## Known development advisories

A fresh `npm audit --json` reported two high-severity affected dependency entries: `decode-uri-component` and its caller `source-map-resolve`. These are existing development dependencies, not two independent installed-Roku vulnerabilities. The dependency graph was not changed by this feature, and these files are excluded from the ZIP. Do not claim a clean audit or force an incompatible transitive override merely to remove the count. See the dated toolchain discussion in [Development](DEVELOPMENT.md).

## Physical acceptance still required

No new Sports playback, UI rendering or remote-key behavior was tested on a physical Roku. Existing movie tests are regression evidence, not sports certification.

Before enabling a default provider:

1. Establish permission for its direct stream delivery and verify the current manifest, stream response and region.
2. On the target Roku, test league/date/status navigation and Back while the schedule or sources are loading.
3. Play an authorized live broadcast long enough to observe playlist renewal and bitrate changes; verify actual native resolution and hear English audio through the current HDMI route.
4. Exercise a failed primary and working alternate, expiry before selection, repeated buffering and Back during recovery. Confirm bounded recovery and that a late result never interrupts accepted playback.
5. Test a paused series episode: Down should request the next known aired episode before credits, save actual progress, retain automatic-next preference and keep seeking/caption controls usable. Verify native Video passes Down to the parent on that Roku OS.
6. Recheck movies, TorBox, saved progress, series autoplay, voice, subtitles and projector/surround preferences after installing the exact CI ZIP.

The unresolved product requirement is broad, reliable, authorized free **video delivery**. Schedules and generated protocol fixtures do not solve broadcaster rights, geo-restrictions, expiring credentials or unavailable games. [Sports research and architecture](SPORTS.md) documents the implemented foundation and operator deployment path.
