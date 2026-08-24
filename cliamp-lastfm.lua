local p = plugin.register({
    name = "lastfm",
    type = "hook",
    version = "2.0.0",
    description = "Scrobbles the current track to last.fm",
    permissions = {"keymap"},
})

local api_key = p:config("api_key")
local api_secret = p:config("api_secret")
local session_key = p:config("session_key")
local username = p:config("username")

-- Optional configuration
local scrobble_mode = tostring(p:config("scrobble_mode") or "played")
local scrobble_percent = tonumber(p:config("scrobble_percent")) or 50
local scrobble_seconds = tonumber(p:config("scrobble_seconds")) or 120
local scrobble_max_seconds = tonumber(p:config("scrobble_max_seconds")) or 240
local now_playing_enabled = p:config("now_playing")

if now_playing_enabled == nil then
    now_playing_enabled = true
elseif type(now_playing_enabled) == "string" then
    now_playing_enabled =
        now_playing_enabled == "true" or
        now_playing_enabled == "1" or
        now_playing_enabled == "yes"
end

local message_duration = tonumber(p:config("message_duration")) or 10

local show_stats = p:config("show_stats")

if show_stats == nil then
    show_stats = true
elseif type(show_stats) == "string" then
    show_stats =
        show_stats == "true" or
        show_stats == "1" or
        show_stats == "yes"
end

local API_URL = "https://ws.audioscrobbler.com/2.0/"

-- Current track state
local current_track_artist = nil
local current_track_title = nil
local current_track_album = nil
local current_track_path = nil
local current_track_duration = 0

-- Playback tracking
local current_track_id = nil
local track_start_timestamp = nil
local last_position = nil
local actual_played_seconds = 0
local has_scrobbled_current = false
local last_playback_status = nil

-- Session information
local session_scrobbles = 0
local last_scrobble_time = 0

-- Last.fm modes
local MODE_NORMAL = "normal"
local MODE_SILENT = "silent"
local MODE_OFF = "off"

local lastfm_mode = MODE_NORMAL


----------------------------------------------------------------------
-- General helpers
----------------------------------------------------------------------

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

local function get(val)
    if type(val) == "function" then
        return val()
    end

    return val
end

local function normalize_string(value)
    if value == nil then
        return ""
    end

    return tostring(value):match("^%s*(.-)%s*$") or ""
end

local function normalize_track_meta(track)
    if not track then
        return "", "", ""
    end

    local artist =
        track.artist or
        track.Artist or
        track.artist_name or
        track.ArtistName or
        ""

    local title =
        track.title or
        track.Title or
        track.track or
        track.Track or
        ""

    local album =
        track.album or
        track.Album or
        ""

    return
        normalize_string(artist),
        normalize_string(title),
        normalize_string(album)
end

local function build_track_id(artist, title, path)
    return
        normalize_string(artist) ..
        "\0" ..
        normalize_string(title) ..
        "\0" ..
        normalize_string(path)
end

local function format_number(num)
    if type(num) ~= "number" then
        return tostring(num)
    end

    local str = tostring(math.floor(num))

    local formatted =
        str:reverse():gsub("(%d%d%d)", "%1,"):reverse()

    if formatted:sub(1, 1) == "," then
        formatted = formatted:sub(2)
    end

    return formatted
end

local function format_seconds(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))

    local minutes = math.floor(seconds / 60)
    local secs = seconds % 60

    return string.format("%d:%02d", minutes, secs)
end


----------------------------------------------------------------------
-- URL / API helpers
----------------------------------------------------------------------

local function urlencode(str)
    if not str then
        return ""
    end

    str = tostring(str)

    str = string.gsub(
        str,
        "([^%w%.%- ])",
        function(c)
            return string.format("%%%02X", string.byte(c))
        end
    )

    return string.gsub(str, " ", "+")
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
        table.insert(
            parts,
            urlencode(k) .. "=" .. urlencode(v)
        )
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
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        }
    })
