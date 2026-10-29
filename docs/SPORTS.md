# Sports in Crimson Cinema — 0.6.0 feature preview

**Provider-native live browsing now reaches the existing native player.** During October 29 testing, the free StremVerse Live Events service returned HLS media that decoded on the PC at **1920×1080 H.264/AAC** for one event and **512×288 H.264/AAC** for another. This is real media evidence, not a mock stream. Other sources failed, and a later request for the HD event returned 403. **Sustained Roku playback, audible English, broadcast authorization and broad league coverage remain unverified.** No provider is installed or bundled automatically.

**Reliability follow-up:** [manual backup setup and measured results](SPORTS-RELIABILITY.md). Replay on live Sources now opens other installed providers for manual same-event selection, and provider-native `sports` catalogs are supported. StremVerse's repeated 403 was at the entry playlist. A CNCVerse alternative decoded a holding card; Nebula's selected HLS failed. Highfly's free `.dev` configuration pages worked but require human verification. **StremVerse and CNCVerse separately passed two-minute NHL PC runs, but share a gateway; independent delivery and Roku validation remain open.**

## Quick setup and use

1. Install the developer ZIP from the successful **PR #9 CI artifact**, not GitHub's source archive. This preview is not merged or hardware-certified.
2. In **Add-ons**, import an HTTPS manifest for a provider you are authorized to use. The free service tested here is `https://stremverse1.alwaysdata.net/manifest.json`. Its [provider FAQ](https://stremverse1.alwaysdata.net/) distinguishes free **Live Events / Replays / Highlights** from paid **Xtra / IPTV**. The free path needs no membership, Stremio app/account, media proxy or permanently running PC. This is a technical compatibility result, not an endorsement or a grant of broadcast rights.
3. Return to **Sports → provider · Live Events**. Sports lists your installed TV/channel/sports catalogs. Choose an event, then a source. Its original ID/type goes to the original provider; no ESPN matching or per-game JSON editing is required.
4. **Live mode** starts about 12 seconds behind the available live edge where supported. It disables resume, next episode and online movie subtitle lookups. Source quality depends on the provider; an “HD SERVER” label is not a measurement.
5. **English + unlabelled** prefers English but permits missing language metadata after native codec and advancing audio/video checks. Playback details still say English is unverified. Choose **Audio: verified English** in Sports, or press **\*** in the live source picker to require it. Known foreign-language tracks remain blocked. Movie/series audio rules are unchanged.
6. For a replay/highlight, choose **Playback: Recorded** before opening its catalog. This restores the existing Details/playback path and strict movie-style audio checks; legacy TV/channel no-resume behavior is unchanged. “Live” is the selected playback mode, not independent proof of an event's time/status.

**Down** enters the list; **\*** returns to Sports filters. **Play/Pause** refreshes. **Back** exits without waiting for provider requests. Existing source pagination and bounded alternatives remain available. No source replacement occurs merely because a late result arrives.

The first Sports filter also opens the separate ESPN schedule browser (13 leagues, yesterday through seven days ahead, times UTC). Schedule IDs are not shared with sports add-ons. **Schedule only** does not mean a stream exists. Use **TV / sports add-ons → Return to provider catalogs** to leave schedules. Events in a provider catalog may be upcoming, completed, mislabeled or unavailable; empty/browser-only/error responses are reported honestly.

## Fresh provider and video investigation

Read-only checks on **2026-10-29, approximately 21:32–21:50 UTC**, from this PC/network. [Sanitized response/decode evidence](research/live-providers-2026-10-29.json) contains no media URLs, request header values, tokens or video files.

| Provider | Real response evidence | Integration decision |
| --- | --- | --- |
| [Nuvio Live Sports](https://nuviosports.xyz/configure), [source](https://github.com/rajhodedara/live-sport-plugin) | Public manifest/configuration returned HTTP 403 (Cloudflare 1010). Source advertises catalog/meta/stream, TV/channel types, `nuvio_sport_` IDs and multiple upstream adapters. [Issue 63](https://github.com/rajhodedara/live-sport-plugin/issues/63) separately reports catalogs loading while replay streams fail. | Native add-on protocol is a potential fit, but service playback is **not verified here**. No browser challenge bypass or copied resolver. The upstream README discourages common free/shared hosting; no self-hosting expense introduced. |
| [Highfly free instances](https://www.reddit.com/r/nuvioaddons/comments/1wig7l4/addon_sports_streams_update_domain_change_nba_soc/) | Earlier unconfigured `.to` manifest attempts returned 403. Later both free `.dev` configuration pages returned 200 and required human verification to issue the real link. [lista-m3u](https://github.com/SPxMM3R1/lista-m3u/blob/main/highfly_live.py) is an integration lead, not proof of service health. | **Configured playback remains untested.** The earlier bare-endpoint test was insufficient; follow the [normal configuration step](SPORTS-RELIABILITY.md#highfly-exact-remaining-step). No challenge bypass or premium service used. |
| [StremVerse free Live Events](https://stremverse1.alwaysdata.net/) | Manifest 3.0.0, `tv` catalog `stremverse_live_events`; Crimson's exact `skip=0.json` route returned 107 entries. Four early sampled stream responses ranged from empty to browser-only to multiple direct media links. A Copa del Rey item supplied HLS and decoded 300 video/517 audio frames at 512×288; HB Koge vs Barcelona supplied HLS and decoded 225 video/387 audio frames at 1920×1080. Both were AVC/AAC without language tags. A later HD request returned 403. | Strongest **tested direct-media path**, using the existing add-on system, original IDs, queries and per-source Referer/User-Agent headers. No new adapter/host required. Not a universal reliability, rights, English or Roku claim. Only the free live catalog was requested. |
| [StreamFree API](https://strmfree.st/api) | Documentation and `/api/v1/streams` responded; event objects contained `live_sources` pointing to embed pages. | Event/source discovery exists, but embeds are not native Video URLs. No new resolver justified while the hosted direct-media path works. No embed scripts or protected token machinery executed. |

Community [StremVerse developer announcement and replies](https://www.reddit.com/r/StremioAddons/comments/1s7uy9m/stremverse_just_another_sports_addon_for_stremio/) identify the free offering and also report empty catalogs/failed playback. These guided testing; they do not establish coverage or Roku compatibility. Other upstream names in Nuvio's source are implementation leads, not independently tested/bundled providers. No upstream code was copied, so no upstream resolver license is assumed from marketing text.

### Reproduce the bounded checks

```text
python scripts/probe-live-providers.py --event-index 3 --event-index 9 --output verification/live-providers.json
```

Indices select the **current** catalog snapshot and can refer to different events later. The report stores the event name and SHA-256 of the opaque ID for attribution. Optional `--decode` requires PyAV in a separate research environment (tested with 19.0.2); it is neither an app dependency nor part of the Roku ZIP. The probe reads at most three 8 MiB segments per source, refuses non-public/non-HTTPS destinations, stops at encryption tags, checks redirects and records only status/origin/codec evidence. It never installs an add-on or solves an access challenge. Run `python tests/probe-live-providers.test.py` for the offline tool tests.

## Earlier alternatives and schedule checks


Read-only research on **October 29, 2026**:

| Option | Evidence and technical fit | Decision |
| --- | --- | --- |
| ESPN public scoreboards | All 13 selected league endpoints returned HTTP 200 with an events array using the same date/limit query as the app. Several had zero events that day. No key needed. [Example endpoint](https://site.api.espn.com/apis/site/v2/sports/football/nfl/scoreboard). | Schedule adapter only. Publicly reachable, undocumented endpoint; no SLA or redistribution license implied. No video links inferred from scores. |
| [TheSportsDB](https://api.thesportsdb.com/docs_api_examples) | Documented metadata API with public V1 examples. V2 live scores are shown as premium (€9/month at inspection). It does not supply general match streams. | Possible future metadata adapter; no paid API introduced. |
| [Streamed.pk](https://streamed.pk/) | The site announces closure; its former matches endpoint returned HTML rather than JSON. Old stream documentation described embedded players. | Excluded. A successful HTTP status alone would have produced a broken catalog. |
| [st-barts/stremio-streamed-addon](https://github.com/st-barts/stremio-streamed-addon) | Its README describes Browser Run token extraction, KV caching and Referer/playlist proxying for another aggregation site. Claims free-tier operation, but quotas and rotating tokens remain dependencies. | Not adopted: broadcast authorization not established; additional browser/resolver infrastructure and fragile upstream delivery. No code copied. |
| Red Bull TV | Public CDN master, lowest variant and a bounded segment prefix returned HTTP 200. Master advertised AVC/AAC and 180p–1080p; sampled playlist had no encryption tag or end marker; prefix had MPEG-TS sync bytes. [Publisher support/licensing](https://www.redbull.com/gb-en/support-hub/media-and-platforms). | Research-only. Not bundled: technical reachability does not establish permission for this distribution. No 4K, audible-English or Roku decoding proof. |
| [Pluto sports](https://www.paramountpressexpress.com/pluto-tv/page/sports) | Official free sports channels include analysis, highlights and selected events. A league-branded channel is not proof of every live league game. Previously used community manifest host was unreachable in this investigation. | Official app remains an option. No new undocumented session/token implementation or dead manifest bundled. Existing user-installed add-ons remain available. |
| [FIFA+ on DAZN](https://www.dazn.com/en-GB/help/articles/36029102113053-fifa-on-dazn-everything-you-need-to-know) | Publisher documents free football programming, including selected live matches. Platform/territory access is separate from a direct Roku-compatible stream endpoint. | No reliable public integration endpoint established here; no web page handed to the native player. |
| [iptv-org](https://github.com/iptv-org/iptv), [Kodi InputStream Adaptive](https://github.com/xbmc/inputstream.adaptive) | Useful playlist discovery and adaptive-player projects. A playlist directory does not itself grant broadcast rights; Kodi's player is not a Roku runtime. | No bulk import of unverified rights/health, no Kodi dependency, no DRM bypass. |

The reproducible probe is `python scripts/probe-sports.py --media --output verification/sports-provider-probe.json`. It makes bounded public requests with no account, cookies or custom Referer. The media flag reads only a segment prefix; it does **not** decode video or measure continuous throughput. [Recorded results](research/sports-probe-2026-10-29.json) include the failed boxing request rather than hiding it.

## Architecture and limits

The Roku directly fetches one schedule at a time through the existing bounded HTTPS transport: **10-second overall request budget, 1 MiB response limit, 100 retained events, 160-character names**. Normalization runs in a Task. Result and finished callbacks are separate: an empty result notification does not cancel a request, duplicate/stale events cannot repaint another date, and rapid navigation does not multiply outstanding schedule transfers. Failed refreshes preserve the earlier schedule with an explicit warning. Returning after 60 seconds refreshes; nothing refreshes behind playback.

Schedule IDs are `espn_<sport>_<league>_<eventId>`, for example `espn_football_nfl_123`. They are metadata identifiers, not media URLs. A compatible add-on advertises `stream` for `tv` with the `espn_` prefix. Custom event/channel catalogs can use `sports_<operator-id>`. An arbitrary existing movie add-on is not expected to recognize these IDs.

Provider-native playback is pinned to the selected catalog owner and its exact original ID/type. A second provider advertising broad `tv` support is not automatically trusted to identify the same game. Alternatives are limited to the original provider/event response; upstream mislabeling remains possible. Account switching/removal uses the existing registry, not a copied provider database.

The existing two-worker coordinator refreshes live lists after 30 seconds on explicit adoption/return/selection, compared with five minutes for movies. This is a bounded freshness policy, not a promise that every signed link lasts 30 seconds. Failed pools use the existing maximum two discovery rounds and attempted-URL exclusion. Successful playback is not changed by background results. No live media URL is saved to source memory; movie source memory is unchanged.

Queries and validated per-item headers survive the source budget and reach a fresh video HTTP agent. Explicit safe stream-format hints and small, signature-checked HLS/DASH responses support extensionless endpoints. Browser-only responses produce an explanation. No HTML player, authentication challenge or DRM is resolved by Crimson. Existing HTTPS source policy remains; the static publisher's stricter query-free URL rules are **not** general native-player limitations.

The selected Live mode uses Roku's documented [Live/PlayStart/HttpHeaders metadata](https://developer.roku.com/dev/docs/content-metadata) and existing native controls. It does not transcode or create English audio. Unlabelled-live acceptance and English verification are separate facts; compatible decoder metadata plus advancing native audio/video samples are still required. Explicit receiver/codec rejection is retained. 48-card pagination, movies, TorBox, voice, captions, projector/surround preferences and manual next episode are preserved.

## Standalone add-on for an authorized broadcaster

The dependency-free publisher in [tools/sports-addon](../tools/sports-addon/) turns an operator's **public, authorized** streams into the standard [add-on stream protocol](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/stream.md). It does not require the Stremio app or account.

Start with `tools/sports-addon/feed.example.json`. Its empty list is intentional. Add an event only after establishing permission to publish its links and play it in this client:

```json
{
  "id": "org.example.sports",
  "name": "Example Sports",
  "events": [{
    "id": "espn_football_nfl_123",
    "name": "Example game — replace with an authorized event",
    "description": "Public English broadcast",
    "expiresAt": "YYYY-MM-DDTHH:MM:SSZ",
    "permission": {
      "owner": "Broadcaster name",
      "publicPlayback": true,
      "redistribution": true,
      "url": "https://example.com/permission"
    },
    "sources": [{
      "name": "Primary",
      "url": "https://example.com/live.m3u8",
      "quality": "1080p",
      "languages": ["eng"]
    }]
  }]
}
```

This is a schema example, **not a playable feed or permission grant**. Replace the ID, publisher evidence, date and media URL. Omit quality when unknown. Put alternatives in source order; Crimson's compatibility/quality ranking may reorder them. A provider's priority can be chosen in Settings.

Build into a **new** directory:

```text
node tools/sports-addon/build.js my-authorized-feed.json sports-public
```

The builder emits manifest, catalog (including Crimson's `skip=0.json` route), metadata and per-event stream JSON. It limits 100 events/eight sources each, deduplicates URLs, rejects path traversal and excludes expired/empty entries. It requires permission assertions and an evidence URL, but cannot independently verify an operator's rights claim.

Only public HTTPS HLS `.m3u8` or DASH `.mpd` URLs are accepted. Query strings, credentials, fragments, custom ports, IP/local hosts, DRM, cookies and custom headers are rejected. **Do not publish API keys or private/signed links, even encoded in a URL path.** The builder cannot identify every secret hidden in a path. It does not resolve HTML players, mint credentials, proxy media or evade geographic restrictions.

Publish the generated files to an HTTPS static host you control. [GitHub Pages supports public repositories on GitHub Free](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages); an existing static host also works. Review its limits and your distribution permission before publishing. No hosting deployment is performed by this PR. Once hosted, the PC can be off: Roku fetches JSON from the host and video from the broadcaster/CDN. Hosting accounts are for the operator, not every viewer.

For GitHub Pages: create a separate public feed repository, copy the **contents** of the generated directory to its root (including `.nojekyll`), commit them, then choose **Settings → Pages → Deploy from a branch → main / root**. Wait for its Pages deployment to finish and open `https://OWNER.github.io/FEED-REPOSITORY/manifest.json` to confirm JSON, not a 404 page. Use that full URL for the import. Updating this feed repository updates the provider without rebuilding the Roku app. Do not upload video segments to Pages.

Install `https://YOUR-HOST/manifest.json` through **Crimson → Add-ons** and its existing TV-approved setup page. Multiple independent providers can be installed, reordered and removed without rebuilding Crimson. No provider is silently installed and no remote Stremio account is changed.

Expiry must be within seven days of building. Rebuild/redeploy after rechecking availability. Crimson checks `behaviorHints.crimsonExpiresAt` during stream discovery **and again when resolving retained candidates**. Expiry does not interrupt an already playing broadcast; old catalog titles may remain until the host updates, but their expired sources are rejected. Static hosting cannot rotate signed URLs or enforce regional rights. A future authorized provider needing that behavior must implement its own fresh `stream/tv/<id>.json` endpoint within its cost budget.

The expiry hint is a Crimson extension. Other clients may ignore it; operators must replace/remove outdated public JSON at the host. Permission attestations and expiry checks are not DRM or access control.

## Verification and remaining gate

See [exact commands, counts and remaining acceptance checks](SPORTS-VALIDATION.md).

Software tests execute production schedule worker/result/finished handlers, source capabilities through AddonsStore, generated manifest registration, CatalogStore requests, Sports/Scene navigation, source budgeting/ranking, PlaybackStore resolution and expiry. Separate local HTTP tests request the actual generated files. Mock media is never presented as a real sports broadcast.

API/media-tested: dated league responses, provider-native catalogs and stream responses, and short StremVerse HLS samples decoded on the PC at 288p and 1080p. A later HD request failed with 403; neither sample proved English language or sustained delivery. **Not physically Roku-tested:** Sports layout/navigation, live decoder startup, audible English/surround, adaptive playback, real source failover and the new paused-Down shortcut.

Before recommending a sports provider, establish its distribution permission and stable direct endpoint; then test live startup, sustained playback, expiring/unavailable alternatives, Back during loading and audible output on the actual Roku/HDMI route. None of the probes establishes universal NFL/NBA/UFC coverage or no-buffering playback.

## Skip to the next episode before credits

In this feature build, pause an accepted TV episode, then press **Down** when the playback-information overlay shows **Down: next episode now**. It saves your real position and fetches fresh sources for the next known aired episode. It works with automatic next episode disabled and does not mark the skipped remainder watched. Play/Pause, seeking, captions and Back retain their existing native paths.

No next action appears for movies, live channels, diagnostics, missing episode metadata, the final known episode or a future release. This is manual episode advance, not automatic credit recognition. The production key/timer/navigation logic is software-tested; whether the native Video overlay passes Down through on each Roku OS still needs a physical check. The existing Back → episodes list remains available.
