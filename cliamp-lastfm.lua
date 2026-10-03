local p = plugin.register({
    name = "lastfm",
    type = "hook",
    version = "1.8.0",
    description = "Scrobbles to last.fm with now-playing + cached batch queue (live radio support)",
    permissions = {"keymap"},
})

local api_key = p:config("api_key")
local api_secret = p:config("api_secret")
local session_key = p:config("session_key")
local username = p:config("username")

local function to_bool(v, default)
    if v == nil then return default end
    if type(v) == "boolean" then return v end
    local s = tostring(v):lower()
    if s == "true" or s == "1" or s == "yes" then return true end
    if s == "false" or s == "0" or s == "no" then return false end
    return default
end

local function to_num(v, default)
    local n = tonumber(v)
    if n == nil then return default end
    return n
end

local now_playing_enabled = to_bool(p:config("now_playing"), true)
local live_enabled = to_bool(p:config("live_enabled"), true)
local live_min_secs = to_num(p:config("live_min_secs"), 60)
local flush_interval = to_num(p:config("flush_interval"), 60)
local batch_size = to_num(p:config("batch_size"), 50)
if batch_size < 1 then batch_size = 1 end
if batch_size > 50 then batch_size = 50 end
if flush_interval < 15 then flush_interval = 15 end

local API_URL = "http://ws.audioscrobbler.com/2.0/"

local has_scrobbled_current = false
local session_scrobbles = 0
local last_scrobble_time = 0
local message_duration = 10
local flushing = false
local backoff_until = 0
local live_seg = nil
local last_np_key = nil
local flush_queue -- forward declaration (defined below, used by live_close)

-- last.fm modes:
-- normal  = everything works, messages shown
-- silent  = everything works, no messages except mode toggle message
-- off     = no messages, no scrobbling, no last.fm API calls
local MODE_NORMAL = "normal"
local MODE_SILENT = "silent"
local MODE_OFF = "off"

local lastfm_mode = MODE_NORMAL
local current_track_artist = nil
local current_track_title = nil

local function lastfm_enabled()
    return lastfm_mode ~= MODE_OFF
end

local function lastfm_silent()
    return lastfm_mode == MODE_SILENT
end

local function lastfm_message(msg, duration)
    if lastfm_enabled() and not lastfm_silent() then
        cliamp.message(msg, duration or message_duration)
    end
end

-- Helper to safely handle properties vs functions
local function get(val)
    if type(val) == "function" then return val() end
    return val
end