end


----------------------------------------------------------------------
-- Current track metadata
----------------------------------------------------------------------

local function get_current_track_meta()
    local artist =
        current_track_artist or
        cliamp.track.artist() or
        ""

    local title =
        current_track_title or
        cliamp.track.title() or
        ""

    local album = current_track_album or ""

    return
        normalize_string(artist),
        normalize_string(title),
        normalize_string(album)
end


----------------------------------------------------------------------
-- Last.fm track information
----------------------------------------------------------------------

local function check_track_loved(track)
    if not lastfm_enabled() then
        return
    end

    if not username then
        return
    end

    local artist, title =
        normalize_track_meta(track)

    if artist == "" or title == "" then
        return
    end

    local response, status =
        lastfm_get(
            API_URL ..
            "?" ..
            build_query_string({
                method = "track.getInfo",
                api_key = api_key,
                artist = artist,
                track = title,
                username = username,
                format = "json",
            })
        )

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and
           data.track and
           data.track.userloved == "1" then

            lastfm_message(
                "♥ Loved Track: " ..
                artist ..
                " - " ..
                title,
                message_duration
            )
        end
    end
end

local function is_track_loved(artist, title)
    if not lastfm_enabled() then
        return false
    end

    if not username then
        return false
    end

    local response, status =
        lastfm_get(
            API_URL ..
            "?" ..
            build_query_string({
                method = "track.getInfo",
                api_key = api_key,
                artist = artist,
                track = title,
                username = username,
                format = "json",
            })
        )

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and
           data.track and
           data.track.userloved == "1" then

            return true
        end
    end

    return false
end

local function get_track_scrobble_count(artist, title)
    if not lastfm_enabled() then
        return "?"
    end

    if not username then
        return "?"
    end

    local response, status =
        lastfm_get(
            API_URL ..
            "?" ..
            build_query_string({
                method = "track.getInfo",
                api_key = api_key,
                artist = artist,
                track = title,
                username = username,
                format = "json",
            })
        )

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and
           data.track and
           data.track.userplaycount then

            local count =
                tonumber(data.track.userplaycount)

            if count then
                return format_number(count)
            end
        end
    end

    return "0"
end

local function get_user_stats()
    if not username then
        return "?", "?"
    end

    local response, status =
        lastfm_get(
            API_URL ..
            "?" ..
            build_query_string({
                method = "user.getInfo",
                api_key = api_key,
                user = username,
                format = "json",
            })
        )

    if tostring(status) ~= "200" then
        return "?", "?"
    end

    local data = cliamp.json.decode(response)

    if not data or not data.user then
        return "?", "?"
    end

    local total_tracks =
        tonumber(data.user.playcount)

    local total_artists =
        tonumber(data.user.artist_count)

    if total_tracks then
        total_tracks = format_number(total_tracks)
    else
        total_tracks = "?"
    end

    if total_artists then
        total_artists = format_number(total_artists)
    else
        total_artists = "?"
    end

    return total_tracks, total_artists
end

local function get_user_loved_count()
    if not lastfm_enabled() then
        return "?"
    end

    if not username then
        return "?"
    end

    local response, status =
        lastfm_get(
            API_URL ..
            "?" ..
            build_query_string({
                method = "user.getLovedTracks",
                api_key = api_key,
                user = username,
                limit = 1,
                format = "json",
            })
        )

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and
           data.lovedtracks and
           data.lovedtracks["@attr"] and
           data.lovedtracks["@attr"].total then

            local count =
                tonumber(data.lovedtracks["@attr"].total)

            if count then
                return format_number(count)
            end
        end
    end

    return "?"
end


----------------------------------------------------------------------
-- Now Playing
----------------------------------------------------------------------

