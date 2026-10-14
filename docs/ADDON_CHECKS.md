# Find an add-on problem

Open **Add-ons → Check add-ons**, or **Settings → Add-on checks**. Each installed add-on gets a named row. Use Up/Down for details, Play/Pause to repeat the check, and Back to cancel/return. No video is played and no account or stored configuration is changed.

The check requests each configured manifest in sequence. Requests have an 8-second deadline; the screen has a 120-second overall deadline. Results are connection/setup observations at that time, not a continuous service monitor.

| Result | Meaning and next step |
| --- | --- |
| Manifest reachable | Valid matching manifest loaded. Read the advertised roles. A catalog or subtitle add-on normally does not supply streams. Account entitlement and playable titles remain untested. |
| Access denied | HTTP 401/403. Privately check the configured link and provider account. |
| Not found | HTTP 404. Check for an outdated manifest or endpoint. A title-specific 404 may mean that title has no source. |
| Rate limited | HTTP 429. Wait before repeating requests. |
| Provider unavailable | HTTP 5xx. Provider/server failure; try later. |
| Timed out / Connection failed | Request deadline or Roku network failure. Check the connection and retry. This does not prove a permanent provider outage. |
| Invalid / changed manifest | Missing required manifest structure or an identity that differs from the installed add-on. Reimport the provider's current configured manifest privately. |
| Missing setup | No configured address was stored. Add the manifest again. |
| Not finished | The overall deadline ended before that row completed. Retry; it is not evidence that the add-on is broken. |

## When a movie already plays

An installed add-on can supply only catalogs, metadata or subtitles. If another add-on supplies the working stream, that is normal. Check which add-on and function were expected to work before reporting a failure.

On the source screen, Left/Right changes provider. The status below its name distinguishes a pending request, safe error category, empty response, filtered sources and returned choices. A partial failure is visible even when a different provider has usable sources. An empty response for one title does not establish a broken add-on. Account/service clips and pending downloads are reported separately from playable choices.

## Share a useful report safely

Use the repository's **Add-on problem** issue template. Include the public add-on name, app version, Roku model/OS, affected stage, safe status category/code and whether another provider plays. For playback, include the source's container, video/audio codec, language and connection route if known.

Do not share your configured manifest, source URL, API key, provider password, private account identifiers or device logs containing them. The new check screen uses fixed result messages and safe display names; a provider name that looks like an address or opaque token is replaced with “Add-on N”. Other screens or provider-supplied metadata can still contain private information, so review screenshots before posting.
