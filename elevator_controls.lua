--====================================================--
--   ELEVATOR FLOOR PANEL  (unified panel + receiver)
--   For CC: Tweaked + Advanced Peripherals
--
--   HARDWARE PER FLOOR (x5, one set per floor):
--     - 1 CC:Tweaked computer
--     - 1 monitor (any size; text scale auto-adjusts)
--     - 1 player_detector peripheral (Advanced Peripherals)
--     - 1 Ender Modem
--   All four must be physically attached to the same computer.
--
--   HOW IT WORKS:
--     Every floor runs this SAME script. Each computer is
--     both a "panel" (shows buttons, reads player clicks) and
--     a "receiver" (listens for requests from other floors and
--     pulses its own local redstone to move the elevator).
--
--     When a player right-clicks the detector and a floor
--     button is selected, this computer sends a rednet message
--     directly to THAT floor's computer. That computer then
--     pulses its local redstone output, which triggers whatever
--     mechanism calls the elevator to that level.
--
--   SETUP STEPS:
--     1. Place hardware on all 5 floors. Boot each computer
--        and note its ID (shown on startup, or run "id").
--     2. Fill in FLOOR_COMPUTERS below with all 5 IDs.
--     3. Fill in FLOORS to match each floor's local redstone
--        wiring (which side, how long to pulse).
--     4. Adjust BUTTONS rank requirements if needed.
--     5. Copy this file to /startup.lua on every floor computer
--        so it restarts automatically after reboots.
--     6. Fill in WEBHOOK_URL + ensure MSG_ID_FILE exists on
--        each computer (copy from your whitelist manager computer).
--====================================================--

--========== FLOOR COMPUTER IDs (CUSTOMIZE ME) ==========--
-- Map a friendly name -> computer ID for each floor.
-- Run this script once on each computer; it prints its own ID.
-- Keys here are used in FLOORS and BUTTONS below.

local FLOOR_COMPUTERS = {
    top     = 15,   -- <-- replace with Top Floor computer ID
    tunnel  = 12,   -- <-- replace with Tunnel computer ID
    storage = 11,   -- <-- replace with Storage computer ID
    testing = 13,   -- <-- replace with Testing Floor computer ID
    command = 14,   -- <-- replace with Command Floor computer ID
}

--========== FLOOR REDSTONE CONFIG (CUSTOMIZE ME) ==========--
-- Each entry defines what THIS floor's computer does to its OWN
-- redstone when it receives a "come here" request.
-- side:         which redstone side to pulse
-- pulseSeconds: how long the pulse lasts
-- Keys MUST match FLOOR_COMPUTERS above.

local FLOORS = {
    top     = { side = "bottom", pulseSeconds = 1 },
    tunnel  = { side = "bottom", pulseSeconds = 1 },
    storage = { side = "bottom", pulseSeconds = 1 },
    testing = { side = "bottom", pulseSeconds = 1 },
    command = { side = "bottom", pulseSeconds = 1 },
}

--========== BUTTON CONFIG (CUSTOMIZE ME) ==========--
-- Each button sends the elevator to a different floor.
-- label:        text shown on the button
-- requiredRank: minimum rank level to use this button
--               (-1 Blacklisted, 0/1 Visitor, 2 Recruit,
--                3 Member, 4 Officer, 5 Senior Officer, 6 Command)
-- floorKey:     must match a key in FLOOR_COMPUTERS / FLOORS

local BUTTONS = {
    { label = "TOP",     requiredRank = 1, floorKey = "top"     },
    { label = "TUNNEL",  requiredRank = 3, floorKey = "tunnel"  },
    { label = "STORAGE", requiredRank = 3, floorKey = "storage" },
    { label = "TESTING", requiredRank = 4, floorKey = "testing" },
    { label = "COMMAND", requiredRank = 5, floorKey = "command" },
}

-- Right-clicking with NO button selected sends the elevator here.
local DEFAULT_FLOOR_KEY = "top"

--========== PROTOCOL ==========--
-- Shared secret so floor computers only react to each other.
-- Change this string on ALL floors if you want (keep them identical).
local PROTOCOL = "elevator_v1"

--========== DISCORD RANK CONFIG ==========--
local WEBHOOK_URL    = "https://discord.com/api/webhooks/1519150777174724640/5RcOy3OPeehsFBw1wgHhxgszeLRkIKDufW4sg64QCe1kLHqYuR5nOv4JRTO8xZPd8mhF"
local MESSAGE_ID     = "1519151496346730529"   -- <-- paste the rank message ID here
local RANK_CACHE_SEC = 15   -- seconds before re-fetching rank data

