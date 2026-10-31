# Sports reliability investigation — October 29, 2026

**October 30 follow-up:** [configured free-provider tests and fixes](SPORTS-FREE-PROVIDERS.md) supersede the earlier browser/sign-in gates below. Highfly now has two successful 120-second 1080p PC runs. The default research-client identity caused some earlier 403s; native Roku and combined NBA playback remain unverified.

**StremVerse and CNCVerse both delivered the same NHL game in separate PC tests: two fresh two-minute runs per provider at 1280×720 H.264/AAC.** A decoded picture showed Blue Jackets vs Hurricanes with the first-period scoreboard, rather than a holding card. Both providers used the same gateway hostname, so the milestone's **independent delivery backup remains unproven**. No physical Roku or audible-language test occurred.

The investigation also located repeated StremVerse football failures at its entry video playlist, rejected a different CNCVerse source that showed a holding card, and found Nebula HLS failures. Those negative results remain in the evidence; a later successful hockey event does not fix every source or establish broad sports coverage.

This continues draft PR #9 from `f58504b005bdfe26ec8b52829c3f732fd231ecee`. The existing provider-native player and same-provider fresh-resolution logic are preserved. No provider was installed, no Roku setting changed, and no account, subscription, proxy or deployment was purchased or created. Two anonymous configuration profiles were generated through the providers' ordinary free setup processes solely for these checks; their links remain private and are not bundled.

## What is usable in the app

The tested software path is **manual backup-provider browsing**:

1. Import a provider's legitimately generated HTTPS manifest through **Add-ons**, using the existing TV confirmation. Do not publish your configured manifest or send it in a GitHub issue.
2. Open **Sports → provider catalog → event → source**. This uses the provider's original ID and type. Installed `sports` catalogs now appear alongside `tv` and `channel` catalogs; Nebula's real manifest exposed this missing type.
3. To try another provider, press **Back** from playback, then **Replay** on the live Sources screen. Other installed providers appear before the previous provider, which is labelled **Current**. The original event name stays visible.
4. Open another catalog and manually match the **teams, competition and Live/Recorded status**. Pick that provider's own event and source. No opaque ID, source URL or failed-source pool is transferred across providers. A similarly named listing may be a replay or the wrong match.

The shortcut works even when the current provider returns no candidates. It cancels/suspends pending source work, unwinds the existing navigation stack, and ignores stale hidden-screen actions. Normal catalog entry clears the comparison label. Existing Back navigation remains available for remotes without Replay. This is software-tested, not physically remote-tested. No automatic cross-provider matching or failover is claimed.

