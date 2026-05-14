local p = plugin.register({
    name = "lastfm",
    type = "hook",
    version = "1.4.0",
    description = "Scrobbles the current track to last.fm",
    permissions = {"keymap"},
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

local function check_track_loved(track)
    if not username then return end
    
    local artist = track.artist or track.Artist or ""
    local title = track.title or track.Title or ""
    
    if artist == "" or title == "" then return end
    
    -- Call track.getInfo to check if loved
    local query = "method=track.getInfo" ..
                  "&api_key=" .. urlencode(api_key) ..
                  "&artist=" .. urlencode(artist) ..
                  "&track=" .. urlencode(title) ..
                  "&username=" .. urlencode(username) ..
                  "&format=json"
    
    local response, status = cliamp.http.get(API_URL .. "?" .. query)
    
    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)
        if data and data.track and data.track.userloved == "1" then
            cliamp.message("♥ Loved Track: " .. artist .. " - " .. title, message_duration)
        end
    end
end

local function is_track_loved(artist, title)
    if not username then return false end
    
    local query = "method=track.getInfo" ..
                  "&api_key=" .. urlencode(api_key) ..
                  "&artist=" .. urlencode(artist) ..
                  "&track=" .. urlencode(title) ..
                  "&username=" .. urlencode(username) ..
                  "&format=json"
    
    local response, status = cliamp.http.get(API_URL .. "?" .. query)
    
    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)
        if data and data.track and data.track.userloved == "1" then
            return true
        end
    end
    return false
end

local function unlove_track()
    if not username or not session_key then
        cliamp.message("[last.fm] Not configured", message_duration)
        return
    end
    
    local artist = cliamp.track.artist()
    local title = cliamp.track.title()
    
    if not artist or not title then
        cliamp.message("[last.fm] No track playing", message_duration)
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
    local body_str = "method=track.unlove" ..
                     "&api_key=" .. urlencode(api_key) ..
                     "&sk=" .. urlencode(session_key) ..
                     "&artist=" .. urlencode(artist) ..
                     "&track=" .. urlencode(title) ..
                     "&api_sig=" .. urlencode(sig) ..
                     "&format=json"
    
    local response, status = cliamp.http.post(API_URL, {
        body = body_str,
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
    })
    
    cliamp.log.debug("last.fm unlove response: status=" .. tostring(status) .. ", body=" .. tostring(response))
    
    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)
        if data and (data.lfm == nil or next(data) == nil) then
            cliamp.message("♡ Unloved: " .. artist .. " - " .. title, message_duration)
        elseif data and data.error then
            cliamp.log.warn("last.fm unlove failed: error code " .. tostring(data.error) .. " - " .. tostring(data.message))
            cliamp.message("[last.fm] Error: " .. tostring(data.message), message_duration)
        else
            cliamp.log.warn("last.fm unlove unexpected response: " .. tostring(response))
            cliamp.message("[last.fm] Unexpected response", message_duration)
        end
    else
        local error_detail = "status=" .. tostring(status)
        if response then
            error_detail = error_detail .. ", response=" .. tostring(response)
        end
        cliamp.log.warn("last.fm unlove failed: " .. error_detail)
        cliamp.message("[last.fm] Unable to unlove track now", message_duration)
    end
end

local function love_track()
    if not username or not session_key then
        cliamp.message("[last.fm] Not configured", message_duration)
        return
    end
    
    local artist = cliamp.track.artist()
    local title = cliamp.track.title()
    
    if not artist or not title then
        cliamp.message("[last.fm] No track playing", message_duration)
        return
    end
    
    -- Check if track is already loved, toggle accordingly
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
    local body_str = "method=track.love" ..
                     "&api_key=" .. urlencode(api_key) ..
                     "&sk=" .. urlencode(session_key) ..
                     "&artist=" .. urlencode(artist) ..
                     "&track=" .. urlencode(title) ..
                     "&api_sig=" .. urlencode(sig) ..
                     "&format=json"
    
    local response, status = cliamp.http.post(API_URL, {
        body = body_str,
        headers = { ["Content-Type"] = "application/x-www-form-urlencoded" }
    })
    
    cliamp.log.debug("last.fm love response: status=" .. tostring(status) .. ", body=" .. tostring(response))
    
    if tostring(status) == "200" then
        local data = cliamp.json.decode(response)
        if data and data.lfm and data.lfm.status == "ok" then
            cliamp.message("♥ Loved: " .. artist .. " - " .. title, message_duration)
        elseif data and (data.lfm == nil or next(data) == nil) then
            -- Empty response means success for track.love
            cliamp.message("♥ Loved: " .. artist .. " - " .. title, message_duration)
        elseif data and data.error then
            cliamp.log.warn("last.fm love failed: error code " .. tostring(data.error) .. " - " .. tostring(data.message))
            cliamp.message("[last.fm] Error: " .. tostring(data.message), message_duration)
        else
            cliamp.log.warn("last.fm love unexpected response: " .. tostring(response))
            cliamp.message("[last.fm] Unexpected response", message_duration)
        end
    else
        local error_detail = "status=" .. tostring(status)
        if response then
            error_detail = error_detail .. ", response=" .. tostring(response)
        end
        cliamp.log.warn("last.fm love failed: " .. error_detail)
        cliamp.message("[last.fm] Unable to love track now", message_duration)
    end
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
    check_track_loved(track)
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

-- Keybinding: * to love current track
local success, reason = p:bind("*", "Love current track on last.fm", function(key)
    love_track()
end)

if not success then
    cliamp.log.warn("last.fm: failed to bind * - " .. tostring(reason))
end

