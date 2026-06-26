-- ============================================================v5
--  Player Coordinate Tracker → Monitor + Discord Webhook
--  Persistent offline player state stored IN the Discord message.
--  On restart, parses the last message to restore offline players.
--
--  Requirements:
--    • CC: Tweaked
--    • Advanced Peripherals — Player Detector
--    • A CC Monitor connected to the computer
--  Setup:
--    1. Connect Player Detector + Monitor to the computer.
--    2. Set WEBHOOK_URL and MESSAGE_ID below.
--       - Leave MESSAGE_ID as "" on first run; it will be printed
--         to the console and saved automatically for next time.
--    3. Run:  lua player_tracker.lua
-- ============================================================

local WEBHOOK_URL     = "https://discord.com/api/webhooks/1518852807694880818/tJ4d23Ba01Mc1ZekjK5yhSiLykKoKofQ2EFskPzR2rT15U8nPDhYLTNUfLm5u6a2othY"
local UPDATE_INTERVAL = 0
local BOT_USERNAME    = "Player Tracker"
local ID_FILE         = "tracker_message_id.txt"

-- ── Warning chatbox config ───────────────────────────────────
-- Attach a Chat Box peripheral named "chat_box" to this computer.
-- Any player within WARN_RADIUS metres who has rank 0 (unknown/visitor)
-- will receive a warning message every WARN_INTERVAL seconds.
local WARN_RADIUS      = 200          -- metres from the detector
local WARN_INTERVAL    = 1            -- seconds between repeated warnings
local WARN_MESSAGE     = "WARNING: You are approaching a restricted base. Turn around immediately or you will be removed."
local WARN_SENDER      = "Base Security"   -- name shown in chat
local WARN_PREFIX      = "&c[!]&r "        -- colour prefix (§c = red in MC formatting)

-- Rank source — same webhook + message the elevator uses
local RANK_WEBHOOK_URL = "https://discord.com/api/webhooks/1519150777174724640/5RcOy3OPeehsFBw1wgHhxgszeLRkIKDufW4sg64QCe1kLHqYuR5nOv4JRTO8xZPd8mhF"
local RANK_MESSAGE_ID  = "1519151496346730529"
local RANK_CACHE_SEC   = 5            -- how often to re-fetch ranks from Discord

-- Default detector position used when the detector can't report its own coords.
local DEFAULT_X = -2306
local DEFAULT_Y = 64
local DEFAULT_Z = 4760

-- ── Colours ─────────────────────────────────────────────────
local COL_BG       = colours.black
local COL_TITLE    = colours.yellow
local COL_HEADER   = colours.lightGrey
local COL_DIVIDER  = colours.grey
local COL_RANK1    = colours.yellow
local COL_RANK2    = colours.white
local COL_RANK3    = colours.orange
local COL_NORMAL   = colours.white
local COL_DIST     = colours.cyan
local COL_DIM      = colours.lightBlue
local COL_EMPTY    = colours.grey
local COL_FOOTER   = colours.grey
local COL_OFFLINE  = colours.red
local COL_OFFTITLE = colours.orange

-- ── Locate peripherals ───────────────────────────────────────
local detector = peripheral.find("player_detector")
if not detector then error("No Player Detector found!", 0) end
local detectorName = peripheral.getName(detector)

local monitor = peripheral.find("monitor")
if not monitor then error("No Monitor found!", 0) end

-- Chat box is optional — warnings are skipped if not present
local chatBox = peripheral.find("chat_box")
if chatBox then
    print("Chat Box: found (" .. peripheral.getName(chatBox) .. ")")
else
    print("[WARN] No chat_box peripheral found — proximity warnings disabled.")
end

print("Detector: " .. detectorName)
print("Monitor:  " .. peripheral.getName(monitor))

-- ── Detector world position ──────────────────────────────────
-- Falls back to DEFAULT_X/Y/Z instead of prompting the user.
local detectorPos = vector.new(0, 0, 0)
local ok, bpos = pcall(function()
    return peripheral.call(detectorName, "getBlockPos")
end)
if ok and bpos then
    detectorPos = vector.new(bpos.x, bpos.y, bpos.z)
    print("Detector pos: " .. bpos.x .. ", " .. bpos.y .. ", " .. bpos.z)
