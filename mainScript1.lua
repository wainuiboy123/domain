-- ============================================================
--  Player Coordinate Tracker → Discord Webhook
--  Requirements:
--    • CC: Tweaked
--    • Advanced Peripherals — Player Detector
--  Setup:
--    1. Connect a Player Detector to the computer (any side).
--    2. Set WEBHOOK_URL below to your Discord webhook URL.
--    3. Adjust UPDATE_INTERVAL (seconds) as desired.
--    4. Run:  lua player_tracker.lua
-- ============================================================

local WEBHOOK_URL     = "https://discord.com/api/webhooks/1518852807694880818/tJ4d23Ba01Mc1ZekjK5yhSiLykKoKofQ2EFskPzR2rT15U8nPDhYLTNUfLm5u6a2othY"
local UPDATE_INTERVAL = 5   -- seconds between each edit
local BOT_USERNAME    = "Player Tracker"

-- ── Locate the player detector peripheral ───────────────────
local detector = peripheral.find("playerDetector")
if not detector then
    error("No Player Detector found! Make sure it is connected to this computer.", 0)
end

-- ── HTTP helper: POST (returns response body + success bool) ─
local function httpPost(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local response, err = http.post(url, payload, headers)
    if not response then
        return nil, false, err
    end
    local body = response.readAll()
    local status = response.getResponseCode()
    response.close()
    return body, (status >= 200 and status < 300), status
end

-- ── HTTP helper: PATCH (edit existing message) ───────────────
local function httpPatch(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    -- CC:Tweaked's http.request supports custom methods
    local ok, response, err = pcall(function()
        return http.request({
            url     = url,
            body    = payload,
            headers = headers,
            method  = "PATCH",
        })
    end)
    if not ok then
        return nil, false, response  -- response is the error message on pcall fail
    end

    -- http.request is async; wait for the event
    while true do
        local event, url_ev, handle = os.pullEvent()
        if event == "http_success" then
            local body   = handle.readAll()
            local status = handle.getResponseCode()
            handle.close()
            return body, (status >= 200 and status < 300), status
        elseif event == "http_failure" then
            return nil, false, handle
        end
    end
end

-- ── Build the message content string ─────────────────────────
local function buildContent(playerData)
    local lines = {}
    local now   = os.date and os.date("!%Y-%m-%d %H:%M:%S UTC") or "unknown time"

    table.insert(lines, "**🗺️ Live Player Coordinates** — *" .. now .. "*")
    table.insert(lines, "```")

    if #playerData == 0 then
        table.insert(lines, "  (no players online)")
    else
        -- Column header
        table.insert(lines, string.format("  %-20s  %7s  %5s  %7s  %s",
            "Player", "X", "Y", "Z", "Dimension"))
        table.insert(lines, "  " .. string.rep("-", 60))

        for _, p in ipairs(playerData) do
            local dim = p.dimension or "unknown"
            -- Trim the minecraft: prefix for readability
            dim = dim:gsub("^minecraft:", "")
            table.insert(lines, string.format("  %-20s  %7.1f  %5.1f  %7.1f  %s",
                p.name, p.x, p.y, p.z, dim))
        end
    end

    table.insert(lines, "```")
    table.insert(lines, "-# Updates every " .. UPDATE_INTERVAL .. "s · " .. #playerData .. " player(s) tracked")

    return table.concat(lines, "\n")
end

-- ── Gather player data from the detector ─────────────────────
local function getPlayerData()
    -- getPlayersInRange with a huge range to grab everyone on the server.
    -- Advanced Peripherals caps detection range server-side (default 100 blocks).
    -- Use getOnlinePlayers() if your AP version supports it for unlimited range.
    local players = {}

    -- Try unlimited / server-wide method first (AP ≥ 0.7.28r)
    local ok, result = pcall(function()
        return detector.getOnlinePlayers()
    end)

    if ok and result then
        -- getOnlinePlayers returns a list of names; fetch positions individually
        for _, name in ipairs(result) do
            local pos = detector.getPlayerPos(name)
            if pos then
                table.insert(players, {
                    name      = name,
                    x         = pos.x,
                    y         = pos.y,
                    z         = pos.z,
                    dimension = pos.dimension,
                })
            end
        end
    else
        -- Fallback: getPlayersInRange (limited to configured server range)
        local range = 100000  -- very large; capped by server config
        local inRange = detector.getPlayersInRange(range)
        if inRange then
            for _, name in ipairs(inRange) do
                local pos = detector.getPlayerPos(name)
                if pos then
                    table.insert(players, {
                        name      = name,
                        x         = pos.x,
                        y         = pos.y,
                        z         = pos.z,
                        dimension = pos.dimension,
                    })
                end
            end
        end
    end

    -- Sort alphabetically for a stable display order
    table.sort(players, function(a, b) return a.name < b.name end)
    return players
end

-- ── Send the initial message and capture its ID ──────────────
local function sendInitialMessage(content)
    local payload = textutils.serialiseJSON({
        username = BOT_USERNAME,
        content  = content,
    })

    -- Append ?wait=true so Discord returns the full message object with an id
    local body, success, status = httpPost(WEBHOOK_URL .. "?wait=true", payload)

    if not success then
        error("Failed to send initial message. HTTP status: " .. tostring(status) ..
              "\nBody: " .. tostring(body), 0)
    end

    local msg = textutils.unserialiseJSON(body)
    if not msg or not msg.id then
        error("Discord did not return a message ID. Response: " .. tostring(body), 0)
    end

    return msg.id
end

-- ── Edit an existing webhook message ─────────────────────────
local function editMessage(messageId, content)
    local editUrl = WEBHOOK_URL .. "/messages/" .. messageId
    local payload = textutils.serialiseJSON({ content = content })
    local body, success, status = httpPatch(editUrl, payload)
    if not success then
        print("[WARN] Edit failed (HTTP " .. tostring(status) .. "): " .. tostring(body))
    end
    return success
end

-- ── Main ──────────────────────────────────────────────────────
print("=== Player Tracker Starting ===")
print("Detector: " .. peripheral.getName(detector))
print("Interval: " .. UPDATE_INTERVAL .. "s")
print("")

if not http then
    error("HTTP is disabled! Enable it in the ComputerCraft config.", 0)
end

-- Send the first message
local playerData    = getPlayerData()
local content       = buildContent(playerData)
local messageId     = sendInitialMessage(content)

print("Initial message sent! ID: " .. messageId)
print("Now editing every " .. UPDATE_INTERVAL .. " seconds. Press Ctrl+T to stop.")
print("")

-- Main update loop
while true do
    sleep(UPDATE_INTERVAL)

    local ok, err = pcall(function()
        playerData = getPlayerData()
        content    = buildContent(playerData)
        editMessage(messageId, content)
    end)

    if ok then
        print("[" .. os.time() .. "] Updated — " .. #playerData .. " player(s) online")
    else
        print("[ERROR] " .. tostring(err))
    end
end
