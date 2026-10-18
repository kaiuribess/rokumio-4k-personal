# Install and configure

## Install the release ZIP

**[Download the installable Roku ZIP — 0.5.29](https://github.com/kaiuribess/rokumio-4k-personal/releases/download/v0.5.29/rokumio-4k-personal-0.5.29.zip)**. Keep it zipped. This direct link avoids GitHub's source-code archives; those archives cannot be uploaded as the channel package.

1. On the Roku remote press **Home three times, Up twice, Right, Left, Right, Left, Right**.
2. Write down the device URL displayed on the developer screen, enable the installer, review Roku's terms, and set an installer password privately. Roku restarts.
3. On a browser on the same network, open that device URL. Username: **`rokudev`**. Use the password you chose.
4. Select **Upload**, choose the versioned app ZIP from [Releases](https://github.com/kaiuribess/rokumio-4k-personal/releases), and install/replace it using **zip**. The app should launch.

A failed development-package installation or deleting the app can reset its local profile and configured providers. Keep your private provider setup link available; never share it publicly.

Roku permits one sideloaded app at a time; this replaces an existing development app and restarts it. Download the release asset, not GitHub's source-code archive. These steps follow [Roku's developer setup documentation](https://developer.roku.com/dev/docs/developer-setup).

## Add a playable source

1. Continue with a local profile, or use optional Stremio pairing to sync your library/add-ons.
2. Open **Add-ons** and leave it open.
3. On your phone/computer, open the exact local setup address displayed by the Roku app. Paste the configured HTTPS manifest URL supplied by your provider and submit it.
4. Select **Allow import** on the TV within 60 seconds, then check the final import summary. A successful manifest import confirms installation, not movie playback compatibility.

Configured manifests may contain account secrets. Enter them privately; do not put them in GitHub issues or screenshots. Each public installation needs its own provider configuration. This release does not include the original user's account, API key or stored add-on.

## Picture and audio

**Settings → Picture quality** saves either **4K first + 1080p** (default) or **4K only**. The source screen's **\*** filter changes the current title only. A 2160p label remains a hint until actual encoded/native dimensions are available.

Open **Settings → Audio mode**. Choose **TV / projector speakers** for built-in display speakers. English AAC stereo, MP3 or usable PCM tracks are the conservative native path. If needed, choose Stereo in Roku's system audio settings. The app does not change system settings for you.

For a compatible soundbar/receiver with HDMI input, choose **HDMI soundbar / receiver**. Connect **Roku → soundbar/receiver HDMI IN → HDMI OUT / eARC → display**, select the bar's HDMI input, set Roku digital audio to **Auto**, and keep Roku volume modes **Off**. Use the soundbar remote for volume while setting it up. The app's preference changes source ranking/compatibility checks; it cannot create discrete surround or certify every receiver.

Open **Settings → Audio connection** after connecting or changing equipment. It queries current Roku-reported output and codec capability, and warns if Stereo is still reported while HDMI surround is selected. A supported codec report is not an acoustic test. During an English Dolby Digital / DD+ 5.1 stream, check the receiver's input display; an AAC stereo source remains two channels.

For **Hisense AX700 + Optoma UHD50X**, plug the Stick into the AX700's **HDMI IN**, then run the AX700's **HDMI OUT / eARC** to the projector's 4K-capable HDMI input. AX700 specifications list a separate HDMI input, 4K60 passthrough, and Dolby Atmos support. This route carries audio to the bar directly; it does not require the projector to return audio over eARC. Check the Roku display setup after changing the HDMI chain. [Official AX700 specifications](https://cdn.bfldr.com/U447IH35/as/x9qfsw9scxvcvw2p9kxz6tsp/1959005_Specifications).

AAC stereo is two channels. Dolby/DTS/TrueHD or multichannel AAC support varies. A silent/unsupported original file cannot be universally converted to stereo by this BrightScript app. See [playback limitations](PLAYBACK.md).

## Check an add-on problem

Open **Add-ons → Check add-ons**, or **Settings → Add-on checks**. Select a row to read its safe error explanation; Play/Pause checks again and Back cancels/returns. The check requests manifests only. Source availability is reported separately for the selected title/provider, and playback compatibility is checked when a source is selected. See [what each result means](ADDON_CHECKS.md).

## Remote controls and shows

Home opens with a featured area and five shortcuts. Choose Movies, Shows or Genres to enter full Discover filters, or My list for saved titles. **Down** from the shortcuts expands catalog browsing; **Up** at the first row returns to the shortcuts. **\*** moves between browsing, the side menu and shortcuts. Each catalog row's **See all** tile opens the complete provider catalog and genre. Home previews are intentionally smaller than full catalogs to limit memory.

| Control | Action |
| --- | --- |
| Arrows / OK | Navigate and select |
| Microphone with Search keyboard open | Native voice dictation where supported |
| Left / Right on sources | Change provider |
| More sources / Previous sources | Move through pages of 48 retained eligible choices |
| \* on sources | Toggle 4K-only / all qualities |
| Play/Pause on sources | Request fresh links |
| Play/Pause on Home | Refresh catalog rows |
| Down from Home shortcuts | Expand two-row catalog browser |
| \* on Home | Move between catalog, menu and shortcuts |
| Play/Pause on Add-on checks | Repeat manifest checks |
| Play/Pause, seek, FF/Rewind in playback | Native playback controls |
| \* in playback | Native options/captions |
| Back | Return; cancel pending lookup/countdown |

After an accepted show episode finishes, the next known episode starts after a five-second countdown. Quality/audio preferences carry forward. The last episode, unavailable metadata and a known future release date stop the sequence. An early playback failure retries the current episode rather than skipping it. This does not detect credits or provide a skip-intro feature.

**Settings → Next episode** disables/enables that countdown. **Source recovery** controls automatic alternate-source attempts; when Off, playback uses the selected eligible source. These saved settings apply to subsequent playback and do not interrupt a running movie. English track checks remain active in both recovery modes.

**Settings → Automatic Play** offers **Start sooner** (default) or **Compare providers**. Start sooner compares available candidates briefly and can begin while another provider is still loading. It has fewer initial recovery alternatives than a full comparison. Compare providers waits for all eligible responses before selecting. Both use the same quality filter and English/audio checks; a candidate label does not establish successful decoding. Returning to the source screen resumes queued providers so their choices remain available. Late provider results do not replace a movie already playing.

For your highest-quality selection, use **Compare providers + Picture quality → 4K only**. With HD fallback allowed, an early 1080p source can be chosen before another provider supplies UHD. This describes selection policy, not a measured device failure; native playback facts still need to confirm the source's actual resolution.

**Settings → Preferred source** opens a scrolling provider list. Choose an installed provider or **Automatic**, which uses the most recent provider to pass English-track/native A/V progress checks. This changes waiting order; it does not preempt active transfers or guarantee a file works. Source statuses now distinguish **Queued** (waiting for a slot) and **Requesting sources** (lookup running).

Manual source pages retain 48 real cards plus navigation controls. More/Previous do not start playback. Back keeps its normal screen-return behavior. Pages expose all retained eligible choices; warm preload still limits each provider to 256 candidates. Play/Pause refresh uses an ordinary provider request when you need fresh/full results. Playback receives the retained pool, not just the displayed page.

## Updates

Upload a new release ZIP through the same installer when you are ready to restart the app. App updates are manual. Catalog/search/source responses come from online add-ons and can change independently of app releases. Fresh links or a refreshed manifest may be needed after provider changes. Registry configuration is separate from the ZIP; do not delete/reset/rekey the app if you intend to retain it.

For someone using the app for the first time, share the README's direct **Download the Roku install ZIP** link together with this setup guide. Each person enables developer mode and configures their own provider privately. The ZIP cannot enable developer mode, supply subscriptions or update itself.


## Stremio account import and recovery (0.5.22)

Pair under Settings → Connect Stremio using the on-screen code. Do not share your account key. Supported account catalog/metadata, stream and subtitle add-ons import automatically after login and on each relaunch. Open Add-ons for current status and **Sync Stremio add-ons** to retry. A complete empty collection is distinct from a failed request. Partial results name accepted, unsupported, invalid and over-budget counts; previous providers are not removed on an incomplete snapshot. Exact duplicates are skipped; configured instances with different URLs remain separate.

After a complete sync confirms your account has no catalog provider, choose **Add movie and show catalogs → Cinemeta · only on this Roku**. This explicit local installation adds browsing/search metadata; it supplies no movie streams, does not purchase a service, and never modifies your remote Stremio collection. A stream provider is still required for playback.

For browser installation, leave Add-ons open, submit the configured HTTPS manifest privately and select **Allow import** on the TV within 60 seconds. Cancel requests you did not initiate. The browser acknowledgement only means the confirmation was queued; the TV's final import summary is authoritative. Manual URL entry and the local catalog option are already initiated using the remote and do not require another browser confirmation.

If an account save is unsynced, Settings → **Retry saved changes** refreshes the server baseline before retrying retained edits. For device storage failures, **Retry device saves** restarts up to three background retry rounds. The app distinguishes a change held in memory from an acknowledged save. A full registry may require removing unnecessary local data; repeated network/storage failures remain visible rather than being treated as successful.
