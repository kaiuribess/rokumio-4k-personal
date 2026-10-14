# Install and configure

## Install the release ZIP

1. On the Roku remote press **Home three times, Up twice, Right, Left, Right, Left, Right**.
2. Write down the device URL displayed on the developer screen, enable the installer, review Roku's terms, and set an installer password privately. Roku restarts.
3. On a browser on the same network, open that device URL. Username: **`rokudev`**. Use the password you chose.
4. Select **Upload**, choose the versioned app ZIP from [Releases](https://github.com/kaiuribess/rokumio-4k-personal/releases), and install/replace it using **zip**. The app should launch.

Roku permits one sideloaded app at a time; this replaces an existing development app and restarts it. Download the release asset, not GitHub's source-code archive. These steps follow [Roku's developer setup documentation](https://developer.roku.com/dev/docs/developer-setup).

## Add a playable source

1. Continue with a local profile, or use optional Stremio pairing to sync your library/add-ons.
2. Open **Add-ons** and leave it open.
3. On your phone/computer, open the exact local setup address displayed by the Roku app. Paste the configured HTTPS manifest URL supplied by your provider and submit it.
4. Check the TV's import summary. A successful manifest import confirms installation, not movie playback compatibility.

Configured manifests may contain account secrets. Enter them privately; do not put them in GitHub issues or screenshots. Each public installation needs its own provider configuration. This release does not include the original user's account, API key or stored add-on.

## Picture and audio

For built-in projector/TV speakers, select **Projector speakers** in the app. English AAC stereo, MP3 or usable PCM tracks are the conservative native path. If needed, choose Stereo in Roku's system audio settings. The app does not change system settings for you.

For a compatible soundbar/receiver with HDMI input, connect **Roku → soundbar/receiver HDMI IN → display** and select the receiver preset (**AX700 surround**) in the app. The preset changes ranking/compatibility preference; it cannot create discrete surround or certify every receiver. Use equipment-specific HDMI/passthrough instructions and check the receiver's reported input format.

AAC stereo is two channels. Dolby/DTS/TrueHD or multichannel AAC support varies. A silent/unsupported original file cannot be universally converted to stereo by this BrightScript app. See [playback limitations](PLAYBACK.md).

## Remote controls and shows

| Control | Action |
| --- | --- |
| Arrows / OK | Navigate and select |
| Microphone with Search keyboard open | Native voice dictation where supported |
| Left / Right on sources | Change provider |
| \* on sources | Toggle 4K-only / all qualities |
| Play/Pause on sources | Request fresh links |
| Play/Pause on Home | Refresh catalog rows |
| Play/Pause, seek, FF/Rewind in playback | Native playback controls |
| \* in playback | Native options/captions |
| Back | Return; cancel pending lookup/countdown |

After an accepted show episode finishes, the next known episode starts after a five-second countdown. Quality/audio preferences carry forward. The last episode, unavailable metadata and a known future release date stop the sequence. An early playback failure retries the current episode rather than skipping it. This does not detect credits or provide a skip-intro feature.

## Updates

Upload a new release ZIP through the same installer when you are ready to restart the app. App updates are manual. Catalog/search/source responses come from online add-ons and can change independently of app releases. Fresh links or a refreshed manifest may be needed after provider changes. Registry configuration is separate from the ZIP; do not delete/reset/rekey the app if you intend to retain it.
