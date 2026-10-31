# All-sports catalog cleanup — planned

**Status: requested next pass, not implemented in the current 0.6.0 package.** This records feedback for draft [PR #9](https://github.com/kaiuribess/rokumio-4k-personal/pull/9); it does not change the player or promise additional event coverage.

## Problem and intended experience

After successfully playing an NBA selection on Roku, the user reported having to scroll through many catalog and source choices. The requested cleanup applies to **all available sports**, not only basketball.

Target flow: **Sports → sport or league → game or event → Watch**.

Keep ordinary browsing focused on recognizable sport, competition and event names. Put alternate providers and backup streams under **More sources**, retaining an explicit provider-browsing route when event identity is uncertain. Source choices should show concise useful distinctions such as provider, reported quality and known language; an unverified label must remain unverified.

## Proposed scope

- Organize the installed providers' catalogs by sport/league, with a clearly named Other sports area for unknown categories. Cover NFL, NBA, MLB, NHL, soccer, college sports, UFC, boxing and other competitions only when installed providers actually supply them.
- Show one event entry only when duplicates can be matched confidently. Compare participants, competition, start time and live versus replay status; handle postponements and ambiguous names conservatively. Keep uncertain entries separate and identify their provider.
- Offer a primary Watch action for an eligible source, with More sources for explicit alternatives. Do not hide useful backup choices or claim the selected source is guaranteed to work.
- Distinguish upcoming, live, replay and unavailable entries only when the evidence supports that status. A schedule entry or catalog label does not establish playable video.
- Preserve provider-native IDs/types and fresh source resolution. Never send one provider's opaque ID to another, silently switch to a different game, or disturb successful playback because more results arrive.
- Reuse the existing player, same-provider refresh/recovery, pagination, bounded loading and remote navigation. Preserve movies, shows, TorBox, audio settings and manual next episode.

## Acceptance for the future implementation

1. Users can find an available event in each represented sport without scrolling through every provider catalog first; unknown categories remain accessible.
2. Watch and More sources both reach the existing source/player path with the selected provider's original event ID/type. No mock or browser-page source is presented as working video.
3. Tests cover matching and deliberate non-matching: same teams on different dates, different competitions, postponed events, replay versus live, missing times and opaque IDs from different providers.
4. Back/cancel stays responsive while catalogs or sources load. Repeated browsing remains bounded on the stick, and all alternatives remain reachable through pagination.
5. Hardware checks cover representative available sports, a failed primary source, manual same-event backup selection and the existing movie/series path. Report measured results separately from user feedback and PC tests.

The current working provider-native integration stays in place until this pass is implemented and validated. No new provider installation, account, payment or hosting service is part of this documentation change.
