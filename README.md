![scrobbling in cliamp](https://github.com/tetsuo76/cliamp-lastfm/blob/main/screenshot.png?raw=true)

## Release Notes

### v1.8.0 (Latest)
- ✨ **New:** Live "now playing" via `track.updateNowPlaying` (shows up on your Last.fm profile while listening)
- ✨ **New:** Cached batch scrobbling — scrobbles queue in `cliamp.store` and upload in batches of up to 50
- ✨ **New:** Offline-friendly: failed uploads stay queued with 5-minute backoff and resume on next start
- ✨ **New:** Live radio segments: each `stream_title` change is tracked; segments listened ≥ `live_min_secs` are scrobbled, shorter/ilegible ones are skipped
- ⚙️ **New options:** `now_playing`, `live_enabled`, `live_min_secs`, `flush_interval`, `batch_size`
- 📝 Success messages are now batch summaries (`Scrobble Sent (N) … [Session, Queued]`) instead of per-track stats

### v1.7.0
- ✨ **New:** Automated setup script (`setup-lastfm.sh`) - simplifies authentication
- ✨ **New:** Auto-opens Last.fm API registration page
- ✨ **New:** Browser-based OAuth flow with automatic credential saving
- 🎯 No more manual session key generation
- 📖 Updated setup instructions with quick-start guide

### Important Migration Notes:
- As of v1.4.1+, plugin filename changed to `~/.config/cliamp/plugins/cliamp-lastfm.lua`
- Update your config: change `[plugins.lastfm]` to `[plugins.cliamp-lastfm]` in `~/.config/cliamp/config.toml`

---

### Simple last.fm plugin v1.8.0 for [cliamp](https://github.com/bjarneo/cliamp)

### 🚀 Quick Setup (2 minutes)

1. **Install the plugin:**
   ```bash
   cliamp plugins install tetsuo76/cliamp-lastfm
   ```

2. **Run the setup script:**
   ```bash
   ./setup-lastfm.sh
   ```
   
   **What the script does:**
   - Opens Last.fm API registration (you only need an app name)
   - Gets your API Key and Secret
   - Opens Last.fm login page
   - You authorize once, credentials saved automatically
   - ✅ Done!

3. **Restart cliamp** and start scrobbling!

### ⚙️ Prerequisites

- `bash` shell
- `curl` - for API requests
- `jq` - for JSON parsing (install: `sudo apt install jq` or `brew install jq`)
- Web browser - for Last.fm authorization

### 📖 Manual Setup (Legacy)

If you prefer to configure manually without the script, edit `~/.config/cliamp/config.toml`:

```toml
[plugins.cliamp-lastfm]
api_key = "YOUR_API_KEY"
api_secret = "YOUR_API_SECRET"
session_key = "SESSION_KEY"
username = "LASTFM_USERNAME"
# v1.8.0 options (all optional, defaults shown):
now_playing = true    # publish "now playing" via track.updateNowPlaying
live_enabled = true   # track live radio stream_title segments
live_min_secs = 60    # min seconds a live segment must play to be scrobbled
flush_interval = 60   # seconds between batch upload attempts
batch_size = 50       # max scrobbles per request (Last.fm allows up to 50)
```

> **Note:** after editing the plugin file, re-approve it with
> `cliamp plugins trust cliamp-lastfm` and restart cliamp.

### Update Plugin

- Remove old version:
  ```bash
  cliamp plugins remove cliamp-lastfm
  ```
- Install latest:
  ```bash
  cliamp plugins install tetsuo76/cliamp-lastfm
  ```

### Track Loving System:

- Love/Unlove Toggle (`*` key): Press asterisk to love the current track or unlove it if already loved
- Loved Track Detection: Automatically displays "♥ Loved Track" notification when a loved track starts playing
- Scrobble success messages show a batch summary: total accepted, session count, and queued remainder

### Live Radio:
- Each `stream_title` change opens a new segment and updates "now playing"
- Segments played for at least `live_min_secs` (default 60s) are queued for scrobbling
- Segments with missing artist/title are skipped (no station-name fallback)

### Operating Modes:
| Feature | Normal Mode | Silence Mode | Deactivated Mode |
|---|---|---|---|
| Scrobbling | Enabled | Enabled | Disabled |
| Last.fm API Calls | Enabled | Enabled | Disabled |
| UI Notifications | Enabled | Disabled | Disabled |
| Love / Unlove | Enabled | Enabled | Disabled |
| Purpose | Default behavior | Distraction-free usage | Fully disable Last.fm integration |

**Mode Toggle Keybind:** `&`

Tested with cliamp v2.0.1 (plugin v1.8.0). Scrobbling works with local files, radios, Spotify and Plex. It should work with other providers but I wasn't able to test them. 