For the second PC-tested provider, open [CNCVerse Bridge](https://cncverse.dpdns.org/), use its ordinary free profile/configuration and **Copy Addon URL**, then import that private link into Crimson. The tested catalog is **SportzX Live Events**, source **SportzxProvider Auto**. Do not select a donation/browser entry. No Stremio login is required by this path. Catalog naming may change; use the provider's own current descriptors. This is an opt-in technical setup, not a broadcast-rights grant or availability promise. Some StremVerse titles are simply **NHL**: inspect the poster for teams/time before choosing a manual backup; the title alone is insufficient.

## Measured provider results

[Sanitized evidence](research/live-reliability-2026-10-29.json) contains timestamps, event-ID hashes, request-stage/status counts, URL fingerprints and decode measurements. It excludes configured URLs, header values, segments and screenshots. These observations are specific to this PC/network and time; failures do not establish worldwide service failure or a particular cause.

| Provider / check | What happened | What it establishes |
| --- | --- | --- |
| CNCVerse / SportzX — Hurricanes vs Blue Jackets, 23:06–23:10 UTC | Two fresh resolutions, 120.12/121.22 seconds. 27/29 unique segments, 3,780/3,990 video and 6,328/6,797 audio frames; 1280×720 H.264/AAC, advancing playlists/PTS, zero decode failures. Later picture showed the named teams and 0–0, first period 18:30. | Sustained PC delivery of real matching sports footage, separately checked after the holding-card false lead. Audio tags absent; no English or Roku proof. |
| StremVerse — NHL poster identifies Hurricanes vs Blue Jackets, 23:08–23:12 UTC | Its own original ID, two fresh resolutions, 120.23/120.08 seconds. 27 segments each, 3,840/3,690 video and 6,328/6,329 audio frames; same 720p H.264/AAC, advancing playlists/PTS and zero decode failures. Picture showed the corresponding teams. | Demonstrated primary for this event on PC. It shares the gateway with CNCVerse; not an independent CDN outage backup. |
| StremVerse — HB Koge vs Barcelona, 22:35 and 22:38 UTC | Manifest, catalog and fresh stream endpoint returned 200. The selected `live.vivo155.com` **entry HLS playlist returned 403** on two fresh resolutions, then again several minutes later. Same URL fingerprint; supplied Referer/User-Agent preserved. | Failure is before variants/segments, not the add-on response. Normal fresh resolution did not fix this sample. The reason for denial is unknown. |
| StremVerse — Copa del Rey / Sporting Hortaleza vs Sevilla, 22:35 UTC | Two fresh stream resolutions returned 200 with four choices; selected Vivo entry playlist returned 403 both times. | A second event showed the same failure stage. No retry storm, header invention or access-control bypass. |
| CNCVerse / PlayZTV — HB Køge vs FC Barcelona, 22:32–22:37 UTC | Two fresh resolutions of the alternative `live2.jorvakstreamcache.com` source; 122.19 and 120.67 seconds elapsed. Each fetched 33 distinct segments over 29 playlist polls and decoded 3,960 video / 6,188 audio frames, H.264 1280×720 + AAC, zero decode failures. Sequences/PTS advanced. | Sustained PC delivery/decoding of media, **not proof of the match**. A subsequent decoded frame showed a promotional holding card. No English, surround, independent upstream or Roku claim. |
| Nebula Sports — Atlético Mineiro vs Cruzeiro, 22:46–22:48 UTC | Normal free quick configuration issued a manifest. Own `sports` catalog and native stream endpoint returned 200. Selected “Fanatiz” HLS returned entry-playlist 502, then 404 on both later fresh resolutions; no segments. Two later DASH responses returned 200 and contained `ContentProtection`. | Protocol compatibility, not usable backup video. Source name pinned after order changes. No DRM/key processing or browser-to-HLS conversion attempted. |
| Highfly free `.dev` instances | Both configuration pages returned 200 and displayed human verification before issuing a link. No legitimately configured manifest was obtained. | Highfly remains **untested after configuration**, not “universally broken because a bare endpoint returned 403.” |

Earlier StremVerse 288p/1080p PC samples are retained in [the earlier validation](SPORTS-VALIDATION.md). They were short and do not override these later failures. One initial exploratory run selected a changed catalog index; it was excluded from the pinned-event conclusions. The new probe pins the original ID and fails if that event disappears, rather than sampling a different game silently.

The [official Hurricanes schedule](https://www.nhl.com/hurricanes/) listed this matchup at 7 p.m.; no broadcast-latency measurement was made.

### Shared dependencies

For HB Køge, StremVerse's Vivo choice and CNCVerse PlayZTV's Vivo choice returned **exactly the same media URL** in a private comparison. They are not independent backups. CNCVerse's jorvak alternative used a different delivery hostname, but its operator/origin relationship is unknown; a different CDN name is insufficient evidence of independence. StremVerse also credits CNC integrations. No automatic recommendation or priority is inferred from a provider's name.

The successful NHL paths both used `chatgpt.hereisman.net` with rotating variant hosts. Each provider was resolved/decoded independently, but that shared gateway is a concrete common failure point. CNCVerse's other same-game catalogs returned an unusable non-absolute URL or a `no.link` placeholder; the SportzX second source exceeded the playlist response budget. They were not counted as successful alternate media.

An initial NHL probe hit a DNS failure at the variant stage after re-fetching the master on each poll. Inspection showed the master had rerouted from `pl.playlist5.space` to `pl.kamfir5.space`, which did not resolve at that time. The probe now follows normal HLS behavior by retaining the selected variant during a session; each fresh resolution round selects anew. The later four sessions completed. This separates a test-method problem and transient routing failure from the earlier StremVerse entry-playlist 403. No DNS override, alternate IP or denied-access workaround was used. Real automatic native Roku recovery remains untested.

### Other routes checked

- [CNCVerse Bridge](https://cncverse.dpdns.org/) has multiple current native catalogs and a normal anonymous profile flow. The [developer announcement](https://www.reddit.com/r/nuvioaddons/comments/1wxgy1s/live_sports_and_live_tv_channels_on_nuvio_with/) was a lead, not playback proof. Other inspected choices included the same Vivo source, public HTTP DASH links and entries without a usable direct URL. Public HTTP admission was not weakened to make these pass. No upstream resolver code copied.
- [Nuvio Live Sports](https://github.com/rajhodedara/live-sport-plugin) remains maintained according to its source/README, but its hosted configuration was 403 here. No proven alternate hosted instance emerged; no challenge bypass or mandatory self-hosting introduced.
- [Plavio](https://www.reddit.com/r/nuvioaddons/comments/1x3y7x5/plaviohd_multisource_movies_series_live_sports/)'s configuration returned HTTP 402; that status alone is not proof a subscription is required. StreamsPPV's advertised host returned 429; it was not repeatedly hammered. [TvVoo's documented host](https://github.com/qwertyuiop8899/tvvoo) returned 403; its documented token/proxy caveats do not establish a working free Roku backup. USA TV's operator page announced shutdown.
- [Nebula's free setup](https://sports.nebulapro.xyz/sports) was followed normally. Supporter channels and browser DRM/key-handling were not used. A successful configuration is not successful video.
- Additional current leads: [PenguPlay's sports announcement](https://www.reddit.com/r/nuvioaddons/comments/1wjrgpz/penguplay_super_quick_update/) led to `pengu.uk`, which returned 403 to this PC request (the web reader could see its notice page). Nuvio's formerly advertised Render manifest returned 404, and a community-hosted manifest returned 403. These are dated access results, not universal service verdicts.

## Highfly: exact remaining step

Open either [free EU configuration](https://sportsfree.highfly.dev/configure) or [free US2 configuration](https://sportsfree-us2.highfly.dev/configure), complete its human verification, and retain the issued manifest privately. The task's browser-control tool reported **“Local browser use is disabled in Work settings”** for Chrome and the in-app browser, so it could not operate or inspect this step. No challenge was bypassed, and no setting was changed to evade that restriction. Enable browser control and complete any human-only verification, or use the issued link directly in Crimson's Add-ons setup.

The operator's configuration FAQ says free playback is offered and premium CDN backups are separate. Its suggestion to try another source/wait for backend recovery is guidance, not a measured fix here. [The operator's domain-migration announcement](https://www.reddit.com/r/nuvioaddons/comments/1wig7l4/addon_sports_streams_update_domain_change_nba_soc/) predates these successful `.dev` configuration responses. Neither a historical domain notice nor an unconfigured manifest response establishes current configured playback.

Once a valid manifest exists, the remaining evidence is specific: its own catalog and IDs, an overlapping live event, fresh stream responses, playlist and segment delivery, sustained decode, and a picture check that confirms the named game. Shared origin/CDN dependencies must then be compared with the primary. If no overlapping game is live, a clearly identified live sports channel is a narrower interim test, not league-coverage proof.

## Reproduce without publishing private settings

Keep a private JSON file in ignored `verification/`:

```json
{
  "manifest": "https://PROVIDER/PRIVATE-CONFIG/manifest.json",
  "catalog": "EXACT_CATALOG_ID",
  "type": "tv",
  "event_id": "EXACT_ORIGINAL_EVENT_ID",
  "source_name": "EXACT_UNIQUE_SOURCE_NAME"
}
```

Use the actual manifest's type, including `sports` where declared. `source_index` is an alternative when no stable unique name exists; indices can reorder and require explicit review. The event is always ID-pinned. The configured path/query and provider-supplied request headers are retained during requests, never written into the report.

```text
python scripts/probe-live-reliability.py --profile-file verification/PRIVATE.json --seconds 120 --rounds 2 --decode --output verification/RESULT.json
python tests/probe-live-reliability.test.py
```

Optional `--decode` uses a separately installed PyAV (19.0.2 in these checks); it is not a project/runtime dependency or included in the Roku ZIP. Without it, only delivery is measured. Default checks have two fresh resolutions, bounded requests and pauses, 256 KiB playlists, 8 MiB segments, 32 MiB decode batches and 256 MiB total media per session. Public destinations are checked, credentials in URL authority rejected, and sensitive headers removed on cross-host redirects. No cookie extraction, proxy, browser resolver, DRM handling or challenge solver exists. This probe currently declines encrypted, fragmented/byte-range HLS and DASH; that is a probe limitation, not a blanket Roku limitation.

Thirteen deterministic Python tests cover production request/resolve/sample/report flow: fresh resolution, reordered/removed IDs, provider path/query/header retention, stage-specific failures and recovery, source ambiguity, malformed data/budgets, media classification, redaction, bounded polling and the distinction between decode success and content verification. App regressions execute the actual Sports/Discover/Scene/ScreenStack/source resolver boundaries. Full package results are recorded in [validation](SPORTS-VALIDATION.md).

## Hardware acceptance after delivery is established

No physical Roku test or installation occurred. Use the exact successful CI artifact linked in PR #9 when ready. On the actual stick: test primary/backup startup, 15+ minutes of the named live event, renewal after link expiry, failures/Back during loading, manual switching to the same event, live edge and audible audio. Confirm neither provider switch nor late results interrupt accepted playback, live viewing creates no movie resume/next episode, and movies/TorBox/episodes still work. A PC decode result cannot certify these conditions.
