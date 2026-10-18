# Add-ons: a simple setup guide

**Crimson Cinema is the Roku player. Add-ons supply its browsing lists, movie/show information, playable links and subtitles.** Connect the providers you want once, then browse, search and play with the Roku remote. A phone/computer is useful for setup; it does not need to stay on for compatible direct playback.

Install the app first using the [Roku installation guide](INSTALL.md). Each person configures their own providers. No streaming account, service key or playable movie library is included in the download. Use sources and content you are authorized to access.

## What do I need?

| Part | What it does | Simple starting choice |
| --- | --- | --- |
| Catalog and metadata | Posters, search, title information and episode lists | Cinemeta; optional TMDB for more browsing rows |
| Stream provider | Finds playable video links for the selected movie/episode | Your compatible direct-HTTPS provider; Comet with your own TorBox account is one optional setup below |
| File-delivery service | Hosts/delivers files used by some stream providers | TorBox for the Comet/TorBox example; its subscription is separate |
| Subtitle provider | Adds caption choices | OpenSubtitles v3, if wanted |

**A catalog does not unlock movies.** TMDB, Cinemeta and Streaming Catalogs do not supply movie streams. Finding a title in Search is separate from finding a playable source. Comet is a connector, not a free TorBox subscription.

Start with one catalog/metadata provider and one compatible stream provider. Check what is already installed before adding duplicates; more add-ons can repeat the same results and take longer to search.

## 1. Choose your profile

For a standalone setup, select **Browse movies & shows** to use the **Local profile**. Stremio sign-in is optional.

Already using Stremio? Choose **Connect Stremio**, or **Settings → Connect Stremio**, and complete the on-screen pairing privately. Supported account catalogs, metadata, stream and subtitle add-ons import automatically after login and on relaunch. In **Add-ons**, wait for the sync result; **Sync Stremio add-ons** retries a failed or partial import. A slow account request can take up to two minutes.

“Your Stremio account has no add-ons” means a completed empty collection; an error or partial result means something different. Read the counts/status before manually reinstalling everything. If the account truly has no catalog, choose **Add movie and show catalogs → Cinemeta · only on this Roku** when offered. That explicit local option does not change your remote Stremio account.

Local and Stremio profiles keep separate add-on collections. **Choose the profile you intend to use before importing.** Manual imports are not uploaded to your remote Stremio account.

## 2. Import an add-on from your phone/computer

1. Open **Crimson Cinema → Add-ons** on Roku and leave that screen open.
2. Put your phone/computer on the same local network. Open the **exact setup address displayed on the TV**, including its port. This is the add-on setup page, separate from Roku's developer installer.
3. Paste the provider's complete configured **HTTPS manifest link** and click **Install**. Use its `manifest.json` link, not its configuration webpage or a `stremio://` app-launch link. Keep every configured path/query character intact.
4. On the TV, choose **Allow import** within **60 seconds**. Only approve a request you just sent.
5. Read the final TV result, such as **“1 add-on added.”** or **“Add-ons already installed.”** The browser's **“Sent”** page only means the confirmation was queued.
6. Press **OK** to close the result. Leave Add-ons open before sending another add-on.
7. Open **Add-ons → Check add-ons**. A reachable manifest confirms setup; try a movie/episode separately to check actual playback.

Keep configured links private: some contain service keys in their path, query or encoded settings. Do not paste them into GitHub issues, screenshots or public chats. Use your own account; do not share someone else's configured manifest.

## 3. Add browsing: Cinemeta or optional TMDB

**Cinemeta** normally exists in the Local profile already. If missing, use the local catalog option above when offered, or import this public manifest:

```text
https://v3-cinemeta.strem.io/manifest.json
```

**TMDB** is an optional account-free catalog for Latest Releases movies and Trending movies/shows. This public preset includes English metadata and IMDb-compatible movie/show/episode identifiers, which help it work with IMDb-based stream providers. Copy the entire single line into the setup page:

```text
https://tmdb.elfhosted.com/%7B%22provideImdbId%22%3A%22true%22%2C%22returnImdbId%22%3A%22true%22%2C%22language%22%3A%22en-US%22%2C%22catalogs%22%3A%5B%7B%22id%22%3A%22tmdb.latest%22%2C%22type%22%3A%22movie%22%2C%22showInHome%22%3Atrue%7D%2C%7B%22id%22%3A%22tmdb.trending%22%2C%22type%22%3A%22series%22%2C%22showInHome%22%3Atrue%7D%2C%7B%22id%22%3A%22tmdb.trending%22%2C%22type%22%3A%22movie%22%2C%22showInHome%22%3Atrue%7D%5D%7D/manifest.json
```

