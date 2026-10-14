# Release validation — 0.5.13

Validated on 2026-10-14:

- The existing locked dependency installation is retained. Independent GitHub CI installs from the lockfile with `npm ci --ignore-scripts` before tests/build.
- The full `npm test` chain passed. After a final stale-deadline guard, the affected diagnostic suite was rerun successfully: **4,026 BrightScript harness assertions plus 69 cinema stream policy assertions (4,095 total)**. Separate Node media/transport/mock suites also passed; their checks are not folded into that count.
- **67 next-episode assertions** are included in the total and exercise production policy, native finish callback, countdown controller, watch-state saving and MainScene routing.
- **81 add-on/audio setup assertions** are included in the total: manifest roles/error categories, private-data exclusion, progressive results/focus, cancellation, stale results/deadlines, worker request scope, explicit equipment choices and honest capability reports.
- `npm run build` passed with no compilation errors.
- `python scripts/verify-package.py` passed ZIP integrity, manifest, component inheritance and packaged reference checks. The build has **51 XML components and 233 packaged script references**.
- Illustrative FHD authoring previews of welcome, add-on checks, surround settings and About were reviewed. These are layout reconstructions with synthetic data, not screenshots of native SceneGraph rendering.
- Private workstation data, account configuration and test logs were excluded from the published snapshot. API-looking strings in test fixtures are synthetic.

These checks run on a computer using simulated native device boundaries. **Version 0.5.13 has not been installed or physically tested.** The previous 0.5.12 ZIP was installed on a reference Streaming Stick+ 3830RW, independently confirming that version running, but its next-episode transition was not physically playback-tested. That earlier installation does not establish the new UI's native rendering. Software/package checks do not prove audible English sound, 4K decoding, surround/HDR, network throughput or uninterrupted full episodes on every source.

The release assets include the compiled install ZIP and its SHA-256 file. Verify the ZIP hash before installation; the repository's source archive is not directly installable. Runtime fixes and dependency advisory limits are described in [PLAYBACK.md](PLAYBACK.md) and [DEVELOPMENT.md](DEVELOPMENT.md).
