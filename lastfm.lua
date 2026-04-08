local p = plugin.register({
    name = "lastfm",
    type = "hook",
    version = "1.1.1",
    description = "Scrobbles the current track to last.fm",
})

local API_KEY = "YOUR_API_KEY"
local API_SECRET = "YOUR_API_SECRET"
local SESSION_KEY = "YOUR_SESSION_KEY"
local API_URL = "http://ws.audioscrobbler.com/2.0/"

local has_scrobbled_current = false

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

local function get_api_sig(params)
    local keys = {}
    for k in pairs(params) do if k ~= "format" then table.insert(keys, k) end end
    table.sort(keys)
    local str = ""
    for _, k in ipairs(keys) do str = str .. k .. params[k] end
    str = str .. API_SECRET
    return cliamp.crypto.md5(str)
end

local function do_scrobble(track, timestamp)
    local artist = track.artist or track.Artist or "Unknown"
    local title = track.title or track.Title or "Unknown"

    local params = {
        method = "track.scrobble",
        api_key = API_KEY,
        sk = SESSION_KEY,
        artist = artist,
        track = title,
        timestamp = tostring(timestamp)
    }

    local sig = get_api_sig(params)
    local body_str = "method=track.scrobble" ..
                     "&api_key=" .. urlencode(API_KEY) ..
                     "&sk=" .. urlencode(SESSION_KEY) ..
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
        print("\27[s\27[999;1H[last.fm] Scrobble Sent: " .. artist .. " - " .. title .. "\27[u")
    else
        cliamp.log.warn("last.fm scrobble failed: " .. tostring(status))
        print("\27[s\27[999;1H[last.fm] Error: HTTP " .. tostring(status) .. "\27[u")
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