--========== RANK DEFINITIONS ==========--
local RANKS = {
    [-1] = { name = "Blacklisted",    color = colors.red       },
    [0]  = { name = "Visitor",        color = colors.lightGray },
    [1]  = { name = "Visitor",        color = colors.white     },
    [2]  = { name = "Recruit",        color = colors.lime      },
    [3]  = { name = "Member",         color = colors.lime      },
    [4]  = { name = "Officer",        color = colors.green     },
    [5]  = { name = "Senior Officer", color = colors.green     },
    [6]  = { name = "Command",        color = colors.green     },
}
local MIN_RANK = -1
local MAX_RANK = 6

--========== THEME ==========--
local THEME = {
    bg              = colors.black,
    btnBg           = colors.white,
    btnText         = colors.black,
    btnSelectedBg   = colors.green,
    btnSelectedText = colors.white,
    msgGood         = colors.lime,
    msgBad          = colors.red,
}

--====================================================--
--   PERIPHERAL INIT
--====================================================--

local mon = peripheral.find("monitor")
if not mon then
    error("No monitor found! Attach a monitor to this computer.")
end

local detector = peripheral.find("player_detector")
if not detector then
    error("No player_detector found! Attach one to this computer.")
end

local modem = peripheral.find("modem")
if not modem then
    error("No Ender Modem found! Attach one to this computer.")
end

rednet.open(peripheral.getName(modem))

mon.setTextScale(0.5)
local W, H = mon.getSize()

-- Identify which floor this computer IS by matching its own ID.
local MY_ID = os.getComputerID()
local MY_FLOOR_KEY = nil
for key, id in pairs(FLOOR_COMPUTERS) do
    if id == MY_ID then
        MY_FLOOR_KEY = key
        break
    end
end

print("=== Elevator Floor Panel ===")
print("Computer ID : " .. MY_ID)
if MY_FLOOR_KEY then
    print("Identified as floor: " .. MY_FLOOR_KEY)
else
    print("WARNING: This computer's ID is not listed in FLOOR_COMPUTERS.")
    print("Add it there so other floors can identify you.")
end

--====================================================--
--   STATE
--====================================================--

local selectedIndex  = nil     -- currently highlighted button (index into BUTTONS)
local rankCache      = {}      -- { [username] = level }
local rankCacheTime  = 0       -- os.clock() of last successful fetch
local statusMessage  = nil     -- transient bottom-of-screen notice
local statusColor    = colors.white
local statusClearAt  = 0
local buttonRegions  = {}      -- clickable regions for monitor_touch

--====================================================--
--   DISCORD RANK LOOKUP
--====================================================--

local function parseRanksFromDescription(description)
    local data = {}
    if not description then return data end
    local block = description:match("```\n?(.-)\n?```")
    if not block then return data end
    for line in block:gmatch("[^\r\n]+") do
        local name, lvl = line:match("^(.-):(-?%d+)$")
        if name and lvl then
            lvl = tonumber(lvl)
            if lvl and lvl >= MIN_RANK and lvl <= MAX_RANK and lvl ~= 0 then
                data[name] = lvl
            end
        end
    end
    return data
end

-- Async-safe HTTP wait: uses os.pullEventRaw (not os.pullEvent) so that
-- http_success / http_failure events are NOT silently filtered out.
-- Unrelated events are re-queued so nothing else is lost.
local function waitForHttp(url)
    while true do
        local event, evUrl, p3, p4 = os.pullEventRaw()
        if (event == "http_success" or event == "http_failure") and evUrl == url then
            return event, p3, p4
        else
            os.queueEvent(event, evUrl, p3, p4)
            os.sleep(0)
        end
    end
end

local function refreshRankCache()
    if MESSAGE_ID == "PASTE_YOUR_MESSAGE_ID_HERE" then
        print("[Ranks] ERROR: MESSAGE_ID has not been set in the script!")
        return false
    end

    local getUrl = WEBHOOK_URL .. "/messages/" .. MESSAGE_ID
    print("[Ranks] Fetching rank data from Discord...")

    local ok, err = pcall(http.request, { url = getUrl, method = "GET" })
    if not ok then
        print("[Ranks] http.request failed: " .. tostring(err))
        return false
    end

    local event, handle, errMsg = waitForHttp(getUrl)
    if event == "http_failure" then
        print("[Ranks] HTTP request failed: " .. tostring(errMsg))
        return false
    end

    local body = handle.readAll()
    handle.close()

    local parsed = textutils.unserialiseJSON(body)
    if not parsed then
        print("[Ranks] Failed to parse JSON response")
        return false
    end
    if not (parsed.embeds and parsed.embeds[1]) then
        print("[Ranks] No embeds found in Discord message")
        return false
    end

    local newCache = parseRanksFromDescription(parsed.embeds[1].description)
    local count = 0
    for _ in pairs(newCache) do count = count + 1 end

    if count == 0 then
        print("[Ranks] WARNING: Parsed 0 ranks. Check the embed description format.")
        print("[Ranks] Description preview: " .. tostring(parsed.embeds[1].description or "nil"):sub(1, 120))
    else
        print("[Ranks] Loaded " .. count .. " rank entries.")
    end

    rankCache     = newCache
    rankCacheTime = os.clock()
    return true
