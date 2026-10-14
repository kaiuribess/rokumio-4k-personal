# Release validation — 0.5.12

Validated from the public source snapshot on 2026-10-14:

- Clean locked dependency installation: `npm ci --ignore-scripts` passed.
- Full `npm test` chain passed: **3,945 BrightScript harness assertions plus 69 cinema stream policy assertions (4,014 total)**. Separate Node media/transport/mock suites also passed; their checks are not folded into that count.
- **67 next-episode assertions** are included in the total and exercise production policy, native finish callback, countdown controller, watch-state saving and MainScene routing.
- `npm run build` passed with no compilation errors.
- `python scripts/verify-package.py` passed ZIP integrity, manifest, component inheritance and packaged reference checks. The build has **48 XML components and 217 packaged script references**.
- Private workstation data, account configuration and test logs were excluded from the published snapshot. API-looking strings in test fixtures are synthetic.

These checks run on a computer using simulated native device boundaries. After publication, the release ZIP was installed on the reference Streaming Stick+ 3830RW: the installer accepted 769,327 bytes and reported success, and a read-only active-app query independently confirmed version 0.5.12 running. **The next-episode transition has not been physically playback-tested.** Installation and software checks do not prove audible English sound, 4K decoding, surround/HDR, network throughput or uninterrupted full episodes on every source.

The release assets include the compiled install ZIP and its SHA-256 file. Verify the ZIP hash before installation; the repository's source archive is not directly installable. Runtime fixes and dependency advisory limits are described in [PLAYBACK.md](PLAYBACK.md) and [DEVELOPMENT.md](DEVELOPMENT.md).
