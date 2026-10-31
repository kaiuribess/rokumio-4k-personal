# NBA multiview: find a combined feed first

**October 30 follow-up:** [configured free-provider tests and fixes](SPORTS-FREE-PROVIDERS.md) supersede the earlier browser/sign-in gates below. Highfly now has two successful 120-second 1080p PC runs. The default research-client identity caused some earlier 403s; native Roku and combined NBA playback remain unverified.

Investigated October 30, 2026 (Pacific; October 31 UTC). This follows the user's preference for **one video containing multiple simultaneous games**, rather than making the Roku decode several separate feeds.

**No usable free, precombined NBA game feed was established.** No multiview option, placeholder channel, provider installation or player replacement was added. The existing provider-native Sports path and manual backup selection remain intact. This is a bounded negative search result, not a claim that no such broadcast exists anywhere.

## What would work with the existing design

A provider can combine the pictures upstream and deliver an ordinary compatible live video. Crimson would then decode one video through its existing player. That avoids requiring multiple local decoders or a running PC. Codec, transport, headers, link renewal and delivery still need validation; a grid image or successful catalog response does not establish playback.

The provider controls the games and layout. Selecting a quadrant cannot recover its original full-resolution picture. Independent game audio would require usable audio tracks from that provider; it cannot be assumed from a mixed feed. A 1920×1080 2-by-2 composition gives each equally sized tile at most 960×540 pixels before borders, not four 1080p pictures.

## Checks and results

[Sanitized catalog and page observations](research/nba-multiview-2026-10-30.json) contain no configured manifest paths, credentials, media links, header values or video files.

