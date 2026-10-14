# Release validation — 0.5.14

Validated on 2026-10-14:

- The existing locked dependency installation is retained. Independent GitHub CI installs from the lockfile with `npm ci --ignore-scripts` before tests/build.
- The full `npm test` chain passed: **4,198 BrightScript harness assertions plus 69 cinema stream policy assertions (4,267 total)**. Separate Node media/transport/mock suites also passed; their checks are not folded into that count.
- **75 Home assertions** exercise the actual preview worker and rendering coordinator: 12-row/24-title caps, eight missing-manifest attempts, bounded catalog requests, malformed metadata, preserved artwork shapes, hidden-screen staging, featured-image cancellation, shortcut focus and exact full-catalog routing.
- **34 playback-stability assertions** cover current-operation timer delays, startup/deadline ownership, last measured terminal position, explicit seek-to-zero behavior and deferred audio-repair timing. Existing native playback and watchdog suites also reproduce fixed timer/stopped/early-end cases.
- **19 preference-policy assertions**, plus store/controller/handoff tests, cover safe defaults, persistence, explicit overrides, quality selection and disabled recovery/next-episode behavior.
- **76 next-episode assertions** are included in the total and exercise production policy, native finish callback, countdown controller, watch-state saving, old timer events and MainScene routing.
- **81 add-on/audio setup assertions** are included in the total: manifest roles/error categories, private-data exclusion, progressive results/focus, cancellation, stale results/deadlines, worker request scope, explicit equipment choices and honest capability reports.
- `npm run build` passed with no compilation errors.
- `python scripts/verify-package.py` passed ZIP integrity, manifest, component inheritance and packaged reference checks. The build has **52 XML components and 244 packaged script references**.
- Illustrative FHD authoring previews of compact and expanded Home were reviewed for spacing and clipping. These reconstruct source coordinates with synthetic data, not native SceneGraph rendering.
- Public source/history and compiled ZIP were scanned for secret-looking data. Private workstation configuration/logs are excluded; retained credential-looking test fixtures are synthetic. This is pattern/content review, not credential validation.

These checks run on a computer using simulated native device boundaries. **0.5.14 has not been installed, frame-rate profiled or physically playback-tested.** The previous 0.5.12 ZIP was confirmed running on a Streaming Stick+ 3830RW, but its next-episode transition was not physically playback-tested. That installation does not establish the new Home's rendering or scheduling. Software/package checks do not prove audible English sound, UHD decoding, surround/HDR, throughput or uninterrupted full episodes on every source.

The release assets include the compiled install ZIP and its SHA-256 file. Verify the ZIP hash before installation; the repository's source archive is not directly installable. Runtime fixes and dependency advisory limits are described in [PLAYBACK.md](PLAYBACK.md) and [DEVELOPMENT.md](DEVELOPMENT.md).