else
    detectorPos = vector.new(DEFAULT_X, DEFAULT_Y, DEFAULT_Z)
    print("[WARN] Could not auto-detect position. Using default: "
        .. DEFAULT_X .. ", " .. DEFAULT_Y .. ", " .. DEFAULT_Z)
end

-- ════════════════════════════════════════════════════════════
--  PLAYER STATE
-- ════════════════════════════════════════════════════════════
local onlinePlayers  = {}
local offlinePlayers = {}

local function distance3D(x, y, z)
    local dx = x - detectorPos.x
    local dy = y - detectorPos.y
    local dz = z - detectorPos.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function updatePlayerState()
    local names = {}
    local ok2, result = pcall(function() return detector.getOnlinePlayers() end)
    if ok2 and result then
        names = result
    else
        local inRange = detector.getPlayersInRange(100000)
        if inRange then names = inRange end
    end

    local detected = {}
    for _, name in ipairs(names) do
        local pos = detector.getPlayerPos(name)
        if pos then
            detected[name] = {
                x         = pos.x,
                y         = pos.y,
                z         = pos.z,
                dimension = pos.dimension,
                distance  = distance3D(pos.x, pos.y, pos.z),
            }
        end
    end

    for name, data in pairs(detected) do
        onlinePlayers[name]  = data
        offlinePlayers[name] = nil
    end

    for name, data in pairs(onlinePlayers) do
        if not detected[name] then
            offlinePlayers[name] = {
                x         = data.x,
                y         = data.y,
                z         = data.z,
                dimension = data.dimension,
                distance  = data.distance,
                lastSeen  = os.date and os.date("!%H:%M:%S") or "unknown",
            }
            onlinePlayers[name] = nil
        end
    end
end

local function sortedList(tbl)
    local list = {}
    for name, data in pairs(tbl) do
        local entry = { name = name }
        for k, v in pairs(data) do entry[k] = v end
        table.insert(list, entry)
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

-- ════════════════════════════════════════════════════════════
--  RANK LOOKUP  (mirrors elevator script — reads same Discord message)
-- ════════════════════════════════════════════════════════════
local rankCache     = {}
local rankCacheTime = -math.huge   -- force a fetch on first use

local function parseRanksFromEmbed(description)
    local data = {}
    if not description then return data end
    local block = description:match("```[^\n]*\n(.-)\n?```")
    if not block then return data end
    for line in block:gmatch("[^\n]+") do
        local name, lvl = line:match("^(.-):(-?%d+)$")
        if name and lvl then
            lvl = tonumber(lvl)
            -- 0 is default (never stored), negative = blacklisted
            if lvl and lvl ~= 0 then
                data[name] = lvl
            end
        end
    end
    return data
end

local function refreshRankCache()
    local url = RANK_WEBHOOK_URL .. "/messages/" .. RANK_MESSAGE_ID
    local response = http.get(url)
    if not response then
        print("[Ranks] HTTP GET failed — keeping stale cache")
        return
    end
    local body   = response.readAll()
    local status = response.getResponseCode()
    response.close()
    if status ~= 200 then
        print("[Ranks] Bad HTTP status " .. status .. " — keeping stale cache")
        return
    end
    local parsed = textutils.unserialiseJSON(body)
    if parsed and parsed.embeds and parsed.embeds[1] then
        rankCache     = parseRanksFromEmbed(parsed.embeds[1].description)
        rankCacheTime = os.clock()
        local count = 0
        for _ in pairs(rankCache) do count = count + 1 end
        print("[Ranks] Loaded " .. count .. " entries.")
    else
        print("[Ranks] Could not parse embed — keeping stale cache")
    end
end

-- Returns the rank level for a player (0 = unknown/visitor).
local function getPlayerRank(username)
    if os.clock() - rankCacheTime > RANK_CACHE_SEC then
        refreshRankCache()
    end
    return rankCache[username] or 0
end

-- ════════════════════════════════════════════════════════════
--  PROXIMITY WARNING STATE
-- ════════════════════════════════════════════════════════════
-- Tracks when each player was last warned so we don't spam every tick.
local lastWarned = {}   -- [username] = os.clock() of last warning sent