| Lead | Direct observation | Result |
| --- | --- | --- |
| StremVerse, CNCVerse and Nebula | Twelve selected current free catalog requests; ten returned 856 entries in total, including duplicate events across providers/catalogs. Two CNCVerse catalog requests failed. Returned titles/descriptions had no matches for the checked multiview/mosaic/NBA-mix terms. NBA game listings were present. | No advertised combined NBA candidate in these responses. Only the selected first pages were inspected, not every possible catalog or hidden configuration. Listing NBA games does not prove their video works. |
| StremVerse's generic NBA cards | Seventeen entries named only NBA also had empty descriptions at their own metadata endpoints. All seventeen posters were downloaded and visually inspected: each advertised an individual two-team game, with duplicate provider listings. | No hidden multiview listing established from those ambiguous names. Posters prove only the advertised matchup, not delivered video or accurate live status. |
| [PPV](https://ppv.st/multiview), following community multiview reports | The normal public catalog returned 158 entries across eleven groups, including Bulls/Celtics and Lakers/Warriors. No combined-feed name/description match. Its public multiview component creates a separate player for each cell, with per-cell source and mute state. | A functioning website feature does not supply a single combined video for Crimson. No combined-media candidate to decode. |
| [TimStreams](https://tim-streams.com/multiview) | Public channels API returned 219 channels; live/upcoming returned 23 events. No combined-feed metadata match. The public client code maps selected streams into separate iframe cells, with layouts up to nine slots. | Browser composition, not a precombined HLS feed. NBA TV and individual NBA match listings are present; neither establishes a multi-game video. |
| [PenguPlay](https://pengu.uk/), from recent developer/community posts | Setup HTML now returns 200. Its normal authentication-configuration endpoint initially returned 403 to a minimal client, then returned `required: true, available: true` with the frontend's ordinary User-Agent/Referer context. | Current configuration requires sign-in. No account created, token extracted, auth gate skipped or manifest fabricated. This is more specific than the earlier homepage-denied observation. No catalog or combined video validated. |
| [NBAMONSTER multiview](https://nbamonster.com/multiview/) | Public HTML contains four `iframe.skmv-frame` elements titled Stream 1 through Stream 4; the page describes desktop multiview. | Browser composition of separate players. No single combined media endpoint established; the page cannot be passed to Roku Video. |
| [BuffStreams multiview](https://buffstream.pk/multiview) | Public HTML contains a source-specific `iframe.se-multiview-iframe` within its tile grid. | Another browser-player route, not evidence of one combined video. Embedded scripts were not executed and access challenges were not bypassed. |
| [iptv-org sports](https://iptv-org.github.io/iptv/categories/sports.m3u) and [US](https://iptv-org.github.io/iptv/countries/us.m3u) listings | 464 and 1,494 channel-name entries respectively, with overlap between lists. Both contained NBA TV; neither had a multiview/mosaic/game-mix/split-screen/CrunchTime name match. | Names only were examined. NBA TV is not proof of simultaneous NBA games. No stream or redistribution authorization inferred. |
| [DIRECTV Mix channels](https://www.directv.com/insider/multiview-mix-channels/) | The operator documents a League Sports Mix containing MLB Network, NBA TV, NFL Network and NHL Network within its packages. | Real combined-channel concept, but not a free Crimson endpoint or an NBA-only multi-game guarantee. No paid account, stream extraction or deployment attempted. |
| [NBA CrunchTime](https://www.nba.com/news/nba-crunchtime-how-to-watch-nba-app) | The NBA's free-whiparound announcement covers 2024–25, not a verified current split-screen feed. | No current reusable endpoint established. Do not substitute historical availability for this season's evidence. |

Searches also covered current Reddit discussions, public GitHub projects, NBA Game Mix and mosaic terminology. Leads describing a multi-player app, old satellite lineup or historical service were not counted as working media. Highfly remains behind the normal configuration/human-verification step documented in [the reliability investigation](SPORTS-RELIABILITY.md#highfly-exact-remaining-step); its configured catalog has not been ruled out or validated.

The follow-up specifically prioritized community providers after the user clarified the scope. Leads included the [current free-addons thread](https://www.reddit.com/r/nuvioaddons/comments/1xbgt60/mega_thread_of_addons_working_only/), [PenguPlay's sports update](https://www.reddit.com/r/nuvioaddons/comments/1xdt6it/penguplay_announcements/), [reported PenguPlay upstream failures](https://www.reddit.com/r/nuvioaddons/comments/1x2u1zd/penguplay_live_sports_binged_streams/), and [a multiview discussion](https://www.reddit.com/r/StremioAddons/comments/1j9xu6j/). Those posts guided real configuration/catalog/client-code checks; popularity and screenshots were not treated as media proof. WatchSports and BINTV public pages supplied no combined-feed lead in the inspected page/client material; their individual game playback was not tested in this multiview search.

### Free sign-ups and the remaining configuration gate

The user permits free sign-ups for further verification. PenguPlay's developer describes a free add-on, but its required Google sign-in has not been completed here. Highfly's current [free EU](https://sportsfree.highfly.dev/configure) and [free US2](https://sportsfree-us2.highfly.dev/configure) pages distinguish the free tier from paid Premium and a separate seven-day Premium trial. The trial is not the proposed free solution. These pages require human verification before issuing the free manifest; neither establishes an NBA multiview catalog entry.

A fresh Chrome setup attempt again returned **Local browser use is disabled in Work settings**. Browser access was requested from the user; no alternate UI tool or authentication bypass was used. No sign-up, payment, trial activation or installation occurred. After normal setup, confirm the required feed is included in the actual free account and test it. A free account alone does not establish video availability, and current free pricing cannot guarantee the operator's future terms.

## Why not build local multiview first?

The user's previously recorded device is **3830RW**. [NBA's current supported Roku list](https://support.watch.nba.com/hc/en-us/articles/26849702436247-Multiview), updated October 6, lists 3940/3941 and 3820/3821 for two games and 4850R for four. It does not list 3830. This is the NBA app's support statement, not proof that every other implementation is impossible. Crimson currently owns one native Video node, and no supported, physically validated multi-decoder implementation for this stick has been established here.

A combined feed is therefore the preferred investigation path. A locally or cloud-hosted compositor would change the no-PC/no-mandatory-hosting requirement. A free hosting allowance is not evidence of free sustained multi-feed decoding, encoding and video delivery.

## Acceptance before adding a channel

1. Find an authorized provider's own current catalog entry for a combined feed; retain its original ID/type and private configuration. Do not invent a mix from another provider's opaque event IDs.
2. Resolve its direct media normally. Preserve legitimate headers/query parameters and refresh expired links; respect authentication, territory restrictions and DRM.
3. Verify playlist **and segments**, sustained PC decoding, and decoded pictures with at least two identifiable NBA games shown simultaneously. Exclude holding cards, scores-only grids, highlights and sequential whiparound from a simultaneous-games claim.
4. Repeat a fresh resolution and a bounded recovery test. Record shared upstream dependencies honestly.
5. On the physical Roku, verify sustained playback, sound, live edge, Back/cancellation and existing movie/episode behavior. None of these hardware tests occurred in this investigation.

The exact missing piece is a legitimate, renewable combined NBA video source, not another schedule screen. No native app code changed for this research update. The existing tested CI install package remains linked in draft PR #9; this document does not certify multiview or broaden its proven sports coverage.
