# cliamp-lastfm

A Last.fm scrobbling plugin for [cliamp](https://github.com/bjarneo/cliamp).

Automatically sends your currently playing music to Last.fm with support for Now Playing updates, configurable scrobble thresholds, track loving/unloving, playback tracking, session statistics, and multiple operating modes.

---

<details>
<summary><h2>✨ Features</h2></summary>

- 🎵 Automatic Last.fm scrobbling
- ▶️ Last.fm Now Playing updates
- ⏱️ Configurable scrobble thresholds
- 🕐 Actual playback-time tracking
- ⏸️ Pause/resume-aware tracking
- ⏩ Seek-aware playback handling
- 📊 Last.fm and session statistics
- ❤️ Love / unlove tracks directly from cliamp
- 💗 Loved-track detection
- 🔄 Duplicate-scrobble protection
- ⌨️ Manual scrobbling
- 💤 Silent mode
- 🚫 Fully disabled mode
- 🔐 Browser-based Last.fm authentication
- 🔒 HTTPS communication with Last.fm
- 🛠️ Automated setup script

</details>

---

<details>
<summary><h1>🚀 Quick Setup</h1></summary>

## 1. Install the plugin

```bash
cliamp plugins install tetsuo76/cliamp-lastfm
```

---

## 2. Run the setup script

From the plugin directory:

```bash
./setup-lastfm.sh
```

The setup script will:

1. Open the Last.fm API application registration page.
2. Ask for your Last.fm API Key.
3. Ask for your Last.fm API Secret.
4. Ask for your Last.fm username.
5. Request an authorization token.
6. Open the Last.fm authorization page.
7. Have you authorize the application.
8. Retrieve your Last.fm session key.
9. Save the credentials to your cliamp configuration.

You only need to authorize the application once.

---

## 3. Restart cliamp

After authentication:

```bash
cliamp
```

The plugin will automatically begin tracking playback and communicating with Last.fm.

</details>

---

<details>
<summary><h1>⚙️ Configuration</h1></summary>

The plugin configuration is stored in:

```text
~/.config/cliamp/config.toml
```

The Last.fm plugin uses:

```toml
[plugins.cliamp-lastfm]

api_key = "YOUR_API_KEY"
api_secret = "YOUR_API_SECRET"
session_key = "YOUR_SESSION_KEY"
username = "YOUR_LASTFM_USERNAME"
```

Keep your API Secret and Session Key private.

</details>

---

<details>
<summary><h1>⏱️ Scrobbling</h1></summary>

The plugin supports configurable scrobble timing rather than requiring playback to reach the end of a track.

This allows tracks to be scrobbled while they are still playing once the required amount of listening has been reached.

## Actual Time Played

Recommended for normal music listening.

```toml
scrobble_mode = "played"
scrobble_seconds = 120
```

The track is scrobbled after **120 seconds of actual playback**.

Paused time does not count.

Example:

```text
00:00  Play
01:00  Pause
        ↓
        10 minutes paused
        ↓
01:00  Resume
02:00  Scrobble
```

This prevents a paused track from incorrectly accumulating listening time.

---

## Percentage-Based Scrobbling

Scrobble after reaching a percentage of the track:

```toml
scrobble_mode = "percent"
scrobble_percent = 50
```

This example scrobbles after reaching 50% of the track.

---

## Playback Position

Scrobble after reaching a specific playback position:

```toml
scrobble_mode = "seconds"
scrobble_seconds = 120
```

This scrobbles after reaching two minutes into the track.

---

## Last.fm-Style Threshold

Use:

```toml
scrobble_mode = "lastfm"
scrobble_max_seconds = 240
```

This follows the traditional Last.fm-style rule:

- Scrobble after approximately 50% of the track has been played, or
- After the configured maximum threshold.

The maximum threshold can be changed:

```toml
scrobble_max_seconds = 240
```

</details>

---

<details>
<summary><h1>▶️ Now Playing</h1></summary>

The plugin can update Last.fm's **Now Playing** status when a track begins.

Enable it with:

```toml
now_playing = true
```

Disable it with:

```toml
now_playing = false
```

Now Playing updates are independent of the scrobble threshold.

Example:

```text
Track starts
    ↓
Last.fm Now Playing updated
    ↓
Continue listening
    ↓
Scrobble threshold reached
    ↓
Track scrobbled
```

</details>

---

<details>
<summary><h1>🕐 Playback Tracking</h1></summary>

The plugin tracks actual playback rather than blindly relying on the current track position.

This allows it to properly handle:

- Play
- Pause
- Resume
- Track changes
- Seeking
- Stopping playback
- Manual scrobbling

When using actual played-time tracking:

```text
Played time = time actually spent listening
```

rather than:

```text
Played time = current playback position
```

This prevents seeking forward or leaving a track paused from artificially satisfying the scrobble threshold.

</details>

---

<details>
<summary><h1>⌨️ Keybindings</h1></summary>

The plugin provides the following keybindings:

| Key      | Action                           |
| -------- | --------------------------------- |
| `*`      | Love / unlove current track      |
| `&`      | Toggle Last.fm operating mode    |
| `Ctrl+L` | Manually scrobble current track  |

> `S` is intentionally **not** used for manual scrobbling because `S` is already assigned by cliamp.

---

## ❤️ Love / Unlove

Press:

```text
*
```

while a track is playing.

If the track is not loved, it will be loved.

If the track is already loved, it will be unloved.

The plugin can also detect whether the current track is already loved and display the appropriate status.

---

## 🔨 Manual Scrobble

Press:

```text
Ctrl+L
```

to manually scrobble the current track.

This is useful for:

- Long mixes
- Live recordings
- Radio streams
- Podcasts
- Tracks with unusual lengths
- Recovering from a failed automatic scrobble
- Testing Last.fm integration

The plugin protects against submitting the same playback session multiple times.

</details>

---

<details>
<summary><h1>🔄 Operating Modes</h1></summary>

Press:

```text
&
```

to cycle through the available Last.fm modes.

```text
Normal → Silent → Off → Normal
```

---

## Normal Mode

Everything is enabled.

| Feature       | Status    |
| ------------- | --------- |
| Scrobbling    | ✅ Enabled |
| Now Playing   | ✅ Enabled |
| Last.fm API   | ✅ Enabled |
| Notifications | ✅ Enabled |
| Love / Unlove | ✅ Enabled |

---

## Silent Mode

Last.fm continues working, but notifications are suppressed.

| Feature       | Status     |
| ------------- | ---------- |
| Scrobbling    | ✅ Enabled  |
| Now Playing   | ✅ Enabled  |
| Last.fm API   | ✅ Enabled  |
| Notifications | ❌ Disabled |
| Love / Unlove | ✅ Enabled  |

This is useful when you want Last.fm tracking without notifications interrupting playback.

---

## Off Mode

Last.fm integration is completely disabled.

| Feature       | Status     |
| ------------- | ---------- |
| Scrobbling    | ❌ Disabled |
| Now Playing   | ❌ Disabled |
| Last.fm API   | ❌ Disabled |
| Notifications | ❌ Disabled |
| Love / Unlove | ❌ Disabled |

Press `&` again to return to Normal mode.

</details>

---

<details>
<summary><h1>📊 Statistics</h1></summary>

Successful scrobbles can display Last.fm statistics such as:

- Total track plays
- Total artist count
- Loved track count
- Current track play count
- Current cliamp session scrobbles

Example:

```text
✓ Scrobbled: Artist - Song [2:03 played]
```

Session information can also be displayed alongside successful scrobbles.

</details>

---

<details>
<summary><h1>🔔 Notifications</h1></summary>

Notification duration can be configured.

Example:

```toml
message_duration = 10
```

This controls how long plugin notifications remain visible.

Set a shorter duration if you prefer less intrusive notifications:

```toml
message_duration = 5
```

</details>

---

<details>
<summary><h1>🧩 Example Configuration</h1></summary>

A typical configuration might look like:

```toml
[plugins.cliamp-lastfm]

# Last.fm authentication
api_key = "YOUR_API_KEY"
api_secret = "YOUR_API_SECRET"
session_key = "YOUR_SESSION_KEY"
username = "YOUR_LASTFM_USERNAME"

# Scrobbling
scrobble_mode = "played"
scrobble_seconds = 120

# Now Playing
now_playing = true

# Notifications
message_duration = 10
```

Only configure the threshold options required by the selected scrobble mode.

</details>

---

<details>
<summary><h1>📦 Prerequisites</h1></summary>

The plugin requires:

- [cliamp](https://github.com/bjarneo/cliamp)
- A Last.fm account
- A Last.fm API application

The automated setup script requires:

- `bash`
- `curl`
- `jq`
- A web browser

---

## macOS

Install `jq` with Homebrew:

```bash
brew install jq
```

---

## Debian / Ubuntu

Install `jq` with:

```bash
sudo apt install jq
```

</details>

---

<details>
<summary><h1>🔐 Last.fm API Setup</h1></summary>

Create a Last.fm API application at:

[https://www.last.fm/api/account/create](https://www.last.fm/api/account/create)

The setup script will open the registration page automatically.

You will need:

- API Key
- API Secret

The callback URL is not required for this plugin's authentication flow.

The setup script then opens the Last.fm authorization page and retrieves a session key after you approve the application.

Credentials are stored locally in:

```text
~/.config/cliamp/config.toml
```

**Never share your API Secret or Session Key.**

</details>

---

<details>
<summary><h1>🔄 Updating the Plugin</h1></summary>

If you installed the plugin through cliamp, update it using the normal cliamp plugin update/reinstall process.

If cliamp reports that the plugin contents are untrusted after an update:

```bash
cliamp plugins trust cliamp-lastfm
```

Then verify:

```bash
cliamp plugins list
```

Restart cliamp after updating.

</details>

---

<details>
<summary><h1>🛠️ Troubleshooting</h1></summary>

## Plugin Shows as Untrusted

Run:

```bash
cliamp plugins trust cliamp-lastfm
```

Then:

```bash
cliamp plugins list
```

The plugin should show as trusted.

---

## Last.fm Is Not Scrobbling

First verify that the plugin configuration exists:

```bash
grep -A10 '\[plugins.cliamp-lastfm\]' \
    ~/.config/cliamp/config.toml
```

You should have:

```toml
[plugins.cliamp-lastfm]
api_key = "..."
api_secret = "..."
session_key = "..."
username = "..."
```

If the session key is missing or invalid, rerun:

```bash
./setup-lastfm.sh
```

Then restart cliamp.

---

## Now Playing Works but Scrobbling Does Not

Check the configured threshold:

```toml
scrobble_mode = "played"
scrobble_seconds = 120
```

Remember that `played` measures **actual listening time**.

Pausing does not count toward the threshold.

Seeking forward does not count as listening time.

---

## I Want Tracks Scrobbled Sooner

Lower the threshold:

```toml
scrobble_mode = "played"
scrobble_seconds = 60
```

---

## I Want Traditional Last.fm Behavior

Use:

```toml
scrobble_mode = "lastfm"
scrobble_max_seconds = 240
```

---

## I Accidentally Seek Through a Track

When using:

```toml
scrobble_mode = "played"
```

the plugin tracks actual listening time rather than simply trusting the playback position.

This prevents rapidly seeking through a track from immediately satisfying the scrobble threshold.

</details>

---

<details>
<summary><h1>🧪 Compatibility</h1></summary>

The plugin is designed to work with cliamp providers that expose standard track and playback information.

Tested providers include:

- Local files
- Radio
- Spotify
- Plex

Other providers may work as long as they expose the playback and track information required by the plugin.

</details>

---

<details>
<summary><h1>📝 Migration Notes</h1></summary>

## Plugin Configuration

Current configuration:

```toml
[plugins.cliamp-lastfm]
```

Older configurations using:

```toml
[plugins.lastfm]
```

should be changed to:

```toml
[plugins.cliamp-lastfm]
```

</details>

---

<details>
<summary><h1>📜 Release Notes</h1></summary>

## v2.0.0

### Added

- Configurable scrobble thresholds
- Actual played-time tracking
- Percentage-based scrobbling
- Fixed playback-position scrobbling
- Last.fm-style scrobble threshold
- Last.fm Now Playing support
- Manual scrobbling
- `Ctrl+L` manual scrobble keybinding
- Pause/resume-aware playback tracking
- Seek-aware playback handling
- Duplicate-scrobble protection
- Configurable notification duration
- Improved Last.fm API handling
- Improved error handling
- Improved scrobble status reporting

### Changed

- Scrobbling no longer depends exclusively on reaching the end of a track
- Playback tracking now accounts for actual listening time
- Paused playback no longer counts toward played-time thresholds
- Seeking no longer artificially increases played time
- Manual scrobbling moved to `Ctrl+L`
- Last.fm API communication uses HTTPS
- Plugin version updated to `2.0.0`

### Removed

- End-of-track-only scrobbling behavior
- `S` manual scrobble keybinding due to cliamp keybinding conflict
- HTTP Last.fm API endpoint

### Preserved

- Last.fm OAuth authentication
- Automated setup script
- Love / unlove functionality
- Loved-track detection
- Session statistics
- Normal / Silent / Off operating modes
- `*` love/unlove keybinding
- `&` mode toggle keybinding

---

## v1.7.0

- Added automated Last.fm setup script
- Added automatic Last.fm API registration workflow
- Added browser-based OAuth authorization
- Added automatic credential saving
- Added setup documentation

</details>

---

# 📄 License

See the repository for license information.
