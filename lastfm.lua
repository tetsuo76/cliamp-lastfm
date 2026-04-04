local p = plugin.register({
    name = "lastfm",
    type = "hook",
    version = "1.0.1",
    description = "Scrobbles the current track to last.fm",
})

local API_KEY = "YOUR_API_KEY"
local API_SECRET = "YOUR_API_SECRET"
local SESSION_KEY = "YOUR_SESSION_KEY"
local API_URL = "http://ws.audioscrobbler.com/2.0/"

-- INTERNAL STATE
local current_timer_id = nil

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
        print("\27[s\27[999;1H[Last.fm] Scrobble Sent: " .. artist .. " - " .. title .. "\27[u")
    else
        print("\27[s\27[999;1H[Last.fm] Error: HTTP " .. tostring(status) .. "\27[u")
    end
end

p:on("track.change", function(track)
    if not track then return end

    -- Cancel previous timer if you skipped a song early
    if current_timer_id then
        cliamp.timer.cancel(current_timer_id)
    end

    local start_time = os.time()
    -- Use the ANSI escape codes to force the message to the bottom
    print("\27[s\27[999;1H[Last.fm] Track detected. Scrobbling in 60s...\27[u")

    current_timer_id = cliamp.timer.after(60.0, function()
        do_scrobble(track, start_time)
        current_timer_id = nil 
    end)
end)


