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
local UPDATE_INTERVAL = 0.5   -- seconds between each edit
local BOT_USERNAME    = "Player Tracker"

-- ── Locate the player detector peripheral ───────────────────
local detector = peripheral.find("player_detector")
if not detector then
    error("No Player Detector found! Make sure it is connected to this computer.", 0)
end

-- ── Get the detector's own block position ───────────────────
-- Used as the origin for distance calculations.
local detectorName = peripheral.getName(detector)
local detectorPos  = vector.new(0, 0, 0)

local ok, bpos = pcall(function()
    return peripheral.call(detectorName, "getBlockPos") -- AP 0.7.30r+
end)
if ok and bpos then
    detectorPos = vector.new(bpos.x, bpos.y, bpos.z)
    print("Detector position: " .. bpos.x .. ", " .. bpos.y .. ", " .. bpos.z)
else
    -- Fallback: ask the user to set it manually
    print("[WARN] Could not auto-detect detector position.")
    print("Enter detector X (or 0 to skip distance sorting): ")
    local x = tonumber(read()) or 0
    if x ~= 0 then
        print("Enter detector Y: ")
        local y = tonumber(read()) or 0
        print("Enter detector Z: ")
        local z = tonumber(read()) or 0
        detectorPos = vector.new(x, y, z)
    end
end

-- ── Distance helper ──────────────────────────────────────────
local function distance3D(x, y, z)
    local dx = x - detectorPos.x
    local dy = y - detectorPos.y
    local dz = z - detectorPos.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- ── HTTP helper: POST ────────────────────────────────────────
local function httpPost(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local response = http.post(url, payload, headers)
    if not response then
        return nil, false, "no response"
    end
    local body   = response.readAll()
    local status = response.getResponseCode()
    response.close()
    return body, (status >= 200 and status < 300), status
end

-- ── HTTP helper: PATCH ───────────────────────────────────────
local function httpPatch(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local ok = pcall(function()
        http.request({
            url     = url,
            body    = payload,
            headers = headers,
            method  = "PATCH",
        })
    end)
    if not ok then return nil, false, "request failed" end

    while true do
        local event, _, handle = os.pullEvent()
        if event == "http_success" then
            local body   = handle.readAll()
            local status = handle.getResponseCode()
            handle.close()
            return body, (status >= 200 and status < 300), status
        elseif event == "http_failure" then
            return nil, false, "http_failure"
        end
    end
end

-- ── Build the Discord message ────────────────────────────────
local function buildContent(playerData)
    local lines = {}
    local now   = os.date and os.date("!%Y-%m-%d %H:%M:%S UTC") or "unknown time"

    table.insert(lines, "**🗺️ Live Player Coordinates** — *" .. now .. "*")
    table.insert(lines, "```")

    if #playerData == 0 then
        table.insert(lines, "  (no players online)")
    else
        table.insert(lines, string.format("  %-16s  %7s  %5s  %7s  %8s  %s",
            "Player", "X", "Y", "Z", "Dist", "Dimension"))
        table.insert(lines, "  " .. string.rep("-", 68))

        for i, p in ipairs(playerData) do
            local dim  = (p.dimension or "unknown"):gsub("^minecraft:", "")
            local dist = string.format("%.1fm", p.distance)
            -- Add a rank medal for the top 3 closest
            local rank = (i == 1 and "#1 ") or (i == 2 and "#2 ") or (i == 3 and "#3 ") or "   "
            table.insert(lines, string.format("  %s%-16s  %7.1f  %5.1f  %7.1f  %8s  %s",
                rank, p.name, p.x, p.y, p.z, dist, dim))
        end
    end

    table.insert(lines, "```")
    table.insert(lines, string.format(
        "-# Updates every %ds · %d player(s) · Detector @ %d, %d, %d",
        UPDATE_INTERVAL, #playerData,
        detectorPos.x, detectorPos.y, detectorPos.z
    ))

    return table.concat(lines, "\n")
end

-- ── Gather + sort player data ────────────────────────────────
local function getPlayerData()
    local players = {}

    -- Try server-wide method first (AP ≥ 0.7.28r)
    local ok, result = pcall(function() return detector.getOnlinePlayers() end)

    local names = {}
    if ok and result then
        names = result
    else
        -- Fallback: getPlayersInRange with a huge number (server caps it)
        local inRange = detector.getPlayersInRange(100000)
        if inRange then names = inRange end
    end

    for _, name in ipairs(names) do
        local pos = detector.getPlayerPos(name)
        if pos then
            local dist = distance3D(pos.x, pos.y, pos.z)
            table.insert(players, {
                name      = name,
                x         = pos.x,
                y         = pos.y,
                z         = pos.z,
                dimension = pos.dimension,
                distance  = dist,
            })
        end
    end

    -- Sort by distance ascending (closest first)
    table.sort(players, function(a, b) return a.distance < b.distance end)
    return players
end

-- ── Send initial message, return its ID ─────────────────────
local function sendInitialMessage(content)
    local payload = textutils.serialiseJSON({
        username = BOT_USERNAME,
        content  = content,
    })
    local body, success, status = httpPost(WEBHOOK_URL .. "?wait=true", payload)
    if not success then
        error("Failed to post message. HTTP " .. tostring(status) .. ": " .. tostring(body), 0)
    end
    local msg = textutils.unserialiseJSON(body)
    if not msg or not msg.id then
        error("No message ID returned: " .. tostring(body), 0)
    end
    return msg.id
end

-- ── Edit an existing message ─────────────────────────────────
local function editMessage(messageId, content)
    local editUrl = WEBHOOK_URL .. "/messages/" .. messageId
    local payload = textutils.serialiseJSON({ content = content })
    local _, success, status = httpPatch(editUrl, payload)
    if not success then
        print("[WARN] Edit failed (HTTP " .. tostring(status) .. ")")
    end
    return success
end

-- ── Main ─────────────────────────────────────────────────────
print("=== Player Tracker Starting ===")
print("Peripheral: " .. detectorName)
print("Interval:   " .. UPDATE_INTERVAL .. "s")
print("")

if not http then
    error("HTTP is disabled! Enable it in the ComputerCraft config.", 0)
end

local playerData = getPlayerData()
local content    = buildContent(playerData)
local messageId  = sendInitialMessage(content)

print("Message sent! ID: " .. messageId)
print("Editing every " .. UPDATE_INTERVAL .. "s — Ctrl+T to stop.")
print("")

while true do
    sleep(UPDATE_INTERVAL)
    local ok, err = pcall(function()
        playerData = getPlayerData()
        content    = buildContent(playerData)
        editMessage(messageId, content)
    end)
    if ok then
        print("[" .. os.time() .. "] Updated — " .. #playerData .. " player(s)")
    else
        print("[ERROR] " .. tostring(err))
    end
end