local function update_now_playing()
    if not lastfm_enabled() then
        return
    end

    if not now_playing_enabled then
        return
    end

    if not api_key or
       not api_secret or
       not session_key then

        return
    end

    local artist, title, album =
        get_current_track_meta()

    if artist == "" or title == "" then
        return
    end

    local params = {
        method = "track.updateNowPlaying",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title,
    }

    if album ~= "" then
        params.album = album
    end

    local sig = get_api_sig(params)

    params.api_sig = sig

    local response, status =
        lastfm_post(params)

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and data.nowplaying then
            cliamp.log.info(
                "last.fm now playing: " ..
                artist ..
                " - " ..
                title
            )
        else
            cliamp.log.warn(
                "last.fm now playing unexpected response: " ..
                tostring(response)
            )
        end
    else
        cliamp.log.warn(
            "last.fm now playing failed: status=" ..
            tostring(status)
        )
    end
end


----------------------------------------------------------------------
-- Love / Unlove
----------------------------------------------------------------------

local function unlove_track()
    if not lastfm_enabled() then
        return
    end

    if not username or not session_key then
        lastfm_message(
            "[last.fm] Not configured",
            message_duration
        )

        return
    end

    local artist, title =
        get_current_track_meta()

    if artist == "" or title == "" then
        lastfm_message(
            "[last.fm] No track playing",
            message_duration
        )

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

    local response, status =
        lastfm_post({
            method = "track.unlove",
            api_key = api_key,
            sk = session_key,
            artist = artist,
            track = title,
            api_sig = sig,
        })

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and
           (data.lfm == nil or next(data) == nil) then

            lastfm_message(
                "♡ Unloved: " ..
                artist ..
                " - " ..
                title,
                message_duration
            )

        elseif data and data.error then

            cliamp.log.warn(
                "last.fm unlove failed: error code " ..
                tostring(data.error) ..
                " - " ..
                tostring(data.message)
            )

            lastfm_message(
                "[last.fm] Error: " ..
                tostring(data.message),
                message_duration
            )
        else
            cliamp.log.warn(
                "last.fm unlove unexpected response: " ..
                tostring(response)
            )

            lastfm_message(
                "[last.fm] Unexpected response",
                message_duration
            )
        end
    else
        cliamp.log.warn(
            "last.fm unlove failed: status=" ..
            tostring(status)
        )

        lastfm_message(
            "[last.fm] Unable to unlove track now",
            message_duration
        )
    end
end

local function love_track()
    if not lastfm_enabled() then
        return
    end

    if not username or not session_key then
        lastfm_message(
            "[last.fm] Not configured",
            message_duration
        )

        return
    end

    local artist, title =
        get_current_track_meta()

    if artist == "" or title == "" then
        lastfm_message(
            "[last.fm] No track playing",
            message_duration
        )

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

    local response, status =
        lastfm_post({
            method = "track.love",
            api_key = api_key,
            sk = session_key,
            artist = artist,
            track = title,
            api_sig = sig,
        })

    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)

        if data and
           data.lfm and
           data.lfm.status == "ok" then

            lastfm_message(
                "♥ Loved: " ..
                artist ..
                " - " ..
                title,
                message_duration
            )

        elseif data and data.error then

            cliamp.log.warn(
                "last.fm love failed: error code " ..
                tostring(data.error) ..
                " - " ..
                tostring(data.message)
            )

            lastfm_message(
                "[last.fm] Error: " ..
                tostring(data.message),
                message_duration
            )
        else
            lastfm_message(
                "♥ Loved: " ..
                artist ..
                " - " ..
                title,
                message_duration
            )
        end
    else
        cliamp.log.warn(
            "last.fm love failed: status=" ..
            tostring(status)
        )

        lastfm_message(
            "[last.fm] Unable to love track now",
            message_duration
        )
    end
end


----------------------------------------------------------------------
-- Scrobble threshold
----------------------------------------------------------------------