This preset contains **no account or API key**. It enables three browse catalogs plus the provider's search catalogs. For custom options, see the [TMDB configuration page](https://tmdb.elfhosted.com/configure/) and [upstream project](https://github.com/mrcanelas/tmdb-addon). Both `provideImdbId` and `returnImdbId` are enabled in the preset; changing to incompatible IDs can leave a title with no matching streams.

Use **Movies**, **Shows**, **Browse/Discover** or a row's **See all** to browse beyond Home's compact previews. On Home, **Play/Pause** refreshes catalog rows. These rows describe titles; they do not establish current source availability or 4K quality.

## 4. Optional streams: Comet with your own TorBox account

This is an account-backed option, separate from free catalogs. Check [TorBox's current plans](https://torbox.app/pricing) before buying; no plan guarantees every title or uninterrupted UHD.

1. Open [Comet's public configuration page](https://comet.elfhosted.com/configure).
2. Choose **Add Debrid Service → TorBox** and enter **your own** TorBox API key privately. This gives the Comet operator access to that service key; use an operator you trust.
3. Select **2160p** and **1080p**. Set **Required Languages** and **Preferred Languages** to **English**; enable **Allow English in Languages** and **Remove Unknown Languages**.
4. Enable **Show Cached Only**, **Remove Trash** and **Deduplicate Streams**. This public instance disables raw torrent mode. If another host exposes **Enable Torrent Mode**, leave it off: Crimson needs compatible direct links.
5. A compact starting point is **Max Results Per Resolution: 8** and **Max Size (GB): 35**. The size ceiling trades larger encodes for lighter files; it is not a bandwidth measurement.
6. Select **Copy Link**, then import that private HTTPS manifest using step 2 above. Comet's **Install** button targets Stremio instead.

The encoded Comet link contains your key; encoding does not make it safe to share. Public-instance rate limits apply. See the [Comet source/configuration](https://github.com/g0ldyy/comet) for current options. Results still depend on cache availability, language metadata, the delivery host and Roku-compatible video/audio.

## 5. Choose quality/audio and play

- **Settings → Picture quality → 4K first + 1080p** prefers eligible UHD and allows HD when needed. **4K only** disables HD fallback.
- **Settings → Automatic Play → Compare providers** compares the wider returned selection. **Start sooner** starts earlier with a potentially smaller initial pool.
- **Settings → Preferred source** can prioritize your installed stream provider. It changes lookup order, not a host's bandwidth.
- **Settings → Audio mode** should match **TV / projector speakers** or **HDMI soundbar / receiver**. See [audio wiring and settings](INSTALL.md#picture-and-audio).

Search, choose the movie or episode, then press **Play**. On the source screen, Left/Right changes provider and Play/Pause requests fresh links. During playback, pause to see available file/codec facts. A “2160p” label or 4K HDMI output alone does not prove genuine decoded UHD; a Dolby codec name alone does not prove audible surround. See [playback evidence and limits](PLAYBACK.md).

## If something does not work

| Symptom | What to do |
| --- | --- |
| “The TV is busy” | Close the previous summary/dialog, return to Add-ons, and submit once more. |
| Nothing imports after “Sent” | Confirm Allow import on the TV within 60 seconds; check its final result. |
| Setup page does not open | Use the address currently shown by this Roku, on the same local network; guest/client isolation can block local access. |
| “Add-ons already installed” after changing a manual configuration | Reimporting the same manifest ID does not update it. Keep your private setup link; deliberately remove/re-add only that provider if you want to replace its local configuration. For account-owned configuration changes, update it in Stremio and run Sync Stremio add-ons. |
| Title exists but no compatible streams | Confirm a stream provider is installed, not just catalogs. Check the selected movie/episode, provider response, account/cache and quality filter; more catalogs cannot create a missing stream. |
| Series has no episodes | Use a metadata-capable provider with compatible episode IDs. The TMDB preset above supplies metadata; arbitrary catalog-only providers may not. |
| Manifest is reachable but playback fails | Manifest checks do not verify subscription entitlement, file delivery, English audio or Roku decoding. Read the selected provider's source status. |
| “Loaded for this session; device save failed.” | The configuration is not confirmed saved across restart. Check the visible storage status and **Settings → Retry device saves**. |

For optional free providers and their limits, see [Free sources](FREE-SOURCES.md). For safe error categories, see [Add-on checks](ADDON_CHECKS.md). Report a problem through the repository's **Add-on problem** issue template using the public provider name and safe status; exclude configured URLs, signed media links and credentials.

Provider pages/preset checked October 17, 2026. Third-party options and availability can change. This guide does not install providers automatically or modify anyone's remote account.
