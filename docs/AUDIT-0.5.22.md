# Crimson Cinema 0.5.22 audit and repair evidence

Audited 2026-10-15 from the freshly fetched default `main`, commit `bcd32111d9b0996b35285b1a684513d88f66b0c1`. Changes are on `fix/stremio-account-sync`. This report describes a software-validated experimental update, not hardware certification.

## Verdict and scope

The missing-account-add-ons report has reproducible client-side causes. One bad or duplicate descriptor could abort the whole collection; a finished notification could discard an available result; catalog discovery and refresh also had gaps. These are repaired without silently adding catalog providers. Existing account isolation, registry acknowledgement, playback recovery and resource limits were traced and regression-tested. Additional account-write defects were repaired.

No personal credentials, authenticated Stremio collection, tester account, live Roku, subscription or movie stream was accessed for this audit. The tester's actual server response is therefore **unverified**. The app now exposes safe received/imported/rejected counts so a real account can distinguish an empty collection from a failed request or unsupported entries. A missing stream alone does not establish that TorBox needs renewing: missing configuration, provider failure, unavailable direct URLs, quality/language filters and subscription state are separate possibilities.

## Root causes and before/after evidence

| Finding | Before on latest main | Repair and regression evidence |
|---|---|---|
| Whole collection rejected | `ReconcileAccount` returned on the first malformed, unsupported or duplicate descriptor. Fresh Stremio profiles have no automatic catalog seeds, so usable neighbours disappeared too. | Validate entries independently; adopt supported providers with explicit partial counts. Infer removals only from a complete valid snapshot. New store reproductions failed 14 assertions before repair, including expected 3 imported providers versus 0. These now pass. |
| Configured instances collapsed | Manifest ID was the storage identity. Two different configured URLs with the same ID collided, and a local-only same-ID provider could disappear. | Distinguish public manifest ID from stable internal identity; use an opaque SHA-256 suffix on collision. Preserve paths/queries unchanged in private state. Test exact duplicates, two configured instances, reorder/reload and local-only ownership after an empty snapshot. |
| Completion ordering | `onAddonSyncFinished` reaped a true finished task without first consuming an existing result. | Either observer consumes an available result once. Empty/false initial notifications wait; duplicate and stale events are rejected. Test finished-before-result dispatch through the actual worker and scene callbacks. |
| Catalog admission | Search required `catalog` in manifest resources, although Stremio derives catalog support from declared catalogs separately. Catalog-only manifests with empty resources were rejected. | Accept valid declared catalog lists independently; malformed catalog entries remain invalid. Tests drive imported descriptors into actual Search and Discover source controllers. |
| Stale screens | Home/Search/Discover compared sorted addresses only; changed catalogs/resources or account order at unchanged URLs were invisible. Sync refreshed only Home and subtitles. | Compare ordered descriptor signatures and invalidate every catalog consumer. Tests change catalog contents at the same URL and reorder providers for all three signatures. Hidden Search retains its requested query while awaiting a refreshed source set. |
| Unsafe outbox restoration | Sync fault cleanup called `RestoreAccountWrites`, potentially replacing newer intent with an older durable copy. | Restore at startup/session reconciliation only. Production fault-cleanup regression preserves a newer edit over an older stored edit. |
| Uncertain write supersession | Failed in-flight writes were discarded when superseded, allowing a same-title replacement to proceed without reconciliation. Later coalescing could also remove a failure block. | Keep the latest intent blocked for that title until explicit retry obtains a fresh baseline. Unrelated titles proceed independently. Actual account pump tests cover held A plus B/C, failures, restart, coalescing and fresh-baseline retry. |
| Login completeness | Link pairing reported success even when `getUser` failed. Polling counted sleeps rather than actual elapsed time. | Require successful identity lookup, bound elapsed pairing time with a monotonic clock, and report failed session persistence. Tests execute the real link-code worker with valid and failed identity responses. |
| Retry and LAN permission | Device persistence retried indefinitely; any native LAN client could forge browser headers while Add-ons was open. | Retain dirty state with three automatic timer rounds plus manual device-save retry. Require explicit TV confirmation within 60 seconds for browser imports, including session/open-screen checks and expiry cleanup. |

Implementation: [AddonsStore](../source/stores/AddonsStore.bs), [StremioApiStore](../source/stores/StremioApiStore.bs), [AddonSyncTask](../components/AddonSyncTask.brs), [MainScene](../components/MainScene.brs), [AccountWork](../components/AccountWork.brs), [AccountAddons](../components/AccountAddons.brs), [SetupImport](../components/SetupImport.brs), and the Home/Search/Discover/Add-ons/Settings screens. The new integration harness is [account-sync-flows.test.js](../tests/account-sync-flows.test.js); store regressions are [account-sync-stores.test.brs](../tests/account-sync-stores.test.brs).