local function get_position_threshold(duration)
    duration = tonumber(duration) or 0

    if duration <= 0 then
        return nil
    end

    if scrobble_mode == "seconds" then
        return math.min(
            scrobble_seconds,
            duration
        )
    end

    if scrobble_mode == "percent" then
        local percent =
            math.max(
                1,
                math.min(
                    100,
                    scrobble_percent
                )
            )

        return duration * (percent / 100)
    end

    if scrobble_mode == "lastfm" then
        return math.min(
            duration / 2,
            scrobble_max_seconds
        )
    end

    -- "played" mode does not use playback position.
    return nil
end

local function get_played_threshold()
    if scrobble_mode == "played" then
        return math.max(
            1,
            scrobble_seconds
        )
    end

    return nil
end


----------------------------------------------------------------------
-- Scrobble
----------------------------------------------------------------------

local function do_scrobble(track, timestamp)
    if not lastfm_enabled() then
        return false
    end

    if not username or not session_key then
        lastfm_message(
            "[last.fm] Not configured",
            message_duration
        )

        return false
    end

    local artist, title, album =
        normalize_track_meta(track)

    if artist == "" or title == "" then
        artist, title, album =
            get_current_track_meta()
    end

    if artist == "" or title == "" then
        lastfm_message(
            "[last.fm] No track metadata",
            message_duration
        )

        return false
    end

    if not timestamp then
        timestamp =
            track_start_timestamp or
            (os.time() - math.floor(last_position or 0))
    end

    local function post_scrobble_request(params)
        local request_params = {}

        for k, v in pairs(params) do
            if k ~= "api_sig" then
                request_params[k] = v
            end
        end

        local sig =
            get_api_sig(request_params)

        request_params.api_sig = sig

        local response, status =
            lastfm_post(request_params)

        local decoded = nil

        pcall(function()
            decoded =
                cliamp.json.decode(response)
        end)

        return response, status, decoded
    end

    local params = {
        method = "track.scrobble",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title,
        timestamp = tostring(timestamp)
    }

    if album ~= "" then
        params.album = album
    end

    local response, status, decoded =
        post_scrobble_request(params)

    local accepted =
        decoded and
        decoded.scrobbles and
        decoded.scrobbles["@attr"] and
        tonumber(
            decoded.scrobbles["@attr"].accepted
        )

    local ignored =
        decoded and
        decoded.scrobbles and
        decoded.scrobbles["@attr"] and
        tonumber(
            decoded.scrobbles["@attr"].ignored
        )

    local ignored_code =
        decoded and
        decoded.scrobbles and
        decoded.scrobbles.scrobble and
        decoded.scrobbles.scrobble.ignoredMessage and
        decoded.scrobbles.scrobble.ignoredMessage.code

    -- Last.fm sometimes rejects a timestamp as too close
    -- to a previous scrobble. Retry slightly earlier.
    if tostring(status) == "200" and
       accepted == 0 and
       ignored == 1 and
       tostring(ignored_code) == "1" then

        local retry_ts = timestamp - 10

        if retry_ts ~= timestamp then
            params.timestamp = tostring(retry_ts)

            response, status, decoded =
                post_scrobble_request(params)

            accepted =
                decoded and
                decoded.scrobbles and
                decoded.scrobbles["@attr"] and
                tonumber(
                    decoded.scrobbles["@attr"].accepted
                )
        end
    end

    if tostring(status) == "200" and accepted == 1 then
        last_scrobble_time = os.time()
        session_scrobbles =
            session_scrobbles + 1

        local scrobble_count =
            get_track_scrobble_count(
                artist,
                title
            )

        local total_tracks = "?"
        local total_artists = "?"
        local loved_count = "?"

        if show_stats and username then
            total_tracks, total_artists =
                get_user_stats()

            loved_count =
                get_user_loved_count()
        end

        local played_display =
            format_seconds(actual_played_seconds)

        local primary_message =
            "✓ Scrobbled: " ..
            artist ..
            " - " ..
            title ..
            " [" ..
            played_display ..
            " played]"

        if scrobble_count ~= "?" then
            primary_message =
                primary_message ..
                " [Total: " ..
                tostring(scrobble_count) ..
                "]"
        end

        lastfm_message(
            primary_message,
            message_duration
        )

        if show_stats then
            local stats_message =
                "[Tracks: " ..
                total_tracks ..
                " | Artists: " ..
                total_artists ..
                " | Loved: " ..
                loved_count ..
                " | Session: " ..
                format_number(session_scrobbles) ..
                "]"

            cliamp.timer.after(
                message_duration,
                function()
                    lastfm_message(
                        stats_message,
                        message_duration
                    )
                end
            )
        end

        return true
    end

    local error_detail =
        "status=" ..
        tostring(status)

    if response then
        error_detail =
            error_detail ..
            ", response=" ..
            tostring(response)
    end

    if tostring(status) == "200" and
       accepted == 0 then

        cliamp.log.warn(
            "last.fm scrobble ignored: " ..
            error_detail
        )

        lastfm_message(
            "[last.fm] Scrobble ignored by server",
            message_duration
        )
    else
        cliamp.log.warn(
            "last.fm scrobble failed: " ..
            error_detail
        )

        lastfm_message(
            "[last.fm] Unable to scrobble now. " ..
            "Check your connection or last.fm status.",
            message_duration
        )
    end

    return false
