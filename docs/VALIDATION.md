# Release validation — 0.5.16

Validated on 2026-10-14:

- The existing locked dependency installation is retained. Independent GitHub CI installs from the lockfile with `npm ci --ignore-scripts` before tests/build.
- The full `npm test` chain passed: **4,635 BrightScript harness assertions plus 69 cinema stream policy assertions (4,704 total)**. Separate Node media/transport/mock suites also passed; their checks are not folded into that count.
- **375 source-screen assertions** cover production callbacks including paging through 49/96/97/256 candidates, final candidate playback/full retained retry pool, 48-card page budget, stale navigation, page/focus restoration, provider/filter/refresh changes, manual precedence and Queued/Requesting status.
- **238 source-prefetch/scheduling assertions** cover shared two-slot ownership, cold/warm adoption, original index alignment, preferred/last-working order, priority beyond the first four providers, invalid/missing keys, preserved cache validity, active-transfer non-preemption, suspension/resume, stale results, grace and strict quality changes.
- **75 Home assertions** exercise the actual preview worker and rendering coordinator: 12-row/24-title caps, eight missing-manifest attempts, bounded catalog requests, malformed metadata, preserved artwork shapes, hidden-screen staging, featured-image cancellation, shortcut focus and exact full-catalog routing.
- **34 playback-stability assertions** cover current-operation timer delays, startup/deadline ownership, last measured terminal position, explicit seek-to-zero behavior and deferred audio-repair timing. Existing native playback and watchdog suites also reproduce fixed timer/stopped/early-end cases.
- **36 preference-policy/UI assertions**, plus store/controller tests, cover safe persistence, playback modes, provider selection, subsection Back and old sender rejection. Twelve new store assertions cover opaque keys, malformed values and refused-write retry.
- Five new native-player assertions place recent-provider recording only after the existing English/unmuted/native A/V progress gate; diagnostics and duplicate ticks do not record it.
- **77 next-episode assertions** are included in the total and exercise production policy, native finish callback, countdown controller, watch-state saving, old timer events, preserved comparison policy and MainScene routing.
- **81 add-on/audio setup assertions** are included in the total: manifest roles/error categories, private-data exclusion, progressive results/focus, cancellation, stale results/deadlines, worker request scope, explicit equipment choices and honest capability reports.
- `npm run build` passed with no compilation errors.
- `python scripts/verify-package.py` passed ZIP integrity, manifest, component inheritance and packaged reference checks. The build has **52 XML components and 253 packaged script references**.
- Illustrative FHD authoring previews of compact and expanded Home were reviewed for spacing and clipping. These reconstruct source coordinates with synthetic data, not native SceneGraph rendering.
- Public source/history and compiled ZIP were scanned for secret-looking data. Private workstation configuration/logs are excluded; retained credential-looking test fixtures are synthetic. This is pattern/content review, not credential validation.
- The supported toolchain patches removed the critical Node development advisory; two underlying advisories remain, affecting nine dependency entries. See the scoped dependency audit in DEVELOPMENT.md. Node development dependencies are excluded from the Roku ZIP.

Independent code review inspected paging, stable priority/index mapping, cache validity, native Settings list generations, opaque storage and recent-provider proof timing. Source/controller tests were independently rerun.

These checks run on a computer using simulated native device boundaries. **0.5.16 has not been installed, frame-rate profiled or physically playback-tested.** The previous 0.5.12 ZIP was confirmed running on a Streaming Stick+ 3830RW, but its next-episode transition was not physically playback-tested. That installation does not establish the new screens' rendering or source scheduling. Software/package checks do not prove audible English sound, UHD decoding, surround/HDR, throughput or uninterrupted full episodes on every source.

Start sooner has fewer initial recovery choices than full comparison. Two slow occupied slots can delay later queued providers. Ordinary provider response sizes and total HTTPS/media connections are not bounded by the two-worker scheduler. These are intentional limits, not measured device freezes or memory leaks.

Manual pages cover retained eligible sources; warm prefetch still has its 256-candidate/provider cap. Source labels remain initial quality hints. Preference memory uses native track/progress observations, not acoustic recognition or universal file compatibility.

The release assets include the compiled install ZIP and its SHA-256 file. Verify the ZIP hash before installation; the repository's source archive is not directly installable. Runtime fixes and dependency advisory limits are described in [PLAYBACK.md](PLAYBACK.md) and [DEVELOPMENT.md](DEVELOPMENT.md).
