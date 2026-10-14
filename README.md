# Crimson Cinema

A native Roku client with a dark red interface for browsing Stremio-compatible catalogs, searching movies and shows, and playing compatible direct streams with the Roku remote. This community derivative adds English audio selection, projector/surround preferences, clearer source cards, automatic source recovery, next-episode playback, and add-on checks. The repository and ZIP filename remain `rokumio-4k-personal` so existing links and build instructions continue to work.

**Version 0.5.16 is an experimental community release.** Software tests and package validation pass. The new screens have authoring previews, but this version has not been installed or tested on a physical Roku. It cannot guarantee that every provider file plays, has English audio, or is genuine 4K.

**[Download the Roku install ZIP — 0.5.16](https://github.com/kaiuribess/rokumio-4k-personal/releases/download/v0.5.16/rokumio-4k-personal-0.5.16.zip)**

Upload that ZIP without extracting it. GitHub's green Code button and “Source code” archives are for developers; they are not the Roku install package.

[Release notes and checksum](https://github.com/kaiuribess/rokumio-4k-personal/releases/tag/v0.5.16) · [Installation](docs/INSTALL.md) · [Add-on checks](docs/ADDON_CHECKS.md) · [Playback and 4K](docs/PLAYBACK.md) · [Development](docs/DEVELOPMENT.md) · [Changes](CHANGELOG.md)

## What you can do

- Browse a featured Home with Search, Movies, Shows, Genres and My list shortcuts, Continue Watching, provider catalogs and advertised genre rows. Down expands the two-row browser; **See all** opens the complete catalog and pagination.
- Search titles and open series seasons/episodes. Full Discover filters, Library, Add-ons, Settings and About remain available.
- Use remote navigation and native Roku keyboard voice dictation where your device, remote, language and region support it.
- Play direct HTTPS MP4/MKV or HLS/DASH streams that your Roku supports. The direct path needs no PC or external streaming server during playback.
- Choose labelled 4K or 1080p sources. Press **\*** on the source screen to toggle **4K-only / all qualities**.
- Let automatic playback rank source candidates, try compatible alternatives, and remember previously successful file identities.
- Browse retained source choices in pages of 48 with **More sources** and **Previous sources**. The selected page does not shrink the player's available fallback pool.
- Choose **TV / projector speakers** or **HDMI soundbar / receiver** under **Settings → Audio mode**. **Audio connection** shows current Roku capability reports and explains a remaining Stereo setting. Audio compatibility still depends on the actual track and connected equipment.
- Open **Add-ons → Check add-ons** to see which installed manifest is reachable or needs attention. The source picker also shows the selected provider's request status. An empty title response or a catalog-only add-on is not automatically labelled broken.
- Continue shows automatically after an accepted episode ends: a **five-second countdown** names the next episode; **Back cancels**. The next episode gets fresh sources and retains the quality filter/audio mode. Regular seasons roll forward without jumping into specials.
- Save resume positions locally; optional Stremio pairing provides account synchronization.
- Save **Picture quality**, **Automatic Play**, **Next episode** and **Source recovery** preferences under Settings. Start sooner is the automatic selection default; Compare providers keeps broader comparison available. Defaults retain 1080p fallback, autoplay and bounded automatic recovery; English dialogue checks stay active.
- Choose **Settings → Preferred source** to request that installed provider first when a slot is free. Automatic uses the most recent provider that passed the existing English-track/native A/V progress checks. Queued providers and active requests have distinct status labels.

The built-in Cinemeta catalog supplies title metadata. **Playable movies, shows, provider accounts and configured stream add-ons are not bundled.** Install your own compatible provider manifest and use content you are authorized to access. Searching a title does not establish that a playable 4K source exists.

## What we added

These are our changes on top of the original client:

- **Crimson Cinema interface:** dark backgrounds, red focus highlights, new app icon/splash, simpler settings and a separate About page with a small Rokumio credit.
- **Lightweight cinematic Home:** one featured image, five shortcuts, progressive catalog/genre shelves, compact previews and full-catalog entry. No video previews or movie inspection on poster focus.
- **Stick performance safeguards:** bounded Home data, correctly sized poster loads, delayed featured artwork, deferred hidden-screen grid updates and playback queue cleanup. These reduce work; they are not measured frame-rate or zero-buffering guarantees.
- **Add-on diagnostics:** named, cancellable manifest checks; fixed safe error categories; and per-provider source status. Private configured URLs and arbitrary provider errors are excluded from the diagnostic result.
- **4K-first source selection:** clearer 2160p/1080p choices, a 4K-only filter, and rejection of inspected MKV video known to be below UHD in that mode.
- **English audio handling:** dialogue-track selection, commentary/audio-description filtering, stale track-selection fixes, and bounded native audio recovery.
- **Projector and surround preferences:** explicit equipment choice, connection guidance, current native capability reports, source ranking and compatibility checks for stereo speakers or a connected soundbar/receiver.
- **Automatic source recovery:** bounded retries for failed starts, stalls and early endings, with memory of previously working file identities.
- **Playback stability fixes:** current-operation timer guards, recovery when native terminal fields reset, a retained startup deadline until acceptance, and better ordering of usable English MP3/PCM and supported surround alternatives.
- **Faster source browsing:** short-lived source preloading, fresh-link refresh, cleaner cards and protection against late results overriding a manual choice.
- **Earlier automatic Play:** start from an available ranked pool after a short comparison window, or save Compare providers to wait for the wider pool. Shared source-list scheduling limits worker concurrency and pauses queued loading during playback.
- **Automatic next episode:** a five-second countdown, Back cancellation, season rollover, fresh sources and preserved quality/audio preferences.
- **Voice and playback information:** native voice-search/transport wiring and available codec/resolution facts that distinguish a source label from measured playback data.

These additions improve selection and recovery; they do not add a transcoder or guarantee compatibility with every provider file.

## Quick start

1. Use the **Download the Roku install ZIP** link above; do not extract it before installing.
2. Enable Roku developer mode and upload that ZIP through the local Development Application Installer. See the [full steps](docs/INSTALL.md).
3. Choose **Browse movies & shows**, then **Add-ons**. Leave Add-ons open and use the local setup address displayed there to import your configured HTTPS `manifest.json` URL.
4. Open **Settings → Audio mode** and choose your connected speakers. Use **Audio connection** to check the current path, then search for a title and press Play. Compatible direct providers play on Roku itself. If you enable 4K-only, the app will not silently fall back to a labelled HD source.

You need a computer/phone for installation or convenient initial configuration. It does not need to remain running for compatible direct-stream playback. Raw torrent/hash-only streams require a separate streaming server; this app is not a torrent engine or audio transcoder.

## Memory and performance

Home retains up to 12 catalog previews of 24 titles each, plus Continue Watching. The full catalogs remain available in Discover. Home makes at most eight base-catalog and eight genre requests, plus up to eight missing-manifest lookups, sequentially on a worker. Only one small featured texture is used; leaving Home releases it and prevents background results from building poster grids over playback.

The app does not save movies. Source preloading is RAM-only for one title, expires after 60 seconds, and holds at most four providers with 256 unique candidates each, reserving up to 64 labelled UHD candidates. Persistent source memory is limited to 32 hashed file-outcome records; it contains no signed URLs. Working outcomes expire in 14 days, verified incompatibility in seven days and transient failures in ten minutes. Leaving the player releases its old queue. Watch history and saved titles remain separate.

Preloading and explicit source requests share two worker slots. All eligible providers remain queued and browsable. Queued requests pause while Player is in front; returning resumes them. A lookup already in flight keeps its slot across title changes until it reports completion, so rapid navigation cannot create a new full batch on each visit. This can delay a new title behind previous requests. It limits owned source-list workers, not all HTTPS connections or provider response sizes. Explicit source results stay with the current source screen until it is canceled/reloaded; the 60-second TTL describes the warm cache.

Start sooner may begin with fewer recovery alternatives than Compare providers. Both retain native quality/audio checks. Later providers do not switch a movie that is already playing.

For a quality-first 4K setup, choose **Compare providers** and **4K only**. With HD fallback enabled, Start sooner may select an available 1080p candidate before a slower provider returns UHD. Initial 2160p labels remain hints; they do not universally prove native UHD decoding.

The source list displays 48 real cards per page, plus two fixed navigation controls when paging is enabled. More/Previous expose later **retained, eligible** choices without growing the current page. Warm prefetch still has its existing 256-candidate/provider cap; Play/Pause refresh uses an ordinary provider response. Ordinary response bytes are not capped by paging. Provider priority reorders waiting jobs only; active transfers are not preempted. Only two opaque hashes are saved for preferred/last working provider identity, excluding configured paths, queries and userinfo.

These limits protect memory and background work without disabling search, full browsing, 4K/1080p selection, voice controls, subtitles, resume, add-on checks or next-episode playback. Actual smoothness and network buffering still require device observation.

## What “4K” means here

A filename or source label saying 2160p is a **hint**. Genuine UHD requires the actual encoded video to have UHD dimensions and the Roku to decode it. A 3840-wide cinema crop can still be UHD. A TV/projector displaying a 4K HDMI signal does not prove the source is 4K.

Pause to view available native playback facts. Adaptive HLS/DASH segments can change resolution. Progressive MKV/MP4 dimensions may be unavailable; unknown remains unknown. The app rejects completely inspected, known below-UHD MKV video in explicit 4K-only mode, but cannot certify all containers and encodings. Read [the evidence and limits](docs/PLAYBACK.md) before buying a service for this app.

## Build your own / fork this repo

```sh
git clone https://github.com/kaiuribess/rokumio-4k-personal.git
cd rokumio-4k-personal
npm ci --ignore-scripts
npm test
npm run build
python scripts/verify-package.py
```

The installable output is **`dist/rokumio-4k-personal.zip`**. GitHub's automatically generated source ZIP is not the install package. See [development and architecture](docs/DEVELOPMENT.md) for the test boundaries and a contribution guide.

## Attribution

Based on [gpratoe/rokumio-client](https://github.com/gpratoe/rokumio-client), base commit `24d3e74bb29bdd94223710e25cd77ab40fca2b36`. The original copyright and [MIT license](LICENSE) are preserved. Open Sans is distributed under its [SIL Open Font License](fonts/OFL.txt). EmojiOnRoku, emoji-regex and Twemoji-derived code retain their notices and [MIT licenses](licenses/). See [NOTICE.txt](NOTICE.txt).

