# Free NBA providers: configured playback checks

Checked October 30, 2026 Pacific / October 31 UTC. This continues draft PR #9 on `feature/live-sports`. The PC investigation below preceded the authorized Roku installation and user feedback recorded in the follow-up. The PR remains draft and unmerged.

**Highfly's free configuration delivered real Celtics–Bulls video in two fresh 120-second PC checks at 1920×1080 H.264/AAC.** Pictures confirmed the game, not a holding card. The same game appeared through StremVerse, whose sampled NBA sources were less stable. Highfly's observed delivery gateway differs from StremVerse's, but hidden origins and operator independence are unknown. This is an additional demonstrated media route, **not hardware sign-off or an all-games guarantee**.

[Sanitized measurements](research/nba-provider-validation-2026-10-31.json) retain failure stages, timings, request origins, decoder results and visual observations. Configured manifests, media links, cookies, account identifiers, header values and video files are excluded.

## Roku installation and user feedback follow-up

The exact tested CI package for commit `ab1e95787ebcb1ced6070d806fba23a09e28caab` was installed on a Roku Streaming Stick Plus with the owner's permission. The developer installer reported success, its stored package size/digest matched the upload, and the active-app query reported Crimson Cinema 0.6.0. This verifies installation and startup, not sustained decoding.

The user then approved individual imports of **Sports Streams (Highfly), PenguPlay, Nuvio Live Sports and StremVerse** and confirmed the four-provider list. Nuvio initially failed because its 74-catalog profile exceeded the existing 64-entry manifest-array budget. Disabling replay catalogs in its normal configuration produced a 17-catalog live profile that the user confirmed imported successfully. No device budget was raised; see the setup below.

After browsing an NBA catalog, selecting a game and choosing a source, the user reported successful playback on the Roku. **The provider, chosen source, playback duration, decoded resolution and audio language were not identified.** This is one user-reported hardware playback success, separate from the measured PC runs below. It does not certify any specific provider on Roku, 4K, English sound, a full match or all-sports reliability.

The same feedback identified too many catalog/source choices. The [all-sports catalog cleanup plan](SPORTS-CATALOG-PLAN.md) records the requested next pass; that interface is **not implemented in this package**.

## A research-client error changed the diagnosis

After the user completed Highfly's normal human verification, its page issued a legitimate free manifest on `sports.highfly.to`. The browser opened it; Python's default urllib client received Cloudflare 1010 / HTTP 403. The same pattern appeared for Nuvio and PenguPlay.

The corrected probe identifies itself truthfully as `CrimsonCinema-Research/0.6`, with the repository address and PC-test purpose. It does not impersonate a browser or Roku, export browser cookies, solve a challenge, invent authorization or override a provider-supplied User-Agent. On the **same private PenguPlay manifest**, an immediate default → identified → default control returned **403 → 200 JSON → 403**. All three configured provider APIs then returned usable catalogs through the identified client.

Earlier bare-client 403s therefore cannot establish that these providers universally fail. Preserve them as dated client-specific observations, not current service verdicts. This correction is in the **PC research probe**. Native Roku transport and decoder behavior were not measured in these checks; the later user report does not turn these PC measurements into Roku results.

## Real media results

