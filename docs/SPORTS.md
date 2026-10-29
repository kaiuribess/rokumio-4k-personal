# Sports in Crimson Cinema — 0.6.0 feature preview

**This adds a working schedule browser and extensible native-playback integration, not a subscription-free replacement for every sports broadcaster. No live sports streams are bundled.** An authorized compatible provider is still needed for video. A listed game, reachable playlist or source label does not prove that a Roku can play it.

## On the Roku

1. Open **Sports** in Home's left menu.
2. Pick a league, date and **All events / Live / Upcoming / Completed**. Dates run from yesterday through the next seven days. Start timestamps are shown in UTC; ESPN determines which schedule date an event belongs to.
3. Select an event to check installed compatible providers. Upcoming events show an explanation. Events with no matching provider show **Schedule only**, not a fabricated Play result.
4. When a provider returns direct streams, the existing source picker and player handle automatic selection, manual alternatives, English audio checks, projector/surround preferences and bounded source recovery.
5. **TV / sports add-ons** opens installed TV/channel catalogs or Add-ons management. These can cover boxing, other competitions or linear channels outside the built-in schedule. They are not all sports catalogs and are labelled by provider.

**Down** from the filters enters the event list. ***** returns to filters; **Play/Pause** refreshes. Back dismisses an open filter, then returns immediately without waiting for network work. There is no background polling during a movie.

The schedule supports NFL, NBA, MLB, NHL, UFC, college football, men's/women's college basketball, WNBA, Premier League, MLS, La Liga and Champions League. The inspected boxing endpoint failed; it is not offered as a working schedule adapter. Completed means the event ended, not that a replay is available.

Sports event requests permit HD even if movies are set to 4K-only. Movie settings are not changed. Live sources do not enter Continue Watching or trigger next-episode autoplay. HLS can adapt quality during playback; no 4K or surround guarantee is made.

## Providers investigated

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

The app consults the actual installed AddonsStore capabilities on selection; account removal/switching is not bypassed by a copied provider list. Existing source-worker limits, 48-card pagination, fallback/discovery limits, native Video, voice controls, captions, audio policy and source memory remain in place. Fallback is bounded, not endless. English-tagged source labels alone cannot bypass the native audio check; an otherwise playable broadcast with untagged audio may be rejected.

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

API-tested: dated league responses plus one public HLS master/variant/segment prefix. **Not physically Roku-tested:** Sports layout/navigation, live decoder startup, audible English/surround, adaptive playback, real source failover and the new paused-Down shortcut.

Before recommending a sports provider, establish its distribution permission and stable direct endpoint; then test live startup, sustained playback, expiring/unavailable alternatives, Back during loading and audible output on the actual Roku/HDMI route. None of the probes establishes universal NFL/NBA/UFC coverage or no-buffering playback.

## Skip to the next episode before credits

In this feature build, pause an accepted TV episode, then press **Down** when the playback-information overlay shows **Down: next episode now**. It saves your real position and fetches fresh sources for the next known aired episode. It works with automatic next episode disabled and does not mark the skipped remainder watched. Play/Pause, seeking, captions and Back retain their existing native paths.

No next action appears for movies, live channels, diagnostics, missing episode metadata, the final known episode or a future release. This is manual episode advance, not automatic credit recognition. The production key/timer/navigation logic is software-tested; whether the native Video overlay passes Down through on each Roku OS still needs a physical check. The existing Back → episodes list remains available.