end


----------------------------------------------------------------------
-- Track state
----------------------------------------------------------------------

local function reset_track_state(track)
    local artist, title, album =
        normalize_track_meta(track)

    local path =
        track and
        track.path and
        tostring(track.path) or
        ""

    current_track_artist = artist
    current_track_title = title
    current_track_album = album
    current_track_path = path

    current_track_duration =
        tonumber(
            track and
            (track.duration or track.Duration)
        ) or
        tonumber(
            get(cliamp.player.duration)
        ) or
        0

    current_track_id =
        build_track_id(
            artist,
            title,
            path
        )

    track_start_timestamp = os.time()

    last_position = 0
    actual_played_seconds = 0
    has_scrobbled_current = false
    last_playback_status = nil
end


----------------------------------------------------------------------
-- Manual scrobble
----------------------------------------------------------------------

local function manual_scrobble()
    if not lastfm_enabled() then
        return
    end

    local artist, title, album =
        get_current_track_meta()

    if artist == "" or title == "" then
        lastfm_message(
            "[last.fm] No track playing",
            message_duration
        )

        return
    end

    if has_scrobbled_current then
        lastfm_message(
            "[last.fm] Track already scrobbled",
            message_duration
        )

        return
    end

    local timestamp =
        track_start_timestamp or
        (os.time() - math.floor(last_position or 0))

    if do_scrobble(
        {
            artist = artist,
            title = title,
            album = album,
            path = current_track_path
        },
        timestamp
    ) then

        has_scrobbled_current = true
    end
end


----------------------------------------------------------------------
-- Mode control
----------------------------------------------------------------------

local function toggle_lastfm_mode()
    if lastfm_mode == MODE_NORMAL then
        lastfm_mode = MODE_SILENT

        cliamp.message(
            "last.fm Silence Mode Activated",
            message_duration
        )

    elseif lastfm_mode == MODE_SILENT then
        lastfm_mode = MODE_OFF

        cliamp.message(
            "last.fm Privacy Mode Activated",
            message_duration
        )

    else
        lastfm_mode = MODE_NORMAL

        cliamp.message(
            "last.fm Normal Mode Activated",
            message_duration
        )
    end
end


----------------------------------------------------------------------
-- Track change
----------------------------------------------------------------------

p:on("track.change", function(track)
    if not track then
        return
    end

    reset_track_state(track)

    if not lastfm_enabled() then
        return
    end

    -- Give cliamp a moment to settle the track metadata.
    cliamp.timer.after(0.25, function()
        if not lastfm_enabled() then
            return
        end

        local artist, title =
            get_current_track_meta()

        if artist == "" or title == "" then
            return
        end

        -- Now Playing is intentionally sent immediately.
        update_now_playing()

        -- Check whether the track is loved.
        check_track_loved({
            artist = artist,
            title = title,
            album = current_track_album,
        })
    end)
end)


