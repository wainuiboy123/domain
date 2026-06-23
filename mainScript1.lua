-- ============================================================
--  Player Coordinate Tracker → Monitor + Discord Webhook
--  Requirements:
--    • CC: Tweaked
--    • Advanced Peripherals — Player Detector
--    • A CC Monitor (any size) connected to the computer
--  Setup:
--    1. Connect Player Detector + Monitor to the computer.
--    2. Set WEBHOOK_URL below.
--    3. Adjust UPDATE_INTERVAL as desired.
--    4. Run:  lua player_tracker.lua
-- ============================================================

local WEBHOOK_URL     = "https://discord.com/api/webhooks/1518852807694880818/tJ4d23Ba01Mc1ZekjK5yhSiLykKoKofQ2EFskPzR2rT15U8nPDhYLTNUfLm5u6a2othY"
local UPDATE_INTERVAL = 0.5
local BOT_USERNAME    = "Player Tracker"

-- ── Colours (change these if you like) ──────────────────────
local COL_BG        = colours.black
local COL_TITLE     = colours.yellow
local COL_HEADER    = colours.lightGrey
local COL_DIVIDER   = colours.grey
local COL_RANK1     = colours.yellow
local COL_RANK2     = colours.white
local COL_RANK3     = colours.orange
local COL_NORMAL    = colours.white
local COL_DIST      = colours.cyan
local COL_DIM       = colours.lightBlue
local COL_EMPTY     = colours.grey
local COL_FOOTER    = colours.grey

-- ── Locate peripherals ───────────────────────────────────────
local detector = peripheral.find("player_detector")
if not detector then
    error("No Player Detector found!", 0)
end
local detectorName = peripheral.getName(detector)

local monitor = peripheral.find("monitor")
if not monitor then
    error("No Monitor found! Connect a CC monitor to the computer.", 0)
end

print("Detector: " .. detectorName)
print("Monitor:  " .. peripheral.getName(monitor))

-- ── Get detector world position ──────────────────────────────
local detectorPos = vector.new(0, 0, 0)
local ok, bpos = pcall(function()
    return peripheral.call(detectorName, "getBlockPos")
end)
if ok and bpos then
    detectorPos = vector.new(bpos.x, bpos.y, bpos.z)
    print("Detector pos: " .. bpos.x .. ", " .. bpos.y .. ", " .. bpos.z)
else
    print("[WARN] Could not auto-detect position.")
    print("Enter detector X (or 0 to skip): ")
    local x = tonumber(read()) or 0
    if x ~= 0 then
        print("Enter Y: ") local y = tonumber(read()) or 0
        print("Enter Z: ") local z = tonumber(read()) or 0
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

-- ── Gather + sort player data ────────────────────────────────
local function getPlayerData()
    local players = {}
    local names   = {}

    local ok, result = pcall(function() return detector.getOnlinePlayers() end)
    if ok and result then
        names = result
    else
        local inRange = detector.getPlayersInRange(100000)
        if inRange then names = inRange end
    end

    for _, name in ipairs(names) do
        local pos = detector.getPlayerPos(name)
        if pos then
            table.insert(players, {
                name      = name,
                x         = pos.x,
                y         = pos.y,
                z         = pos.z,
                dimension = pos.dimension,
                distance  = distance3D(pos.x, pos.y, pos.z),
            })
        end
    end

    table.sort(players, function(a, b) return a.distance < b.distance end)
    return players
end

-- ════════════════════════════════════════════════════════════
--  MONITOR RENDERING
-- ════════════════════════════════════════════════════════════

