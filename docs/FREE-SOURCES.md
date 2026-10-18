# Optional free sources

Crimson Cinema can use free add-ons, but each add-on has a different role. The two playback providers below are **optional imports**, not bundled accounts or default streaming services. No account or paid key was required for the configurations checked on **October 17, 2026**. Availability, host limits and provider terms can change; free access today is not a lifetime guarantee.

Install your own compatible provider manifest and use content you are authorized to access. Listing an add-on here does not establish permission to watch every title it returns, an affiliation with its operator, or a guarantee of playback.

## Browsing and captions

| Add-on | What it supplies | Public manifest |
| --- | --- | --- |
| Cinemeta | Movie/show search and title metadata. Normally already available in the local profile. | [Cinemeta](https://v3-cinemeta.strem.io/manifest.json) |
| Streaming Catalogs | Extra browsing rows grouped by streaming service. These rows do not grant access to those services. | [Streaming Catalogs](https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club/manifest.json) |
| OpenSubtitles v3 | Subtitle choices; language and timing depend on the selected track. | [OpenSubtitles v3](https://opensubtitles-v3.strem.io/manifest.json) |

**None of these three supplies movie streams.** Check the installed Add-ons list before importing a duplicate. Provider references: [Stremio's official add-on collection](https://github.com/Stremio/stremio-official-addons/blob/master/index.json) and [Streaming Catalogs source](https://github.com/rleroi/Stremio-Streaming-Catalogs-Addon).

### TMDB: latest releases and trending movies/shows

The account-free [TMDB Addon on ElfHosted](https://tmdb.elfhosted.com/configure) version 3.1.7 supplied working Latest Releases movie, Trending series and Trending movie catalogs in the October 17 checks. Configure **both** `provideImdbId:"true"` and `returnImdbId:"true"`, plus `language:"en-US"`. The second IMDb flag is essential: the bare default can return `tmdb:` identifiers that an IMDb stream provider does not accept. Keep just those three browse catalogs plus its two search catalogs for a compact setup. Family Guy metadata returned 483 episode records with IMDb-compatible series/season/episode IDs. These observations establish metadata interoperability, not source availability or playback.

In 0.5.29, Home shares its eight base-preview requests across providers, so earlier catalog add-ons cannot spend every slot before a later provider is considered. Existing row/poster/request bounds remain; all supported catalogs stay accessible through Discover. Discover now honors TMDB's advertised 20-item page size and advances by the raw provider count while stopping empty/repeated pages. A catalog-only add-on with IMDb items may still need a separate metadata-capable provider; the inspected TMDB configuration supplies its own working metadata and does not depend on that unresolved generic fallback path.

Older AIOCatalogs and Cyberflix links should not be added from stale guides: their operators' current materials identify discontinuation/retirement. Verify the current manifest rather than treating a catalog name as proof of maintenance.

## HDHub: optional on-demand sources

[HDHub's configuration page](https://hdhub.thevolecitor.qzz.io/) supplies direct movie/episode sources. The public configuration below requests 2160p and 1080p, descending quality, at most five results per quality/provider, and no extra catalogs. It contains **no account key**; the encoded TorBox setting is the literal value `unset`.

```text
https://hdhub.thevolecitor.qzz.io/eyJ0b3Jib3giOiJ1bnNldCIsInF1YWxpdGllcyI6IjIxNjBwLDEwODBwIiwic29ydCI6ImRlc2MiLCJtcSI6NSwibXAiOjUsImNhdGFsb2dzIjoiIn0/manifest.json
```

The checked manifest was `com.stremio.HdHub` version 1.0.7. Bounded media-header checks found seekable HTTPS Matroska files, including encoded 3840x2160 HEVC video with explicitly tagged English AAC or E-AC-3 tracks, and 1080p alternatives. Other results had uncertain audio language or failed range requests. These checks did not play a complete title or establish audible audio, surround output, sustained Roku decoding, or whether a source master was upscaled.

Some results use Pixeldrain. Its [current plan page](https://pixeldrain.com/home) advertises a 6 GB free allowance and reduced speed of 1 MiB/s after the limit. Its [FAQ](https://docs.pixeldrain.com/questions_and_answers/#how-does-the-transfer-limit-work) explains that free usage is tracked per IP over a rolling 24-hour window; hotlink protection can also interrupt access. We have not established that this add-on's links are exempt. Large files can exhaust that allowance, so this is not an unlimited free 4K service.

The provider can also return **Download Only** entries that do not support reliable seeking. Version 0.5.23 excludes recognized download-only and 10Gbps delivery annotations from selection; 0.5.22 does not. The provider's configuration does not itself guarantee English audio. A filename, language label or quality label remains a hint until usable track/dimension evidence is available.

## Pluto TV: optional live channels

```text
https://dev.nebulawp.org/stremio/pluto-tv-addon/manifest.json
```

This is a [community Pluto TV add-on](https://stremio-addons.net/addons/pluto-tv), not the official Pluto app. The checked manifest was `org.plutotv` version 1.0.0 and provided catalogs, metadata and live streams. Sample requests returned direct HTTPS HLS playlists on Pluto's delivery service. The sampled playlists advertised English stereo audio; a bounded clear audio segment contained AAC.

It supplies scheduled live channels, not on-demand access to every movie or episode. Catalogs include different regions/languages, and individual channels may be unavailable locally. The checks did not establish 4K, audible surround or physical Roku playback.

## Import only the providers you want

1. Open **Crimson Cinema > Add-ons** on Roku and leave it open.
2. On a phone/computer on the same network, open the local setup address displayed there.
3. Paste one public manifest above and submit it.
4. Select **Allow import** on the TV within 60 seconds, then read the final import summary. The browser acknowledgement alone does not confirm installation.
5. Run **Add-ons > Check add-ons**. A reachable manifest confirms setup, not that every title or channel will play.

For HD fallback, use **Settings > Picture quality > 4K first + 1080p**. Choose **TV / projector speakers** or **HDMI soundbar / receiver** under **Audio mode** to match the connected equipment. See [playback and 4K evidence](PLAYBACK.md) for the difference between source labels, encoded dimensions and native playback. Once a compatible direct stream starts, the setup phone/computer does not need to remain on.

Keep configured URLs containing personal keys private. Only the account-free public examples above belong in shared documentation; never post signed media URLs, account manifests or credentials in an issue.

## Broader coverage and current releases

Catalogs and search query online providers. A newly listed movie or episode may still have no compatible stream; a theater listing is not evidence of a released UHD file. Adding more catalogs does not expand the media available from the installed stream providers.

For larger files, an account-backed host may offer a more suitable delivery path than a throttled free host. This is conditional on the particular file, cache and connector. As checked on October 17, 2026, [TorBox's official May 20 announcement](https://feedback.torbox.app/changelog/v844) says its hosted Stremio add-on was disabled. Do not use old instructions promising that official manifest. A maintained third-party connector and its current direct HTTPS output need to be verified before recommending a subscription for Crimson. The [pricing page](https://www.torbox.app/pricing) lists the plans; a higher-priced plan does not prove better title coverage or compatibility with Roku.

For a paid route to evaluate separately within a $5/month ceiling, current primary documentation lists **TorBox Essential at $3/month** with unlimited cached downloads and a 200 GB maximum file size. Standard mainly adds active download slots and seeding time; it is not a documented fix for single-stream buffering. Use a maintained connector such as [Torrentio](https://torrentio.strem.fun/configure) or [hosted AIOStreams](https://docs.aiostreams.viren070.me/getting-started/public-instances/) that explicitly supports TorBox and returns fresh direct HTTPS links. Prefer cached English HEVC UHD candidates with compatible audio and a practical bitrate. No subscription was purchased or authenticated, and this exact route has not been certified on this Roku. See [TorBox restrictions](https://support.torbox.app/en/articles/9836418-account-restrictions), [cache behavior](https://support.torbox.app/en/articles/9923071-how-does-the-torbox-cache-work), and [shared delivery-speed limits](https://support.torbox.app/en/articles/9836433-what-is-the-speed-of-my-connection-to-torbox).

Before a purchase, check whether the account offers TorBox's documented [24-hour Pro demo](https://support.torbox.app/en/articles/13247567-does-torbox-offer-any-sort-of-trial-or-demo). Read the offered eligibility, payment and renewal terms before activation; neither eligibility nor no-card/no-renewal behavior was verified for a specific account. A successful Pro demo is not proof of identical Essential traffic priority. Ordinary Free-tier API/connector eligibility must not be inferred from pricing-page text stripped of its checkmark icons. Set up the compatible connector privately with the user's own key, English and 2160p plus 1080p, prefer cached results and exclude acquisition/status clips. Keep a modest result cap, preserve filenames/size hints and avoid unnecessary proxying. Public AIOStreams instances can disable particular integrations (including Torrentio on ElfHosted); verify the selected host's supported integrations before using it. No password or configured manifest belongs in an issue or chat.

[Comet's public ElfHosted configuration](https://comet.elfhosted.com/configure) is another inspected TorBox connector. A private, owner-authorized profile used cached-only results, required/preferred English, eight results per resolution, 2160p plus 1080p, no raw torrents and a 35-GiB source-size ceiling. Manifest and movie/episode discovery succeeded; the PC's first redirected media check returned HTTP403 at the CDN, so native reliability remains unverified. Shared-instance limits apply. Comet receives the entered service key, and its configured URL reversibly encodes it; keep the complete URL and related browser logs private. Do not copy another person's configuration or bundle one in a release. [Comet source](https://github.com/g0ldyy/comet). This is an optional account-backed route; it is not a free cloud subscription or a guarantee of every title.

Adding another free aggregator may repeat HDHub's hosts rather than add bandwidth. Fresh checks of Flix-Streams Free, Sootio HTTP-only, Pipe and WebStreamrMBG did not establish a stronger sustained UHD path. Sootio's current default HTTP configuration did return English/UHD-labelled resolver links for three sampled movies; an 84.58 GB candidate redirected to a host that refused the bounded media check with HTTP 403. This is not evidence of a working UHD source. Flix returned an inspected cropped UHD HEVC file, but native provider lookup and automatic candidate attempts did not reach sustained playback in this test. Pipe returned no streams for the sampled movie, and another candidate contained an unusable proxy hostname. Labels and header inspection do not prove native playback or reliability. No additional provider was persistently installed.

Crimson does not increase a file host's transfer allowance or make a fixed-bitrate MKV adaptive. The native player handles the actual media download. Software can reduce competing work, expose diagnostics and recover from a persistently failing source; it cannot guarantee every movie/show or unlimited, uninterrupted free UHD.

## Other apps and lifetime offers

Current [official Stremio downloads](https://www.stremio.com/downloads) do not list Roku. Kodi, Syncler, weyd, CloudStream and Nuvio do not provide a supported native Roku alternative in the platforms checked. Installing their Android packages on this stick is not an available route.

[Stroku Native](https://stroku.netlify.app/) is a credible additional free Roku client with public [MIT source](https://github.com/gabrielsmith1874/Stroku/tree/c7cc0a1528423feed50d3477381a33df97e425bd/Stroku-Native). Its direct-stream route uses add-ons without a home server; its free raw-torrent route explicitly requires an Android server. Store availability/version in each region, microphone support, sustained UHD and audible 5.1 were not independently verified. A different client using the same host does not establish a faster delivery path. No alternative app was installed during this review.

Official Roku Channel, Tubi, Pluto TV and Plex's free catalog are server-independent licensed options for the titles they carry. Their rotating catalogs and title-specific quality do not establish every movie/show in 4K. [Roku free-content guide](https://support.roku.com/article/watch-free-movies-and-tv-shows), [Plex free-catalog FAQ](https://support.plex.tv/articles/frequently-asked-questions-vod/).

Jellyfin is free but needs a media server. Emby's $119 lifetime offer is a software license and explicitly supplies neither server hosting nor content. Neither meets a stick-only setup by itself. No current operator-backed lifetime cloud-delivery offer was verified for Crimson. [Jellyfin requirements](https://jellyfin.org/docs/general/quick-start/), [Emby offer](https://emby.media/premiere.html). No purchase, trial activation, remote-account change or account credential access was performed.
