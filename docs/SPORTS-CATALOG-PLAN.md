# Sports catalog cleanup — 0.6.1

**Implemented in source; physical Roku testing of this interface is outstanding.** This follows the plan recorded with merged PR #9. The earlier user-reported NBA playback succeeded on 0.6.0 and does not certify this newer interface.

## Use

**Sports → sport → game/event → Watch.** Watch uses the existing automatic source selection and same-provider recovery. **More sources** opens explicit provider choices and the existing manual stream picker. **Browse by provider** keeps original catalogs accessible; the first filter also offers separate ESPN schedules.

Categories cover basketball, American football, soccer, baseball, hockey, MMA/UFC, boxing, motorsport, tennis, golf, cricket, rugby, wrestling, volleyball, cycling, darts, snooker/pool, esports and channels. Only categories represented in installed catalog descriptors appear. Mixed or unrecognized catalogs stay under **All / other sports**. This organizes existing providers; it does not add broadcast coverage.

Each category loads matching catalogs first, then mixed catalogs whose returned metadata identifies that sport. Provider-reported status appears beside each listing; missing status stays unverified. No team-name guessing or ESPN-ID substitution is used. Unknown categories remain accessible in mixed/provider browsing.

Select an event for two actions:

- **Watch:** request fresh sources from that event's primary provider and use existing native automatic selection. It does not guarantee the first stream works or switch automatically to another provider's event.
- **More sources:** choose a confidently matched provider route and then a stream manually, or browse another provider and locate the same event yourself.

Known upcoming/postponed events do not automatically launch a live source. Playback: Recorded retains the existing metadata/Details path. Live audio preferences, movie/show playback, TorBox, voice, subtitles, source recovery and next episode use their existing implementations.

## Matching and privacy

Exact duplicate appearances of one provider's native ID/type are folded. Cross-provider grouping requires the same normalized participant title, explicit UTC start time, competition and known phase. Different dates, competitions, participants, replay/live states, postponements or missing fields keep listings separate. Native IDs, declared types and configured addresses remain attached to each route, including private paths/query parameters. Matching changes presentation, never rewrites those identifiers.

Providers often omit the required evidence. Duplicate-looking games can therefore remain visible with different provider names. A similar title alone is insufficient evidence to route playback to a different event. This implementation does not claim full alias matching, verified live status or independent upstream delivery.

No profiles, temporary media URLs or account credentials are added to the repository, package or public UI. No new provider, account, subscription, proxy or hosting service is installed.

## Bounds and failure handling

- The 40-catalog cutoff is removed. Provider browsing renders 48 catalogs per page with previous/next navigation.
- One catalog worker is owned until its finished notification, including across Back/category changes. Empty/duplicate/stale result events cannot release a running slot or paint another category/account. Covered screens launch no new catalog work.
- Requests use existing CatalogStore URL assembly/validation, a 10-second request deadline and the existing 1 MiB transport response limit. Normalization runs in a Task and returns at most 48 records with bounded fields. Oversized native IDs are rejected rather than truncated.
- Event pages render 48 listings. A batch retains at most 240 original routes; queued catalogs and further pages remain available through More events. A new batch releases older records, which remain available through original provider browsing. There is no session-long accumulated event history.
- Raw pagination offsets include malformed records. Manifest page-size hints and explicit end markers are respected. Catalogs without declared skip are freshly fetched and sliced locally; a paginated provider returning the same first ID switches to bounded local slices of a fresh page-zero response instead of looping.
- Failed catalogs expose retry while keeping usable results. Worker launch failure and finished-without-result are failures, not successful empty catalogs. Completed empty responses show an empty state. Interactive return refreshes a retained event list after 30 seconds; there is no periodic fetch behind playback.
- Catalogs requiring a genre choice remain accessible through original provider browsing instead of issuing an invalid unfiltered request.

## Verification

`node tests/sports.test.js` executes actual AddonsStore → CatalogStore → SportsCatalogTask → Sports screen callbacks → Scene/source request boundaries, with injected network and native-node seams. Coverage includes grouping, private URL retention, Watch/manual choices, original IDs/types, conservative matching, malformed/raw offsets, non-paginated slices, ignored skip, failure/retry, stale/duplicate callbacks, Back, hidden screens, account/registry invalidation, batch limits, later catalogs, recorded routing and refresh.

The PR records full-suite, build and package results and links the tested CI artifact. These tests do not measure Roku rendering speed, audible sound or sustained decoding.

Physical acceptance: browse representative installed sports, open an event and Watch, use More sources, traverse multiple pages, Back during loading, retry an unavailable provider, return after playback, and check an existing movie/show plus manual next episode. Record provider/source, duration and actual behavior separately from metadata labels.