end

local function getRank(username)
    if os.clock() - rankCacheTime > RANK_CACHE_SEC then
        refreshRankCache()
    end
    return rankCache[username] or 0
end

--====================================================--
--   REDSTONE (receiver side)
--====================================================--

local function pulseRedstone(floorKey)
    local cfg = FLOORS[floorKey]
    if not cfg then
        print("pulseRedstone: unknown floorKey '" .. tostring(floorKey) .. "'")
        return
    end
    redstone.setOutput(cfg.side, true)
    sleep(cfg.pulseSeconds)
    redstone.setOutput(cfg.side, false)
end

--====================================================--
--   WIRELESS FLOOR REQUEST (panel side)
--====================================================--

-- Sends a "move elevator here" request to the target floor's computer
-- and waits up to 3 seconds for an acknowledgment.
-- Returns true on confirmed ack, false on timeout.
local function requestFloor(floorKey)
    local targetId = FLOOR_COMPUTERS[floorKey]
    if not targetId then
        print("requestFloor: no computer ID for floor '" .. tostring(floorKey) .. "'")
        return false
    end

    -- If the target IS this computer, just pulse locally and skip the network round-trip.
    if targetId == MY_ID then
        pulseRedstone(floorKey)
        return true
    end

    rednet.send(targetId, { action = "goToFloor", floorKey = floorKey }, PROTOCOL)

    local timer = os.startTimer(3)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local senderId, message, protocol = p1, p2, p3
            if senderId == targetId
               and protocol == PROTOCOL
               and type(message) == "table"
               and message.action == "ack"
               and message.floorKey == floorKey then
                return true
            else
                -- Not our ack — put it back so the main loop can handle it
                -- (e.g. another floor requesting THIS floor simultaneously).
                os.queueEvent(event, p1, p2, p3)
            end
        elseif event == "timer" and p1 == timer then
            return false
        else
            os.queueEvent(event, p1, p2, p3)
        end
    end
end

--====================================================--
--   DRAWING
--====================================================--

local function setStatus(text, color, holdSeconds)
    statusMessage = text
    statusColor   = color
    statusClearAt = os.clock() + (holdSeconds or 2.5)
end