local function sendWarning(username)
    if not chatBox then return end
    -- Correct Advanced Peripherals API signature:
    -- sendMessageToPlayer(message, username, prefix, brackets, bracketColor)
    local ok, err = pcall(function()
        chatBox.sendMessageToPlayer(WARN_MESSAGE, username, WARN_SENDER, "[]", "&c")
    end)
    if not ok then
        print("[ChatBox] Failed to warn " .. username .. ": " .. tostring(err))
    end
end

local function checkProximityWarnings()
    if not chatBox then return end
    local now = os.clock()
    -- Check every currently-online player
    for name, data in pairs(onlinePlayers) do
        if data.distance <= WARN_RADIUS then
            local rank = getPlayerRank(name)
            if rank <= 0 then
                -- Rank 0 or below (blacklisted) — warn them
                local lastTime = lastWarned[name] or -math.huge
                if now - lastTime >= WARN_INTERVAL then
                    sendWarning(name)
                    lastWarned[name] = now
                    print("[Warn] Warned " .. name .. " (rank " .. rank .. ", dist " .. string.format("%.0f", data.distance) .. "m)")
                end
            end
        else
            -- Player moved out of range — reset their warning timer so they
            -- get warned again immediately if they come back.
            lastWarned[name] = nil
        end
    end
    -- Clean up entries for players who went offline
    for name in pairs(lastWarned) do
        if not onlinePlayers[name] then
            lastWarned[name] = nil
        end
    end
end

-- ════════════════════════════════════════════════════════════
--  PARSE OFFLINE PLAYERS FROM DISCORD MESSAGE
-- ════════════════════════════════════════════════════════════
local function parseOfflineFromMessage(content)
    local parsed = {}
    local inDiff = false

    for line in (content .. "\n"):gmatch("([^\n]*)\n") do
        if line:match("^```diff") then
            inDiff = true
        elseif inDiff and line:match("^```") then
            inDiff = false
        elseif inDiff then
            local rest = line:match("^%- (.+)$")
            if rest and not rest:match("^%-%-") and not rest:match("^Player") then
                local name, x, y, z, lastSeen, dim =
                    rest:match("^(%S+)%s+(%-?%d+%.%d+)%s+(%-?%d+%.%d+)%s+(%-?%d+%.%d+)%s+%-?%d+%.%d+m%s+(%S+)%s+(.+)$")
                if name and x and y and z then
                    local nx = tonumber(x)
                    local ny = tonumber(y)
                    local nz = tonumber(z)
                    if nx and ny and nz then
                        parsed[name] = {
                            x         = nx,
                            y         = ny,
                            z         = nz,
                            dimension = dim and dim:gsub("%s+$", "") or "unknown",
                            distance  = distance3D(nx, ny, nz),
                            lastSeen  = lastSeen or "unknown",
                        }
                    end
                end
            end
        end
    end

    return parsed
end

-- ════════════════════════════════════════════════════════════
--  HTTP HELPERS
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

