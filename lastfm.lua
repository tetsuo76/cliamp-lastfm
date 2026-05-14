local p = plugin.register({
    name = "lastfm",
    type = "hook",
    version = "1.3.0",
    description = "Scrobbles the current track to last.fm",
})

local api_key = p:config("api_key")
local api_secret = p:config("api_secret")
local session_key = p:config("session_key")
local username = p:config("username")
local API_URL = "http://ws.audioscrobbler.com/2.0/"
local has_scrobbled_current = false
local session_scrobbles = 0
local message_duration = 10

-- Helper to safely handle properties vs functions
local function get(val)
    if type(val) == "function" then return val() end
    return val
end

-- INTERNAL STATE
local function urlencode(str)
    if not str then return "" end
    str = string.gsub(str, "([^%w%.%- ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return string.gsub(str, " ", "+")
end

local function format_number(num)
    if type(num) ~= "number" then return tostring(num) end
    local str = tostring(num)
    local formatted = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if formatted:sub(1,1) == "," then formatted = formatted:sub(2) end
    return formatted
end

local function get_api_sig(params)
    local keys = {}
    for k in pairs(params) do if k ~= "format" then table.insert(keys, k) end end
    table.sort(keys)
    local str = ""
    for _, k in ipairs(keys) do str = str .. k .. params[k] end
    str = str .. api_secret
    return cliamp.crypto.md5(str)
end

local function do_scrobble(track, timestamp)
    local artist = track.artist or track.Artist or "Unknown"
    local title = track.title or track.Title or "Unknown"

    local params = {
        method = "track.scrobble",
        api_key = api_key,
        sk = session_key,
        artist = artist,
        track = title,
        timestamp = tostring(timestamp)
    }

    local sig = get_api_sig(params)
    local body_str = "method=track.scrobble" ..
                     "&api_key=" .. urlencode(api_key) ..
                     "&sk=" .. urlencode(session_key) ..
                     "&artist=" .. urlencode(artist) ..
                     "&track=" .. urlencode(title) ..
                     "&timestamp=" .. urlencode(tostring(timestamp)) ..
                     "&api_sig=" .. urlencode(sig) ..
                     "&format=json"

    -- Synchronous call returning response and status
    local response, status = cliamp.http.post(API_URL, {
        body = body_str,
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
    })

    -- UI NOTIFICATION: Concise message at the bottom
    if tostring(status) == "200" then
        session_scrobbles = session_scrobbles + 1
        local stats = ""
        if username then
            local query = "method=user.getInfo&api_key=" .. urlencode(api_key) .. "&user=" .. urlencode(username) .. "&format=json"
            local response2, status2 = cliamp.http.get(API_URL .. "?" .. query)
            local total_tracks = "?"
            local total_artists = "?"
            if tostring(status2) == "200" then
                local data = cliamp.json.decode(response2)
                if data and data.user then
                    total_tracks = tostring(data.user.playcount or "?")
                    total_artists = tostring(data.user.artist_count or "?")
                    if total_tracks ~= "?" then total_tracks = format_number(tonumber(total_tracks)) end
                    if total_artists ~= "?" then total_artists = format_number(tonumber(total_artists)) end
                end
            end
            stats = " [Tracks: " .. total_tracks .. " | Artists: " .. total_artists .. " | Session: " .. format_number(session_scrobbles) .. "]"
        else
            stats = " [No username set in config.toml]"
        end
        cliamp.message("Scrobble Sent: " .. artist .. " - " .. title .. stats, message_duration)          
    else
        local error_detail = "status=" .. tostring(status)
        if response then
            error_detail = error_detail .. ", response=" .. tostring(response)
        end
        cliamp.log.warn("last.fm scrobble failed: " .. error_detail)
        cliamp.message("[last.fm] Unable to scrobble now. Check your connection or last.fm status.", message_duration)
    end
end

-- Catch natural ends via playback position
p:on("track.change", function(track)
    has_scrobbled_current = false
end)

p:on("playback.state", function(data)
    local dur = get(cliamp.player.duration) or 0

    -- Added Check: Track must be >= 30 seconds
    if not has_scrobbled_current and dur >= 30 and data.status == "playing" then

        -- Natural end check
        if data.position >= (dur - 1.5) then
            do_scrobble(data, os.time())
            has_scrobbled_current = true
        end
    end
end)

p:on("track.scrobble", function(track)
    -- Check global duration again for the 30s rule backup
    local dur = get(cliamp.player.duration) or 0

    if not has_scrobbled_current and dur >= 30 then
        do_scrobble(track, os.time())
        has_scrobbled_current = true
    end
end)