----------------------------------------------------------------------
-- Playback tracking
----------------------------------------------------------------------

p:on("playback.state", function(data)
    if not lastfm_enabled() then
        return
    end

    if not data then
        return
    end

    local status =
        tostring(data.status or "")

    local position =
        tonumber(data.position) or
        tonumber(get(cliamp.player.position)) or
        0

    local duration =
        tonumber(get(cliamp.player.duration)) or
        current_track_duration or
        0

    if duration > 0 then
        current_track_duration = duration
    end

    -- Pick up metadata if track.change didn't provide it.
    local data_artist =
        data.artist or
        data.Artist or
        ""

    local data_title =
        data.title or
        data.Title or
        ""

    if data_artist ~= "" then
        current_track_artist =
            normalize_string(data_artist)
    end

    if data_title ~= "" then
        current_track_title =
            normalize_string(data_title)
    end

    -- Establish a track start time if necessary.
    if not track_start_timestamp then
        track_start_timestamp =
            os.time() -
            math.floor(position)
    end

    -- First playback event for this track.
    if last_position == nil then
        last_position = position
    end

    -- Actual listening time tracking.
    if status == "playing" then
        local delta =
            position - (last_position or position)

        -- Normal playback advances roughly once per event.
        --
        -- If the position jumps forward significantly, treat
        -- that as a seek rather than listened time.
        if delta >= 0 and delta <= 3 then
            actual_played_seconds =
                actual_played_seconds + delta
        end

        -- If we resumed after a pause, don't count the time
        -- spent paused.
        if last_playback_status == "paused" then
            last_position = position
        end
    end

    last_position = position

    ------------------------------------------------------------------
    -- Scrobble threshold
    ------------------------------------------------------------------

    if has_scrobbled_current then
        last_playback_status = status
        return
    end

    if status ~= "playing" then
        last_playback_status = status
        return
    end

    local should_scrobble = false

    if scrobble_mode == "played" then
        local threshold =
            get_played_threshold()

        if threshold and
           actual_played_seconds >= threshold then

            should_scrobble = true
        end

    else
        local threshold =
            get_position_threshold(duration)

        if threshold and
           position >= threshold then

            should_scrobble = true
        end
    end

    if should_scrobble then
        local artist, title, album =
            get_current_track_meta()

        local track = {
            artist = artist,
            title = title,
            album = album,
            path = current_track_path
        }

        local timestamp =
            track_start_timestamp or
            (os.time() - math.floor(position))

        if do_scrobble(
            track,
            timestamp
        ) then

            has_scrobbled_current = true
        end
    end

    last_playback_status = status
end)


----------------------------------------------------------------------
-- Keybindings
----------------------------------------------------------------------

-- * = love/unlove
local success, reason =
    p:bind(
        "*",
        "Love current track on last.fm",
        function(key)
            love_track()
        end
    )

if not success then
    cliamp.log.warn(
        "last.fm: failed to bind * - " ..
        tostring(reason)
    )
end


-- & = mode
local mode_success, mode_reason =
    p:bind(
        "&",
        "Toggle last.fm mode",
        function(key)
            toggle_lastfm_mode()
        end
    )

if not mode_success then
    cliamp.log.warn(
        "last.fm: failed to bind & - " ..
        tostring(mode_reason)
    )
end


-- S = manual scrobble
local scrobble_success, scrobble_reason =
    p:bind(
        "Ctrl+L",
        "Scrobble current track now",
        function(key)
            manual_scrobble()
        end
    )

if not scrobble_success then
    cliamp.log.warn(
        "last.fm: failed to bind S - " ..
        tostring(scrobble_reason)
    )
end