| Route | Observation | What it proves / does not prove |
| --- | --- | --- |
| Highfly free, Basketball → Boston Celtics vs Chicago Bulls → Leaf (Strong), NBC Sports Boston | Two fresh resolutions, 120.27 and 120.25 seconds; 26 distinct segments each; 9,326 and 9,353 video frames; 3,665 and 3,660 audio frames. Advancing playlists/PTS, zero decode failures. H.264 1920×1080, AAC tagged `eng`. Media fingerprints changed on renewal. | Sustained bounded PC delivery/decoding and fresh-link retrieval. A separate frame showed CHI 92 / BOS 111, fourth quarter 5:29, NBC Sports Boston. First two frames were commercials; only the game frame establishes content. English metadata is not an audible-room test. This is 1080p, not 4K. |
| Highfly free, TSN 4 alternative | Short three-segment sample decoded 1,080 video / 844 audio frames, 1920×1080 H.264/AAC with `eng` audio metadata. | Another free source delivered media. No separate sustained or picture validation for this alternative. |
| StremVerse, same game (poster identifies Celtics/Bulls), SV5 HD SERVER | Two fresh stream responses; both entry playlists returned 403 with supplied Referer/User-Agent retained. | A media-entry failure, not a manifest/catalog failure. Fresh resolution did not repair it. Cause unknown; no access-control workaround. |
| StremVerse, same game, SV6 SportzX Live | Correct game picture at 1280×720 H.264/AAC. Two attempts advanced then stopped on **segment 404**, after 12.17 and 23.08 seconds. | Same-event overlap and a distinct failure stage. These are failed sustained runs, not successful two-minute tests. Audio was `und` with very few decoded audio frames; no audible-audio claim. Earlier successful NHL runs remain separate evidence. |
| PenguPlay, Basketball, Plorax | Two fresh runs lasted 123.22 / 120.19 seconds, fetched 27 / 28 distinct segments and decoded 9,661 / 10,080 video frames at 1080p H.264/AAC (`eng`), with zero decode failures. The second playlist window repeated for eight consecutive polls before advancing. | Its segments use **the same `east.papacito.cfd` origin as Highfly**. It is not an independent CDN backup or a zero-buffer guarantee. A separate picture showed an NBC Sports Boston upcoming-game promo, not independent proof of the current matchup. |
| PenguPlay PPV.st | Entry and selected variant playlists loaded, but the sampled media playlist had zero segments. | No video proof. The probe now explicitly reports `NoMediaSegments` for an empty sample. |
| PenguPlay AK47 / Nuvio PPV | AK47 playlist declared encryption; Nuvio PPV used fragmented/byte-range HLS. | The bounded probe declines these formats. Neither was decoded. This is a probe limitation, not a blanket Roku incompatibility claim; no DRM/key handling was attempted. |

Highfly and PenguPlay initial default-client media 403s were followed by successful media delivery with the corrected identified client. Nuvio's identified API returned 13 media choices plus a donation link for the same game. Its inspected PPV playlist was not decoded, so Nuvio is not counted as a demonstrated backup here.

### Dependency comparison

Highfly Leaf used `papacito.cfd` for its playlist and `east.papacito.cfd` for segments. StremVerse SportzX used `chatgpt.hereisman.net` and its rotating variant CDN. The pictures showed the same game with different broadcast overlays. These are independently exercised delivery paths with no shared observed gateway in this sample; a different hostname alone cannot establish independent operators or hidden upstreams. No automatic cross-provider switching or opaque-ID matching was added.

PenguPlay Plorax and Highfly Leaf share the Papacito segment service. They can provide alternate add-on frontends, but a Papacito outage may affect both. The old CNCVerse/StremVerse shared-gateway finding also remains valid.

## Exact app defects repaired

1. **Missing singular resource type.** Highfly's manifest declares `sport`, not `sports`. `SportsCatalogs()` previously filtered it out despite successful registration. The page now admits both spellings without rewriting them. Regression tests execute actual registration, catalog requests, Discover selection, original-ID stream requests and the existing resolver for both types, retaining configured path/query data.
2. **Non-video entries in fallback pools.** Highfly returns locked premium options pointing to Google's homepage and a player tip pointing to its `/health` endpoint. The source filter now recognizes those exact destination-plus-annotation shapes as provider status entries. It leaves genuine native sources, `notWebReady`, ordinary movie titles and unrelated hosts alone. The integration test passes a realistic response through the actual store, budgeting, selection and resolver and verifies only the usable candidate survives.
3. **Misleading research failures.** The probe supplies an honest default identity, preserves provider-required overrides case-insensitively, keeps redirect/size/deadline protections, and identifies empty media samples explicitly. Tests cover real request construction and the complete report flow. No native player rewrite or duplicate fresh-link recovery was introduced.

## Simple free setup

### Highfly