local function urlencode(str)
    if not str then return "" end
    str = tostring(str)
    str = string.gsub(str, "([^%w%.%- ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return string.gsub(str, " ", "+")
end

local function format_number(num)
    if type(num) ~= "number" then return tostring(num) end
    local str = tostring(num)
    local formatted = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if formatted:sub(1, 1) == "," then formatted = formatted:sub(2) end
    return formatted
end

local function get_api_sig(params)
    local keys = {}

    for k in pairs(params) do
        if k ~= "format" then
            table.insert(keys, k)
        end
    end

    table.sort(keys)

    local str = ""
    for _, k in ipairs(keys) do
        str = str .. k .. tostring(params[k])
    end

    str = str .. api_secret
    return cliamp.crypto.md5(str)
end

local function build_query_string(params)
    local parts = {}

    for k, v in pairs(params) do
        table.insert(parts, urlencode(k) .. "=" .. urlencode(v))
    end

    return table.concat(parts, "&")
end

local function build_post_body(params)
    return build_query_string(params) .. "&format=json"
end

local function lastfm_get(url)
    if not lastfm_enabled() then
        return nil, "disabled"
    end

    return cliamp.http.get(url)
end

local function lastfm_post(params)
    if not lastfm_enabled() then
        return nil, "disabled"
    end

    return cliamp.http.post(API_URL, {
        body = build_post_body(params),
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
    })
end

local function trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$") or "")
end

-- Split "Artist - Title" (Icecast-style stream titles). Returns "","" when
-- there is no separator so callers can skip illegible live segments.
local function split_stream_title(s)
    s = trim(s)
    if s == "" then return "", "" end
    local a, b = s:match("^(.-)%s+%-%s+(.+)$")
    if not a or not b then return "", "" end
    return trim(a), trim(b)
end

local function queue_load()
    local ok, q = pcall(cliamp.store.get, "queue")
    if not ok then return {} end
    if type(q) ~= "table" then return {} end
    return q
end

local function queue_save(q)
    pcall(cliamp.store.set, "queue", q)
end

local function queue_add(artist, title, album, timestamp)
    artist, title = trim(artist), trim(title)
    album = trim(album)
    timestamp = math.floor(tonumber(timestamp) or os.time())
    if artist == "" or title == "" then return false end
    if not api_key or not api_secret or not session_key then
        lastfm_message("[last.fm] Not configured", message_duration)
        return false
    end
    local q = queue_load()
    for _, e in ipairs(q) do
        if e.artist == artist and e.track == title and e.timestamp == timestamp then
            return false
        end
    end
    table.insert(q, { artist = artist, track = title, album = album, timestamp = timestamp })
    queue_save(q)
    cliamp.log.debug("last.fm queued: " .. artist .. " - " .. title .. " (queue=" .. #q .. ")")
    return true
end

local function update_now_playing(artist, title, album, duration)
    if not lastfm_enabled() or not now_playing_enabled then return end
    if not api_key or not api_secret or not session_key then return end
    artist, title = trim(artist), trim(title)
    if artist == "" or title == "" then return end
    local key = artist .. "\0" .. title
    if key == last_np_key then return end
    last_np_key = key
    local params = {
        method = "track.updateNowPlaying",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title,
    }
    if trim(album) ~= "" then params.album = trim(album) end
    local dur = math.floor(tonumber(duration) or 0)
    if dur > 0 then params.duration = tostring(dur) end
    local sig_params = {}
    for k, v in pairs(params) do sig_params[k] = v end
    params.api_sig = get_api_sig(sig_params)
    local response, status = lastfm_post(params)
    if tostring(status) ~= "200" then
        cliamp.log.warn("last.fm now-playing failed: status=" .. tostring(status))
        last_np_key = nil
    else
        cliamp.log.debug("last.fm now-playing: " .. artist .. " - " .. title)
    end
end

-- Close the current live segment: scrobble it only if it played >= 60s.
local function live_close()
    local seg = live_seg
    live_seg = nil
    if not seg then return end
    if not lastfm_enabled() or not live_enabled then return end
    local elapsed = os.time() - (seg.start or os.time())
    if elapsed >= live_min_secs and trim(seg.artist) ~= "" and trim(seg.title) ~= "" then
        if queue_add(seg.artist, seg.title, seg.album, seg.start) then
            cliamp.timer.after(2, flush_queue)
        end
    else
        cliamp.log.debug("last.fm live segment skipped (<" .. live_min_secs .. "s or illegible)")
    end
end

local function live_open(artist, title, album, path, duration)
    artist, title = trim(artist), trim(title)
    if artist == "" or title == "" then return end
    live_seg = { artist = artist, title = title, album = trim(album), path = path, start = os.time() }
    update_now_playing(artist, title, album, duration)
end

local function normalize_track_meta(track)
    if not track then
        return "", ""
    end

    local artist = track.artist or track.Artist or track.artist_name or track.ArtistName or ""
    local title = track.title or track.Title or track.track or track.Track or ""

    artist = tostring(artist):match("^%s*(.-)%s*$") or ""
    title = tostring(title):match("^%s*(.-)%s*$") or ""
    return artist, title
end

local function get_current_track_meta()
    local artist = current_track_artist and current_track_artist ~= "" and current_track_artist or cliamp.track.artist()
    local title = current_track_title and current_track_title ~= "" and current_track_title or cliamp.track.title()

    artist = tostring(artist or ""):match("^%s*(.-)%s*$") or ""
    title = tostring(title or ""):match("^%s*(.-)%s*$") or ""
    return artist, title
end

local function check_track_loved(track)
    if not lastfm_enabled() then return end
    if not username then return end

    local artist, title = normalize_track_meta(track)

    if artist == "" or title == "" then return end

    local response, status = lastfm_get(API_URL .. "?" .. build_query_string({
        method = "track.getInfo",
        api_key = api_key,
        artist = artist,
        track = title,
        username = username,
        format = "json",
    }))

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and data.track and data.track.userloved == "1" then
            lastfm_message("♥ Loved Track: " .. artist .. " - " .. title, message_duration)
        end
    end
end

local function is_track_loved(artist, title)
    if not lastfm_enabled() then return false end
    if not username then return false end

    local response, status = lastfm_get(API_URL .. "?" .. build_query_string({
        method = "track.getInfo",
        api_key = api_key,
        artist = artist,
        track = title,
        username = username,
        format = "json",
    }))

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and data.track and data.track.userloved == "1" then
            return true
        end
    end

    return false
end

local function get_track_scrobble_count(artist, title)
    if not lastfm_enabled() then return "?" end
    if not username then return "?" end

    local response, status = lastfm_get(API_URL .. "?" .. build_query_string({
        method = "track.getInfo",
        api_key = api_key,
        artist = artist,
        track = title,
        username = username,
        format = "json",
    }))

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and data.track and data.track.userplaycount then
            local count = tonumber(data.track.userplaycount)

            if count then
                return format_number(count)
            end
        end
    end

    return "0"
end

local function get_user_loved_count()
    if not lastfm_enabled() then return "?" end
    if not username then return "?" end

    local response, status = lastfm_get(API_URL .. "?" .. build_query_string({
        method = "user.getLovedTracks",
        api_key = api_key,
        user = username,
        limit = 1,
        format = "json",
    }))

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and data.lovedtracks and data.lovedtracks["@attr"] and data.lovedtracks["@attr"].total then
            local count = tonumber(data.lovedtracks["@attr"].total)

            if count then
                return format_number(count)
            end
        end
    end

    return "?"
end

local function unlove_track()
    if not lastfm_enabled() then return end

    if not username or not session_key then
        lastfm_message("[last.fm] Not configured", message_duration)
        return
    end

    local artist, title = get_current_track_meta()

    if artist == "" or title == "" then
        lastfm_message("[last.fm] No track playing", message_duration)
        return
    end

    local params = {
        method = "track.unlove",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title
    }

    local sig = get_api_sig(params)

    local response, status = lastfm_post({
        method = "track.unlove",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title,
        api_sig = sig,
    })

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and (data.lfm == nil or next(data) == nil) then
            lastfm_message("♡ Unloved: " .. artist .. " - " .. title, message_duration)
        elseif data and data.error then
            cliamp.log.warn("last.fm unlove failed: error code " .. tostring(data.error) .. " - " .. tostring(data.message))
            lastfm_message("[last.fm] Error: " .. tostring(data.message), message_duration)
        else
            cliamp.log.warn("last.fm unlove unexpected response: " .. tostring(response))
            lastfm_message("[last.fm] Unexpected response", message_duration)
        end
    else
        local error_detail = "status=" .. tostring(status)

        if response then
            error_detail = error_detail .. ", response=" .. tostring(response)
        end

        cliamp.log.warn("last.fm unlove failed: " .. error_detail)
        lastfm_message("[last.fm] Unable to unlove track now", message_duration)
    end
end

local function love_track()
    if not lastfm_enabled() then return end

    if not username or not session_key then
        lastfm_message("[last.fm] Not configured", message_duration)
        return
    end

    local artist, title = get_current_track_meta()

    if artist == "" or title == "" then
        lastfm_message("[last.fm] No track playing", message_duration)
        return
    end

    if is_track_loved(artist, title) then
        unlove_track()
        return
    end

    local params = {
        method = "track.love",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title
    }

    local sig = get_api_sig(params)

    local response, status = lastfm_post({
        method = "track.love",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title,
        api_sig = sig,
    })

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and data.lfm and data.lfm.status == "ok" then
            lastfm_message("♥ Loved: " .. artist .. " - " .. title, message_duration)
        elseif data and (data.lfm == nil or next(data) == nil) then
            lastfm_message("♥ Loved: " .. artist .. " - " .. title, message_duration)
        elseif data and data.error then
            cliamp.log.warn("last.fm love failed: error code " .. tostring(data.error) .. " - " .. tostring(data.message))
            lastfm_message("[last.fm] Error: " .. tostring(data.message), message_duration)
        else
            cliamp.log.warn("last.fm love unexpected response: " .. tostring(response))
            lastfm_message("[last.fm] Unexpected response", message_duration)
        end
    else
        local error_detail = "status=" .. tostring(status)

        if response then
            error_detail = error_detail .. ", response=" .. tostring(response)
        end

        cliamp.log.warn("last.fm love failed: " .. error_detail)
        lastfm_message("[last.fm] Unable to love track now", message_duration)
    end
end

-- Enqueue a single scrobble and schedule a batch flush (replaces direct POST).
local function do_scrobble(track, timestamp)
    if not lastfm_enabled() then return false end

    local artist = trim(track.artist or track.Artist or "")
    local title = trim(track.title or track.Title or "")
    local album = trim(track.album or track.Album or "")
    if artist == "" or title == "" then return false end
    if queue_add(artist, title, album, timestamp) then
        cliamp.timer.after(2, flush_queue)
        return true
    end
    return false
end

-- Batch flush: posts up to batch_size queued scrobbles in one request.
-- Offline-friendly: failures keep the queue (5 min backoff); HTTP 200 with
-- zero accepted (invalid entries) drops the batch to avoid poison loops.
flush_queue = function()
    if not lastfm_enabled() then return end
    if flushing then return end
    if os.time() < backoff_until then return end
    if not api_key or not api_secret or not session_key then return end
    local q = queue_load()
    if #q == 0 then return end
    flushing = true
    local n = math.min(#q, batch_size)
    local first = q[1]
    local params = {
        method = "track.scrobble",
        api_key = api_key,
        sk = session_key,
    }
    for i = 1, n do
        local e = q[i]
        local idx = tostring(i - 1)
        params["artist[" .. idx .. "]"] = e.artist
        params["track[" .. idx .. "]"] = e.track
        params["album[" .. idx .. "]"] = e.album or ""
        params["timestamp[" .. idx .. "]"] = tostring(e.timestamp)
    end
    local sig_params = {}
    for k, v in pairs(params) do sig_params[k] = v end
    params.api_sig = get_api_sig(sig_params)

    local response, status = lastfm_post(params)
    local decoded = nil
    pcall(function() decoded = cliamp.json.decode(response) end)
    local attr = decoded and decoded.scrobbles and decoded.scrobbles["@attr"]
    local accepted = attr and tonumber(attr.accepted) or 0
    local ignored = attr and tonumber(attr.ignored) or 0

    if tostring(status) == "200" and accepted > 0 then
        for _ = 1, accepted do table.remove(q, 1) end
        queue_save(q)
        last_scrobble_time = os.time()
        session_scrobbles = session_scrobbles + accepted
        local label = first.artist .. " - " .. first.track
        if accepted > 1 then label = label .. " (+" .. (accepted - 1) .. " more)" end
        lastfm_message("Scrobble Sent (" .. accepted .. "): " .. label ..
            " [Session: " .. format_number(session_scrobbles) .. ", Queued: " .. #q .. "]",
            message_duration)
    elseif tostring(status) == "200" then
        for _ = 1, n do table.remove(q, 1) end
        queue_save(q)
        cliamp.log.warn("last.fm batch ignored by server (" .. tostring(ignored) ..
            " ignored): " .. tostring(response))
        lastfm_message("[last.fm] Scrobble ignored by server", message_duration)
    else
        backoff_until = os.time() + 300
        cliamp.log.warn("last.fm batch failed (kept " .. #q .. " queued): status=" ..
            tostring(status) .. ", response=" .. tostring(response))
        lastfm_message("[last.fm] Offline? Kept " .. #q .. " queued, retry later.", message_duration)
    end
    flushing = false
end

local function toggle_lastfm_mode()
    if lastfm_mode == MODE_NORMAL then
        lastfm_mode = MODE_SILENT
        cliamp.message("last.fm Silence Mode Activated", message_duration)

    elseif lastfm_mode == MODE_SILENT then
        lastfm_mode = MODE_OFF
        cliamp.message("last.fm Privacy Mode Activated", message_duration)

    else
        lastfm_mode = MODE_NORMAL
        cliamp.message("last.fm Normal Mode Activated", message_duration)
    end
end

-- Track change: close any previous live segment, publish now-playing,
-- and check loved status. Live streams get their now-playing updates from
-- playback.state as stream titles arrive.
p:on("track.change", function(track)
    has_scrobbled_current = false
    last_np_key = nil
    live_close()
    current_track_artist, current_track_title = normalize_track_meta(track)

    if not lastfm_enabled() then return end

    local dur = tonumber(track and track.duration) or 0
    local is_live = live_enabled and track and track.stream and dur == 0
    if not is_live and current_track_artist ~= "" and current_track_title ~= "" then
        update_now_playing(current_track_artist, current_track_title,
            track.album or track.Album, dur)
    end

    local delay = 0

    if os.time() - last_scrobble_time < 3 then
        delay = 2.5
    end

    if delay > 0 then
        cliamp.timer.after(delay, function()
            check_track_loved(track)
        end)
    else
        check_track_loved(track)
    end
end)

p:on("playback.state", function(data)
    if not lastfm_enabled() then return end
    local dur = get(cliamp.player.duration) or 0
    local position = data.position or get(cliamp.player.position) or 0
    local previous_artist = current_track_artist
    local previous_title = current_track_title
    local current_artist = current_track_artist and current_track_artist ~= "" and current_track_artist or nil
    local current_title = current_track_title and current_track_title ~= "" and current_track_title or nil
    local cliamp_artist = cliamp.track.artist() or ""
    local cliamp_title = cliamp.track.title() or ""
    local data_artist = data.artist or data.Artist or ""
    local data_title = data.title or data.Title or (data.track and (data.track.title or data.track.Title or data.track.track or data.track.Track)) or ""

    if data_artist ~= "" or data_title ~= "" then
        current_track_artist = data_artist ~= "" and data_artist or current_track_artist
        current_track_title = data_title ~= "" and data_title or current_track_title
        current_artist = current_track_artist and current_track_artist ~= "" and current_track_artist or nil
        current_title = current_track_title and current_track_title ~= "" and current_track_title or nil
    end

    if previous_artist and previous_title and current_track_artist and current_track_title then
        if (previous_artist ~= current_track_artist or previous_title ~= current_track_title) and has_scrobbled_current then
            has_scrobbled_current = false
        end
    end

    -- Live radio: track stream-title segments. Each new title opens a segment
    -- (with now-playing); the previous one is scrobbled if >= live_min_secs.
    local is_live = live_enabled and dur == 0 and data.status == "playing"
    if is_live then
        local seg_artist = trim(data_artist ~= "" and data_artist or cliamp_artist)
        local seg_title = trim(data_title ~= "" and data_title or cliamp_title)
        if seg_artist == "" or seg_title == "" then
            local st = data.stream_title or data.streamTitle or ""
            seg_artist, seg_title = split_stream_title(st)
        end
        if seg_artist ~= "" and seg_title ~= "" then
            current_track_artist, current_track_title = seg_artist, seg_title
            if not live_seg or live_seg.artist ~= seg_artist or live_seg.title ~= seg_title then
                live_close()
                local seg_album = data.album or data.Album or ""
                live_open(seg_artist, seg_title, seg_album, data.path)
                check_track_loved({ artist = seg_artist, title = seg_title })
            end
        end
        return
    end

    local artist = current_artist or cliamp_artist or "<unknown artist>"
    local title = current_title or cliamp_title or "<unknown title>"

    if not has_scrobbled_current and data.status == "playing" then
        local threshold = dur >= 30 and (dur - 1.5) or 30
        if position >= threshold then
            local ts = os.time() - math.floor(position)
            if do_scrobble(data, ts) then
                has_scrobbled_current = true
            end
        end
    end
end)

p:on("track.scrobble", function(track)
    if not lastfm_enabled() then return end

    local dur = get(cliamp.player.duration) or 0
    local position = track.played_secs or get(cliamp.player.position) or 0
    local threshold = 30

    if dur >= 30 then
        threshold = math.min(dur / 2, 240)
    end

    if not has_scrobbled_current and position >= threshold then
        local ts = os.time() - math.floor(position)
        if track.path and not track.path:match("^spotify:") and not track.path:match("^https?://") then
            ts = ts - 5
        end
        if do_scrobble(track, ts) then
            has_scrobbled_current = true
        end
    end
end)

p:on("playback.stop", function()
    last_np_key = nil
    live_close()
    flush_queue()
end)

p:on("app.quit", function()
    live_close()
    flush_queue()
end)

p:on("app.start", function()
    local q = queue_load()
    if #q > 0 then
        cliamp.log.info("last.fm resuming with " .. #q .. " queued scrobbles")
    end
    cliamp.timer.every(flush_interval, flush_queue)
    cliamp.timer.after(5, flush_queue)
end)

-- Keybinding: * to love/unlove current track
local success, reason = p:bind("*", "Love current track on last.fm", function(key)
    love_track()
end)

if not success then
    cliamp.log.warn("last.fm: failed to bind * - " .. tostring(reason))
end

-- Keybinding: & to cycle last.fm mode
-- Normal -> Silence -> Deactivated -> Normal
local mode_success, mode_reason = p:bind("&", "Toggle last.fm mode", function(key)
    toggle_lastfm_mode()
end)

if not mode_success then
    cliamp.log.warn("last.fm: failed to bind & - " .. tostring(mode_reason))
end