## Account/API and catalog contract

The official core serializes `AddonCollectionGet` with `authKey` and `update`, and expects a result containing an `addons` descriptor array. The app uses the long POST request path, preserves descriptor boundaries for validation and returns safe aggregate counts. It does not fetch a replacement default catalog to disguise a failed collection. It never calls a remote add-on collection setter.

References: [Stremio request definitions at inspected core commit](https://github.com/Stremio/stremio-core/blob/719ac32f9ab63c8b29fb7466935936cc946f1b33/src/types/api/request.rs), [collection response schema](https://github.com/Stremio/stremio-core/blob/719ac32f9ab63c8b29fb7466935936cc946f1b33/src/types/api/response.rs), [manifest contract](https://github.com/Stremio/stremio-addon-sdk/blob/master/docs/api/responses/manifest.md), and [descriptor format](https://github.com/Stremio/stremio-addon-client/blob/master/README.md). These establish expected formats, not the contents of the tester's private account.

Add-ons shows loading, complete, partial, failed, truly empty-account and unsaved states. Counts distinguish imported, exact duplicates, unsupported transports, invalid descriptors and device-budget exclusions. Complete snapshots replace changed account configurations, apply order and remove absent account-owned records. Partial snapshots retain previously installed providers; local-only records survive both cases. A full registry can leave an imported collection usable only for the current session; that is reported as unsaved, never durable success.

When catalogs are absent, **Add movie and show catalogs → Cinemeta · only on this Roku** is explicit opt-in. Tests execute the real row builder and selection path, assert no hidden provider installation during rendering and verify only the requested local manifest is queued. It supplies metadata/search, not stream access or a subscription.

## Data integrity and playback audit

Account-scoped registry keys and generation tokens already existed in latest main. Tests now follow actual login/StoreHost switching with a held A response delivered after B login, then repeated production logout/login and session reconstruction. A data never enters B's store or task slot. Pending edits are keyed by title and kind; full-item writes wait for a server baseline, require HTTP plus application acknowledgement and retain failures. POST failures are not automatically replayed.

Registry writes and flushes are acknowledged through `RegistryIO`; independent failures retain dirty state and prior durable buffers. The conservative whole-registry budget is 30 KiB uncompressed, with Roku's native compressed limit still authoritative. Playback checkpoints remain dirty-only every 30 seconds outside native Video observers; accepted progress survives recovery and failed replacements. Termination before an acknowledged checkpoint can still lose recent progress. A permanent storage failure or logout with unsynced edits cannot guarantee preservation of every edit.

The source screen still has two shared request workers, Start sooner/Compare providers, provider priority, 48-card pagination, UHD/all filters and per-title count/serialized-byte budgets. Full pool construction/ranking occurs in `SourceSelectionTask`. Early-pool failure resumes queued discovery or refreshes exhausted discovery, excludes already-attempted delivery URLs and retains the checkpoint, with at most two automatic recovery rounds. Recovery tests route through the real player/coordinator callbacks and select the working queued-provider candidate rather than repeating the failed pool. Successful playback is not replaced by late results.

Decoded-response acquisition uses temporary files with endpoint-specific size checks before reading/JSON parsing, plus nesting limits. Stream fields/candidate counts and merged subtitles are bounded. Oversized response files, huge fields and thousands of subtitles are covered with deterministic boundary doubles. Temporary files can overshoot between polling checks; these limits do not bound every native allocation or prove a device crash threshold.

English recovery, projector/surround preferences, online-subtitle opt-in, voice wiring, native controls, next episodes and source memory remain covered by the existing production callback/policy suites. A 4K label is a selection hint. Encoded dimensions, current-file native playback information and audible output remain separate evidence.

## Validation and publication

Run from the repository root:

```text
npm ci --ignore-scripts
npm test
npm run build
python scripts/verify-package.py
python scripts/release-provenance.py
npm audit --json
```

Exact final results and counts are recorded in [VALIDATION.md](VALIDATION.md). Secret-pattern/content review covers public working files, reachable historical blobs and ZIP members without printing candidate values. Package verification checks root manifest/version, integrity, safe paths, XML/interfaces/artwork, exclusion of development files and license presence. Upstream MIT attribution, fonts/third-party licenses and lawful-use wording remain.

Publish the exact ZIP from the successful CI run for the final branch commit, with its SHA-256, package-check and provenance files. Do not rebuild it for release publication. Release remains an experimental prerelease. No live deployment or Roku settings change is part of this audit.

Still required for stable status: authenticated-account confirmation of the received collection; clean install and upgrade on hardware; full movie endurance; consecutive episodes; repeated seeking and navigation; Back during native loading; expired-source recovery; memory measurements; audible English/stereo and AX700 surround over the actual HDMI route; sustained UHD/HDR evidence. Software tests cannot certify those outcomes.