-- Write coloured text at a position on the monitor
local function mWrite(mon, x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    mon.setTextColour(fg or colours.white)
    mon.setBackgroundColour(bg or COL_BG)
    mon.write(text)
end

-- Fill an entire line with a background colour
local function mFillLine(mon, y, w, bg)
    mon.setCursorPos(1, y)
    mon.setBackgroundColour(bg or COL_BG)
    mon.write(string.rep(" ", w))
end

local function renderMonitor(playerData)
    monitor.setTextScale(0.5) -- small text = more columns; adjust to taste
    monitor.setBackgroundColour(COL_BG)
    monitor.clear()

    local w, h = monitor.getSize()
    local now  = os.date and os.date("!%H:%M:%S UTC") or "??:??:??"

    -- ── Title bar ──
    mFillLine(monitor, 1, w, colours.grey)
    local title = " 🗺  Player Tracker"
    mWrite(monitor, 1, 1, title, COL_TITLE, colours.grey)
    local timeStr = now .. " "
    mWrite(monitor, w - #timeStr + 1, 1, timeStr, COL_HEADER, colours.grey)

    -- ── Column headers ──
    local row = 3
    mWrite(monitor, 1,  row, string.format("  %-16s", "Player"),   COL_HEADER)
    mWrite(monitor, 19, row, string.format("%7s", "X"),             COL_HEADER)
    mWrite(monitor, 27, row, string.format("%5s", "Y"),             COL_HEADER)
    mWrite(monitor, 33, row, string.format("%7s", "Z"),             COL_HEADER)
    mWrite(monitor, 41, row, string.format("%8s", "Dist"),          COL_HEADER)
    if w >= 56 then
        mWrite(monitor, 50, row, "Dimension", COL_HEADER)
    end

    -- ── Divider ──
    row = 4
    mWrite(monitor, 1, row, string.rep("-", math.min(w, 70)), COL_DIVIDER)

    -- ── Player rows ──
    row = 5
    if #playerData == 0 then
        mWrite(monitor, 3, row, "(no players online)", COL_EMPTY)
    else
        for i, p in ipairs(playerData) do
            if row > h - 2 then
                mWrite(monitor, 3, row, "... and " .. (#playerData - i + 1) .. " more", COL_EMPTY)
                break
            end

            -- Pick colour by rank
            local col = COL_NORMAL
            if i == 1 then col = COL_RANK1
            elseif i == 2 then col = COL_RANK2
            elseif i == 3 then col = COL_RANK3
            end

            local rank = (i <= 3) and ("#" .. i .. " ") or "   "
            local dim  = (p.dimension or "unknown"):gsub("^minecraft:", "")
            local dist = string.format("%.1fm", p.distance)

            mWrite(monitor, 1,  row, string.format("%s%-16s", rank, p.name:sub(1,16)), col)
            mWrite(monitor, 19, row, string.format("%7.1f",   p.x),   col)
            mWrite(monitor, 27, row, string.format("%5.1f",   p.y),   col)
            mWrite(monitor, 33, row, string.format("%7.1f",   p.z),   col)
            mWrite(monitor, 41, row, string.format("%8s",     dist),  COL_DIST)
            if w >= 56 then
                mWrite(monitor, 50, row, dim:sub(1, w - 50), COL_DIM)
            end

            row = row + 1
        end
    end

    -- ── Footer ──
    local footer = string.format(
        " %d player(s) · updates every %ds · detector @ %d,%d,%d",
        #playerData, UPDATE_INTERVAL,
        detectorPos.x, detectorPos.y, detectorPos.z
    )
    mFillLine(monitor, h, w, colours.grey)
    mWrite(monitor, 1, h, footer:sub(1, w), COL_FOOTER, colours.grey)
end

-- ════════════════════════════════════════════════════════════
--  DISCORD WEBHOOK
-- ════════════════════════════════════════════════════════════

local function httpPost(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local response = http.post(url, payload, headers)
    if not response then return nil, false, "no response" end
    local body   = response.readAll()
    local status = response.getResponseCode()
    response.close()
    return body, (status >= 200 and status < 300), status
end

local function httpPatch(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    pcall(function()
        http.request({ url = url, body = payload, headers = headers, method = "PATCH" })
    end)
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

local function buildDiscordContent(playerData)
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

local function sendInitialMessage(content)
    local payload = textutils.serialiseJSON({ username = BOT_USERNAME, content = content })
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

local function editMessage(messageId, content)
    local editUrl = WEBHOOK_URL .. "/messages/" .. messageId
    local payload = textutils.serialiseJSON({ content = content })
    local _, success, status = httpPatch(editUrl, payload)
    if not success then
        print("[WARN] Discord edit failed (HTTP " .. tostring(status) .. ")")
    end
end

-- ════════════════════════════════════════════════════════════
--  MAIN
-- ════════════════════════════════════════════════════════════
print("")
print("=== Player Tracker Starting ===")

if not http then
    error("HTTP is disabled! Enable it in computercraft-server.toml", 0)
end

-- Initial data fetch
local playerData = getPlayerData()

-- Render monitor immediately so it's not blank while we wait for Discord
renderMonitor(playerData)

-- Send first Discord message
local discordContent = buildDiscordContent(playerData)
local messageId      = sendInitialMessage(discordContent)
print("Discord message ID: " .. messageId)
print("Running — Ctrl+T to stop.")
print("")

-- Main loop
while true do
    sleep(UPDATE_INTERVAL)

    local ok, err = pcall(function()
        playerData = getPlayerData()
        renderMonitor(playerData)
        discordContent = buildDiscordContent(playerData)
        editMessage(messageId, discordContent)
    end)

    if ok then
        print("[" .. os.time() .. "] Updated — " .. #playerData .. " player(s)")
    else
        print("[ERROR] " .. tostring(err))
    end
end