local function fillButton(text, bg, fg, xmin, xmax, ymin, ymax)
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    local width   = xmax - xmin + 1
    local height  = ymax - ymin + 1
    local textY   = ymin + math.floor((height - 1) / 2)
    local leftPad = math.floor((width - #text) / 2)
    local rightPad = width - #text - leftPad
    for y = ymin, ymax do
        mon.setCursorPos(xmin, y)
        if y == textY then
            mon.write(string.rep(" ", math.max(0, leftPad)))
            mon.write(text)
            mon.write(string.rep(" ", math.max(0, rightPad)))
        else
            mon.write(string.rep(" ", width))
        end
    end
end

local function drawButtons()
    buttonRegions = {}
    local gap        = 1
    local totalGap   = gap * (#BUTTONS - 1)
    local usable     = H - totalGap
    local rowHeight  = math.floor(usable / #BUTTONS)
    local leftover   = usable - (rowHeight * #BUTTONS)

    local y = 1
    for i, btn in ipairs(BUTTONS) do
        local thisHeight = rowHeight + ((i <= leftover) and 1 or 0)
        local ymin = y
        local ymax = y + thisHeight - 1

        local isThisFloor = (btn.floorKey == MY_FLOOR_KEY)
        local bg, fg
        if i == selectedIndex then
            bg, fg = THEME.btnSelectedBg, THEME.btnSelectedText
        elseif isThisFloor then
            -- Subtly mark the button for the floor we're currently on.
            bg, fg = colors.lightGray, colors.black
        else
            bg, fg = THEME.btnBg, THEME.btnText
        end

        fillButton(btn.label, bg, fg, 1, W, ymin, ymax)
        buttonRegions[i] = { xmin = 1, xmax = W, ymin = ymin, ymax = ymax }
        y = ymax + 1 + gap
    end
end

local function drawScreen()
    mon.setBackgroundColor(THEME.bg)
    mon.clear()
    drawButtons()

    if statusMessage and os.clock() < statusClearAt then
        local lastBtn = buttonRegions[#BUTTONS]
        mon.setBackgroundColor(THEME.bg)
        mon.setTextColor(statusColor)
        local x = math.max(1, math.floor((W - #statusMessage) / 2) + 1)
        mon.setCursorPos(x, lastBtn.ymax)
        mon.write(statusMessage)
    end
end

--====================================================--
--   INPUT HANDLING
--====================================================--

local function handleMonitorTouch(x, y)
    for i, region in pairs(buttonRegions) do
        if x >= region.xmin and x <= region.xmax
           and y >= region.ymin and y <= region.ymax then
            selectedIndex = i
            drawScreen()
            return
        end
    end
end

local function handlePlayerClick(username)
    local btn
    if selectedIndex then
        btn = BUTTONS[selectedIndex]
    else
        -- Find the DEFAULT_FLOOR_KEY button in the BUTTONS list.
        for _, b in ipairs(BUTTONS) do
            if b.floorKey == DEFAULT_FLOOR_KEY then btn = b break end
        end
        -- Fallback: synthesise an entry so the logic below still works.
        if not btn then
            btn = { label = DEFAULT_FLOOR_KEY, requiredRank = 1, floorKey = DEFAULT_FLOOR_KEY }
        end
    end

    local rank = getRank(username)

    if rank < btn.requiredRank then
        setStatus(username .. ": ACCESS DENIED", THEME.msgBad, 2.5)
        drawScreen()
        return
    end

    setStatus(username .. ": Granted", THEME.msgGood, 1.5)
    drawScreen()

    local ok = requestFloor(btn.floorKey)

    if ok then
        setStatus("Moving -> " .. btn.label, THEME.msgGood, 2.5)
    else
        setStatus("No response!", THEME.msgBad, 3)
    end
    selectedIndex = nil
    drawScreen()
end

-- Called when this computer receives a floor request FROM another panel.
local function handleIncomingRequest(senderId, message)
    local floorKey = message.floorKey
    if not FLOORS[floorKey] then
        print("Ignoring unknown floorKey: " .. tostring(floorKey))
        return
    end
    -- Only act if the request is actually for THIS floor.
    if FLOOR_COMPUTERS[floorKey] ~= MY_ID then
        print("Request for '" .. floorKey .. "' arrived here but target ID is "
              .. tostring(FLOOR_COMPUTERS[floorKey]) .. " -- ignoring.")
        return
    end
    print("Floor request from #" .. tostring(senderId) .. " -> " .. floorKey)
    rednet.send(senderId, { action = "ack", floorKey = floorKey }, PROTOCOL)
    -- Pulse redstone AFTER sending the ack so the panel's timer doesn't
    -- expire before we confirm; the physical mechanism fires right after.
    pulseRedstone(floorKey)
end

--====================================================--
--   MAIN LOOP
--====================================================--

local function main()
    refreshRankCache()
    drawScreen()

    local statusTimer = os.startTimer(0.5)

    while true do
        local event, p1, p2, p3 = os.pullEvent()

        if event == "monitor_touch" then
            -- p1 = monitor name, p2 = x, p3 = y
            handleMonitorTouch(p2, p3)

        elseif event == "playerClick" then
            -- p1 = username, p2 = device name
            handlePlayerClick(p1)

        elseif event == "rednet_message" then
            -- p1 = senderId, p2 = message table, p3 = protocol string
            local senderId, message, protocol = p1, p2, p3
            if protocol == PROTOCOL
               and type(message) == "table"
               and message.action == "goToFloor" then
                handleIncomingRequest(senderId, message)
            end
            -- Acks from remote floors while waiting in requestFloor() are
            -- consumed inside that function; if one leaks here it's stale
            -- and safe to drop.

        elseif event == "timer" and p1 == statusTimer then
            if statusMessage and os.clock() >= statusClearAt then
                statusMessage = nil
                drawScreen()
            end
            statusTimer = os.startTimer(0.5)
        end
    end
end

--====================================================--
--   WATCHDOG  (auto-restart on crash)
--====================================================--
while true do
    local ok, err = pcall(main)
    if ok then break end
    print("Elevator panel crashed: " .. tostring(err))
    print("Restarting in 3 seconds...")
    sleep(3)
end