1. Open [free US2 setup](https://sportsfree-us2.highfly.dev/configure) or [free EU setup](https://sportsfree.highfly.dev/configure). Use the free flow, complete its normal human verification and choose **Get Addon Link**. The tested US2 page issued a `sports.highfly.to` manifest. Do not substitute a domain or manufacture a configuration path.
2. Copy your generated add-on link privately. No Stremio app/account, payment, subscription or premium trial was required for this test.
3. Use Crimson's existing **Add-ons** import and approve it on the TV. Each import requires separate TV confirmation; dismiss its summary before sending another.
4. Open **Sports → Sports Streams · Basketball → the actual game → a free Leaf source**. Source availability changes. Premium placeholders and the instructional tip are excluded by this patch.

### PenguPlay

The user completed [PenguPlay's normal Google sign-in](https://pengu.uk/). **Sources → Live TV** was initially off; enabling it made live catalogs available. Then use **Overview → Copy Addon URL** and Crimson's usual TV-approved import. The configured profile stays private and is not bundled. No payment or trial was started. Selecting Live TV changed that PenguPlay configuration, not a remote Stremio account.

### Nuvio Live Sports

1. Open [Nuvio's normal configuration](https://nuviosports.xyz/configure).
2. Set **Replay catalog → Hide replays** and **Web Streams → Hide web streams**. Keep the desired live sports enabled. The tested profile kept all live sports and returned **17 catalogs**.
3. Copy the newly generated add-on link privately and import it through Crimson **Add-ons**, approving it on the TV.

The earlier profile returned **74 catalogs** and Roku rejected it with “manifests exceed device budget.” Crimson limits individual manifest arrays, including catalogs, to 64 entries. This was a catalog-count failure, not a playback diagnosis. Using the normal smaller profile fixed this import without relaxing memory limits. Catalog counts can change upstream; do not assume a future profile still fits just because its settings look the same. Hiding web streams excludes browser-only options; it does not prove that every remaining source plays natively.

### StremVerse

Import the public `https://stremverse1.alwaysdata.net/manifest.json` through Crimson **Add-ons** and approve it on the TV. Use its free Live Events catalog; no paid Xtra/IPTV membership was introduced. The sampled NBA failures above still apply even though importing the manifest succeeded.

Do not publish configured manifests in issues or screenshots. Free operation was observed now, not promised forever. Only use broadcasts you are authorized to access; a provider's availability or disclaimer does not establish distribution rights.

## NBA grid / RedZone

The current basketball catalogs returned 20 Highfly, 29 Nuvio and 31 PenguPlay entries. No combined NBA-game listing was identified. Nuvio/PenguPlay channel searches for `multiview` returned none. Nuvio listed ordinary NBA channels and **NFL RedZone**; that is a catalog finding only. No live Sunday RedZone broadcast or simultaneous NBA grid was decoded. A channel named Sports Mix, NBA TV or a browser multiview page is not proof of a single combined game feed. See [the broader combined-feed investigation](SPORTS-NBA-MULTIVIEW.md).

## Validation and remaining acceptance

Local commands: `npm ci --ignore-scripts`, `npm test`, `npm run build`, `python scripts/verify-package.py`, `python tests/probe-live-providers.test.py`, `python tests/probe-live-reliability.test.py` all passed. App suites: **6,616 assertions across 37 harness runs**, **151 cinema-policy assertions**, **50 playlist assertions**, **66 Node test cases**. Python: **7 + 14 cases**. Package: **212 members, 54 XML components, 281 script references, 168 declared interface implementations**. Existing two high development dependency entries remain outside the Roku ZIP; no dependency was added. The PR links the exact tested CI artifact and checksum.

The probe's wall-clock fetch/decode sessions are not real-time rendering or a zero-buffer guarantee. Installation/startup and the limited user-reported playback above are now recorded separately. Sustained 15+ minute playback, audible English, live edge, expired-link recovery, Back/cancel, manual same-game provider switching and unchanged movie/TorBox/next-episode behavior still need controlled physical-stick checks. Keep the PR draft/unmerged. No paid proxy, serverless deployment or mandatory running PC is introduced by the app changes. This follow-up changes documentation only; the app code and cited tested package are unchanged.