-- Returns body, success, status.
-- Uses http.post with method override via a raw request, then waits with
-- os.pullEventRaw so http_success/http_failure are not filtered out.
-- Unrelated http events are safely ignored (not re-queued — handles can't
-- be serialised back into the event queue).
local function httpPatch(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local sentOk, sentErr = pcall(function()
        http.request({ url = url, body = payload, headers = headers, method = "PATCH" })
    end)
    if not sentOk then
        print("[HTTP] PATCH send error: " .. tostring(sentErr))
        return nil, false, "request_failed"
    end
    -- Wait for the response, ignoring unrelated events.
    -- We do NOT re-queue http handles because they can't be re-queued safely.
    local deadline = os.clock() + 10  -- 10 second timeout
    while os.clock() < deadline do
        local event, evUrl, handle = os.pullEventRaw()
        if event == "terminate" then
            error("Terminated", 0)
        elseif event == "http_success" then
            if evUrl == url then
                local body   = handle.readAll()
                local status = handle.getResponseCode()
                handle.close()
                return body, (status >= 200 and status < 300), status
            else
                -- Different URL succeeded — close handle to avoid leak, keep waiting
                if handle then pcall(function() handle.close() end) end
            end
        elseif event == "http_failure" then
            if evUrl == url then
                return nil, false, "http_failure"
            end
            -- Different URL failed — keep waiting
        end
        -- All other events are silently ignored while we wait for our HTTP response
    end
    print("[FATAL] HTTP PATCH timed out — rebooting now...")
    sleep(1)
    os.reboot()
end

local function httpGet(url, headers)
    headers = headers or {}
    local response = http.get(url, headers)
    if not response then return nil, false, "no response" end
    local body   = response.readAll()
    local status = response.getResponseCode()
    response.close()
    return body, (status >= 200 and status < 300), status
end

-- ════════════════════════════════════════════════════════════
--  MESSAGE ID PERSISTENCE
-- ════════════════════════════════════════════════════════════
local function loadMessageId()
    if not fs.exists(ID_FILE) then return nil end
    local f  = fs.open(ID_FILE, "r")
    local id = f.readAll():gsub("%s+", "")
    f.close()
    return id ~= "" and id or nil
end

local function saveMessageId(id)
    local f = fs.open(ID_FILE, "w")
    f.write(id)
    f.close()
end

-- ════════════════════════════════════════════════════════════
--  DISCORD CONTENT BUILDER
-- ════════════════════════════════════════════════════════════
local function buildDiscordContent()
    local online  = sortedList(onlinePlayers)
    local offline = sortedList(offlinePlayers)
    local now     = os.date and os.date("!%Y-%m-%d %H:%M:%S UTC") or "unknown time"
    local lines   = {}

    table.insert(lines, "**\xF0\x9F\x97\xBA\xEF\xB8\x8F Live Player Coordinates** \xe2\x80\x94 *" .. now .. "*")

    table.insert(lines, "```")
    if #online == 0 then
        table.insert(lines, "  (no players online)")
    else
        table.insert(lines, string.format("  %-16s  %7s  %5s  %7s  %8s  %s",
            "Player", "X", "Y", "Z", "Dist", "Dimension"))
        table.insert(lines, "  " .. string.rep("-", 68))
        for i, p in ipairs(online) do
            local dim  = (p.dimension or "unknown"):gsub("^minecraft:", "")
            local dist = string.format("%.1fm", p.distance)
            local rank = (i == 1 and "#1 ") or (i == 2 and "#2 ") or (i == 3 and "#3 ") or "   "
            table.insert(lines, string.format("  %s%-16s  %7.1f  %5.1f  %7.1f  %8s  %s",
                rank, p.name, p.x, p.y, p.z, dist, dim))
        end
    end
    table.insert(lines, "```")

    if #offline > 0 then
        table.insert(lines, "**\xF0\x9F\x93\xB4 Offline \xe2\x80\x94 last known position**")
        table.insert(lines, "```diff")
        table.insert(lines, string.format("  %-16s  %7s  %5s  %7s  %8s  %-10s  %s",
            "Player", "X", "Y", "Z", "Dist", "LastSeen", "Dimension"))
        table.insert(lines, "  " .. string.rep("-", 75))
        for _, p in ipairs(offline) do
            local dim  = (p.dimension or "unknown"):gsub("^minecraft:", "")
            local dist = string.format("%.1fm", p.distance)
            local seen = p.lastSeen or "unknown"
            table.insert(lines, string.format("- %-16s  %7.1f  %5.1f  %7.1f  %8s  %-10s  %s",
                p.name, p.x, p.y, p.z, dist, seen, dim))
        end
        table.insert(lines, "```")
    end

    table.insert(lines, string.format(
        "-# Updates every %ds \xc2\xb7 %d online \xc2\xb7 %d offline \xc2\xb7 Detector @ %d, %d, %d",
        UPDATE_INTERVAL, #online, #offline,
        detectorPos.x, detectorPos.y, detectorPos.z
    ))

    return table.concat(lines, "\n")
end

-- ════════════════════════════════════════════════════════════
--  MONITOR RENDERING
-- ════════════════════════════════════════════════════════════
local function mWrite(mon, x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    mon.setTextColour(fg or colours.white)
    mon.setBackgroundColour(bg or COL_BG)
    mon.write(text)
end

local function mFillLine(mon, y, w, bg)
    mon.setCursorPos(1, y)
    mon.setBackgroundColour(bg or COL_BG)
    mon.write(string.rep(" ", w))
end

local function renderMonitor()
    monitor.setTextScale(0.5)
    monitor.setBackgroundColour(COL_BG)
    monitor.clear()

    local w, h    = monitor.getSize()
    local now     = os.date and os.date("!%H:%M:%S UTC") or "??:??:??"
    local online  = sortedList(onlinePlayers)
    local offline = sortedList(offlinePlayers)

    mFillLine(monitor, 1, w, colours.grey)
    mWrite(monitor, 1, 1, " Player Tracker", COL_TITLE, colours.grey)
    local ts = now .. " "
    mWrite(monitor, w - #ts + 1, 1, ts, COL_HEADER, colours.grey)

    local row = 3
    mWrite(monitor, 1,  row, string.format("  %-16s", "Player"),  COL_HEADER)
    mWrite(monitor, 19, row, string.format("%7s",  "X"),           COL_HEADER)
    mWrite(monitor, 27, row, string.format("%5s",  "Y"),           COL_HEADER)
    mWrite(monitor, 33, row, string.format("%7s",  "Z"),           COL_HEADER)
    mWrite(monitor, 41, row, string.format("%8s",  "Dist"),        COL_HEADER)
    if w >= 56 then mWrite(monitor, 50, row, "Dimension", COL_HEADER) end
    row = row + 1
    mWrite(monitor, 1, row, string.rep("-", math.min(w, 70)), COL_DIVIDER)
    row = row + 1

    if #online == 0 then
        mWrite(monitor, 3, row, "(no players online)", COL_EMPTY)
        row = row + 1
    else
        for i, p in ipairs(online) do
            if row > h - 4 then break end
            local col  = (i==1 and COL_RANK1) or (i==2 and COL_RANK2) or (i==3 and COL_RANK3) or COL_NORMAL
            local rank = (i <= 3) and ("#"..i.." ") or "   "
            local dim  = (p.dimension or "unknown"):gsub("^minecraft:", "")
            local dist = string.format("%.1fm", p.distance)
            mWrite(monitor, 1,  row, string.format("%s%-16s", rank, p.name:sub(1,16)), col)
            mWrite(monitor, 19, row, string.format("%7.1f", p.x),  col)
            mWrite(monitor, 27, row, string.format("%5.1f", p.y),  col)
            mWrite(monitor, 33, row, string.format("%7.1f", p.z),  col)
            mWrite(monitor, 41, row, string.format("%8s",   dist), COL_DIST)
            if w >= 56 then mWrite(monitor, 50, row, dim:sub(1, w-50), COL_DIM) end
            row = row + 1
        end
    end

    if #offline > 0 and row <= h - 2 then
        row = row + 1
        if row <= h - 2 then
            mWrite(monitor, 1, row, string.rep("-", math.min(w, 70)), COL_DIVIDER)
            row = row + 1
        end
        if row <= h - 2 then
            mWrite(monitor, 1, row, " OFFLINE - last known position", COL_OFFTITLE)
            row = row + 1
        end
        for _, p in ipairs(offline) do
            if row > h - 2 then break end
            local dim  = (p.dimension or "unknown"):gsub("^minecraft:", "")
            local dist = string.format("%.1fm", p.distance)
            local seen = p.lastSeen or "?"
            mWrite(monitor, 1,  row, string.format("  %-16s", p.name:sub(1,16)), COL_OFFLINE)
            mWrite(monitor, 19, row, string.format("%7.1f", p.x),  COL_NORMAL)
            mWrite(monitor, 27, row, string.format("%5.1f", p.y),  COL_NORMAL)
            mWrite(monitor, 33, row, string.format("%7.1f", p.z),  COL_NORMAL)
            mWrite(monitor, 41, row, string.format("%8s",   dist), COL_DIST)
            if w >= 56 then mWrite(monitor, 50, row, (dim.." ("..seen..")"):sub(1, w-50), COL_DIM) end
            row = row + 1
        end
    end

    local footer = string.format(
        " %d online · %d offline · every %ds · @%d,%d,%d",
        #online, #offline, UPDATE_INTERVAL,
        detectorPos.x, detectorPos.y, detectorPos.z
    )
    mFillLine(monitor, h, w, colours.grey)
    mWrite(monitor, 1, h, footer:sub(1, w), COL_FOOTER, colours.grey)
end

-- ════════════════════════════════════════════════════════════
--  DISCORD SEND / EDIT / FETCH
-- ════════════════════════════════════════════════════════════
local function sendInitialMessage(content)
    local payload = textutils.serialiseJSON({ username = BOT_USERNAME, content = content })
    local body, success, status = httpPost(WEBHOOK_URL .. "?wait=true", payload)
    if not success then
        print("[FATAL] Failed to post initial message (HTTP " .. tostring(status) .. ") — rebooting now...")
        sleep(1)
        os.reboot()
    end
    local msg = textutils.unserialiseJSON(body)
    if not msg or not msg.id then
        print("[FATAL] No message ID returned — rebooting now...")
        sleep(1)
        os.reboot()
    end
    return msg.id
end

-- Edits the Discord message. Reboots immediately on any failure so the
-- computer comes back fresh and re-establishes the connection.
local function editMessage(messageId, content)
    local editUrl = WEBHOOK_URL .. "/messages/" .. messageId
    local payload = textutils.serialiseJSON({ content = content })
    local _, success, status = httpPatch(editUrl, payload)
    if not success then
        print("[FATAL] Discord edit failed (" .. tostring(status) .. ") — rebooting now...")
        sleep(1)
        os.reboot()
    end
    return true
end

local function fetchMessage(messageId)
    local url  = WEBHOOK_URL .. "/messages/" .. messageId
    local body, success, status = httpGet(url)
    if not success then
        print("[FATAL] Could not fetch message (HTTP " .. tostring(status) .. ") — rebooting now...")
        sleep(1)
        os.reboot()
    end
    local msg = textutils.unserialiseJSON(body)
    return msg and msg.content or nil
end

-- ════════════════════════════════════════════════════════════
--  STARTUP — restore offline players from Discord
-- ════════════════════════════════════════════════════════════
print("")
print("=== Player Tracker Starting ===")

if not http then
    error("HTTP is disabled! Enable it in computercraft-server.toml", 0)
end

local messageId = loadMessageId()

if messageId then
    print("Found saved message ID: " .. messageId)
    print("Fetching previous message to restore offline players...")
    local content = fetchMessage(messageId)
    if content then
        local restored = parseOfflineFromMessage(content)
        local count = 0
        for name, data in pairs(restored) do
            offlinePlayers[name] = data
            count = count + 1
        end
        print("Restored " .. count .. " offline player(s) from Discord.")
    else
        print("[WARN] Could not fetch old message — starting fresh.")
        messageId = nil
    end
else
    print("No saved message ID found — will create a new message.")
end

updatePlayerState()
renderMonitor()

local content = buildDiscordContent()

if messageId then
    editMessage(messageId, content)
    print("Resumed editing existing message ID: " .. messageId)
else
    messageId = sendInitialMessage(content)
    saveMessageId(messageId)
    print("New message created. ID saved: " .. messageId)
end

print("Running — Ctrl+T to stop.")
print("")

-- ════════════════════════════════════════════════════════════
--  MAIN LOOP
-- ════════════════════════════════════════════════════════════
while true do
    sleep(UPDATE_INTERVAL)
    local ok2, err = pcall(function()
        updatePlayerState()
        checkProximityWarnings()
        renderMonitor()
        editMessage(messageId, buildDiscordContent())
    end)
    if ok2 then
        local on  = 0; for _ in pairs(onlinePlayers)  do on  = on  + 1 end
        local off = 0; for _ in pairs(offlinePlayers) do off = off + 1 end
        print("[" .. os.time() .. "] Updated — " .. on .. " online, " .. off .. " offline")
    else
        print("[ERROR] " .. tostring(err))
        print("Rebooting in 2 seconds...")
        sleep(2)
        os.reboot()
    end
end
