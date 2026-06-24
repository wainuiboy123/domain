--====================================================--
--   ELEVATOR CALL PANEL
--   For CC: Tweaked + Advanced Peripherals
--   Requires: a 1x1 Monitor + a "player_detector"
--             peripheral, both connected to this computer,
--             PLUS an Ender Modem (this computer rides on a
--             moving structure, so it talks to the floor
--             computers wirelessly instead of wiring
--             redstone directly).
--
--   This is the PANEL half of a six-computer system:
--     1 panel computer (this script) +
--     5 floor receiver computers (run "elevator_receiver.lua"
--     on each one -- one per floor, each wired into that
--     floor's own redstone).
--
--   Each floor button below is tied to a SPECIFIC receiver
--   computer's ID. When a button is selected and the player
--   detector is right-clicked, the panel sends the request
--   directly to that one floor's computer -- not a shared
--   "floorId" routed through a single receiver.
--
--   Reads player ranks from the SAME Discord webhook
--   message used by the whitelist manager script, so both
--   programs always agree on everyone's rank.
--====================================================--

--========== PERIPHERAL SETUP ==========--

local mon = peripheral.find("monitor")
if not mon then
    error("No monitor connected! Attach a 1x1 monitor to this computer.")
end

local detector = peripheral.find("player_detector")
if not detector then
    error("No player_detector connected!")
end

local modem = peripheral.find("modem")
if not modem then
    error("No Ender Modem connected! This panel needs one since it's on a " ..
          "moving structure and can't wire redstone directly.")
end

mon.setTextScale(0.5)
local W, H = mon.getSize()

--========== FLOOR / RECEIVER COMPUTER IDS (CUSTOMIZE ME) ==========--
-- Put every floor's receiver computer ID here. To find a computer's ID,
-- boot it up and look at the top of its screen -- elevator_receiver.lua
-- prints its own ID on startup -- or run the "id" program in its shell.
--
-- These IDs are referenced by the BUTTONS list and DEFAULT_FLOOR further
-- down, so set them ALL here first and you won't need to hunt through the
-- rest of the script.

local RECEIVER_IDS = {
    topFloor     = 15,  -- <-- CHANGE to the Top Floor computer's ID
    tunnel       = 12,  -- <-- CHANGE to the Tunnel computer's ID
    testingFloor = 11,  -- <-- CHANGE to the Testing Floor computer's ID
    fourthFloor  = 13,  -- <-- CHANGE to the 4th floor computer's ID
    commandFloor = 14,  -- <-- CHANGE to the Command Floor computer's ID
}

-- A shared "password" of sorts so receivers only react to messages from
-- this panel and not random rednet traffic. Change it to anything; just
-- make sure every elevator_receiver.lua uses the exact same string.
local PROTOCOL = "elevator_panel_v1"

rednet.open(peripheral.getName(modem))
print("This panel's computer ID is: " .. os.getComputerID())

--========== DISCORD WEBHOOK CONFIG ==========--
-- Use the EXACT SAME webhook URL as the whitelist manager script, so this
-- panel reads the same rank data that script writes.
local WEBHOOK_URL = "https://discord.com/api/webhooks/1519150777174724640/5RcOy3OPeehsFBw1wgHhxgszeLRkIKDufW4sg64QCe1kLHqYuR5nOv4JRTO8xZPd8mhF"

-- Cached message id -- must point at the SAME message the whitelist script
-- maintains. Easiest way to guarantee that: copy the whitelist computer's
-- /disc_whitelist_msg_id.txt file onto this computer at the same path.
local MSG_ID_FILE = "/disc_whitelist_msg_id.txt"

-- How long (in seconds) cached rank data is considered fresh before this
-- panel re-checks Discord. Keeps things snappy without hammering the API
-- on every single right-click.
local RANK_CACHE_SECONDS = 15

--========== BUTTON CONFIG (CUSTOMIZE ME) ==========--
-- label:        text shown on the button
-- requiredRank: minimum rank LEVEL needed to use this button
--               (-1 Blacklisted, 0 Visitor(default), 1 Visitor, 2 Recruit,
--                3 Member, 4 Officer, 5 Senior Officer, 6 Command)
-- receiverId:   which floor's receiver computer this button targets
--               (pulled from RECEIVER_IDS above)

local BUTTONS = {
    { label = "TUNNEL",   requiredRank = 3, receiverId = RECEIVER_IDS.tunnel },
    { label = "STORAGE",  requiredRank = 3, receiverId = RECEIVER_IDS.testingFloor },
    { label = "TESTING",  requiredRank = 4, receiverId = RECEIVER_IDS.fourthFloor },
    { label = "COMMAND",  requiredRank = 5, receiverId = RECEIVER_IDS.commandFloor },
}

-- Right-clicking the player detector with NO button selected sends the
-- elevator to this floor instead.
local DEFAULT_FLOOR = { label = "TOP", requiredRank = 1, receiverId = RECEIVER_IDS.topFloor }

--========== RANK DEFINITIONS ==========--
-- Mirrors the whitelist manager script so rank names/levels line up exactly.

local RANKS = {
    [-1] = { name = "Blacklisted",     color = colors.red },
    [0]  = { name = "Visitor",         color = colors.lightGray },
    [1]  = { name = "Visitor",         color = colors.white },
    [2]  = { name = "Recruit",         color = colors.lime },
    [3]  = { name = "Member",          color = colors.lime },
    [4]  = { name = "Officer",         color = colors.green },
    [5]  = { name = "Senior Officer",  color = colors.green },
    [6]  = { name = "Command",         color = colors.green },
}
local MIN_RANK = -1
local MAX_RANK = 6

--========== THEME ==========--

local THEME = {
    bg            = colors.black,
    btnBg         = colors.white,
    btnText       = colors.black,
    btnSelectedBg = colors.green,
    btnSelectedText = colors.white,
    btnDeniedBg   = colors.red,
    btnDeniedText = colors.white,
    msgGood       = colors.lime,
    msgBad        = colors.red,
}

--========== STATE ==========--

local selectedIndex = nil      -- index into BUTTONS, currently armed selection
local rankCache = {}           -- { [username] = level }
local rankCacheTime = 0        -- os.clock() time of last successful fetch
local statusMessage = nil      -- transient message shown at the bottom
local statusColor = colors.white
local statusClearAt = 0

local buttonRegions = {}       -- clickable regions for monitor_touch

--========== DISCORD RANK LOOKUP ==========--

local function getCachedMessageId()
    if not fs.exists(MSG_ID_FILE) then return nil end
    local h = fs.open(MSG_ID_FILE, "r")
    if not h then return nil end
    local id = h.readAll()
    h.close()
    id = id and id:gsub("%s+", "") or nil
    if id == "" then return nil end
    return id
end

-- Parses the fenced "username:level" block back out of the embed description
-- (same format the whitelist manager script writes).
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

-- Waits for a specific http_success/http_failure pair matching `url`,
-- re-queueing any unrelated events so playerClick/monitor_touch/timers
-- that happen mid-request aren't lost.
local function waitForHttp(url)
    while true do
        local event, evUrl, p3, p4 = os.pullEvent()
        if (event == "http_success" or event == "http_failure") and evUrl == url then
            return event, p3, p4
        else
            os.queueEvent(event, evUrl, p3, p4)
            os.sleep(0)
        end
    end
end

local function refreshRankCache()
    local msgId = getCachedMessageId()
    if not msgId then return false end

    local getUrl = WEBHOOK_URL .. "/messages/" .. msgId
    local ok = pcall(http.request, { url = getUrl, method = "GET" })
    if not ok then return false end

    local event, handle = waitForHttp(getUrl)
    if event == "http_success" then
        local respBody = handle.readAll()
        handle.close()
        local parsed = textutils.unserialiseJSON(respBody)
        if parsed and parsed.embeds and parsed.embeds[1] then
            rankCache = parseRanksFromDescription(parsed.embeds[1].description)
            rankCacheTime = os.clock()
            return true
        end
    end
    return false
end

local function getRank(username)
    -- Refresh if our cache is stale.
    if os.clock() - rankCacheTime > RANK_CACHE_SECONDS then
        refreshRankCache()
    end
    return rankCache[username] or 0
end

--========== WIRELESS FLOOR REQUEST ==========--

-- Sends the floor request to the stationary receiver computer and waits
-- (briefly) for an acknowledgment so the panel can show success/failure.
-- Returns true if the receiver confirmed, false on timeout/no response.
local function requestFloor(floorId)
    rednet.send(RECEIVER_ID, { action = "goToFloor", floorId = floorId }, PROTOCOL)

    local timer = os.startTimer(3)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "rednet_message" then
            local senderId, message, protocol = p1, p2, p3
            if senderId == RECEIVER_ID and protocol == PROTOCOL
               and type(message) == "table" and message.action == "ack"
               and message.floorId == floorId then
                return true
            else
                os.queueEvent(event, p1, p2, p3)
            end
        elseif event == "timer" and p1 == timer then
            return false
        else
            os.queueEvent(event, p1, p2, p3)
        end
    end
end

--========== DRAWING ==========--

local function setStatus(text, color, holdSeconds)
    statusMessage = text
    statusColor = color
    statusClearAt = os.clock() + (holdSeconds or 2.5)
end

-- Centers text inside a rectangular region, both horizontally and vertically.
local function fillButton(text, bg, fg, xmin, xmax, ymin, ymax)
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    local width = xmax - xmin + 1
    local height = ymax - ymin + 1
    local textY = ymin + math.floor((height - 1) / 2)
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

    local gap = 1
    local totalGap = gap * (#BUTTONS - 1)
    local usableHeight = H - totalGap
    local rowHeight = math.floor(usableHeight / #BUTTONS)
    local leftover = usableHeight - (rowHeight * #BUTTONS)

    local y = 1
    for i, btn in ipairs(BUTTONS) do
        -- distribute any leftover rows to the first buttons so the set
        -- of buttons always fills exactly 100% of the monitor height
        local thisHeight = rowHeight + ((i <= leftover) and 1 or 0)
        local ymin = y
        local ymax = y + thisHeight - 1

        local bg, fg
        if i == selectedIndex then
            bg, fg = THEME.btnSelectedBg, THEME.btnSelectedText
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

    -- transient status message overlays the bottom row of the last button
    -- briefly, then clears itself on the next redraw once expired.
    if statusMessage and os.clock() < statusClearAt then
        local lastBtn = buttonRegions[#BUTTONS]
        mon.setBackgroundColor(THEME.bg)
        mon.setTextColor(statusColor)
        local x = math.max(1, math.floor((W - #statusMessage) / 2) + 1)
        mon.setCursorPos(x, lastBtn.ymax)
        mon.write(statusMessage)
    end
end

--========== INPUT HANDLING ==========--

local function handleMonitorTouch(x, y)
    for i, region in pairs(buttonRegions) do
        if x >= region.xmin and x <= region.xmax and y >= region.ymin and y <= region.ymax then
            selectedIndex = i
            drawScreen()
            return
        end
    end
end

local function handlePlayerClick(username)
    local btn = selectedIndex and BUTTONS[selectedIndex] or DEFAULT_FLOOR
    local rank = getRank(username)

    if rank < btn.requiredRank then
        setStatus(username .. ": ACCESS DENIED", THEME.msgBad, 2.5)
        drawScreen()
        return
    end

    setStatus(username .. ": Access granted", THEME.msgGood, 2)
    drawScreen()

    local ok = requestFloor(btn.floorId)

    if ok then
        setStatus("Moving to " .. btn.label, THEME.msgGood, 2.5)
    else
        setStatus("No response from receiver!", THEME.msgBad, 3)
    end
    selectedIndex = nil
    drawScreen()
end

--========== MAIN LOOP ==========--

local function main()
    refreshRankCache()
    drawScreen()

    local statusTimer = os.startTimer(0.5)

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "monitor_touch" then
            handleMonitorTouch(p2, p3)
        elseif event == "playerClick" then
            -- playerClick fires with (username, devicename)
            handlePlayerClick(p1)
        elseif event == "timer" and p1 == statusTimer then
            -- redraw periodically so expired status messages clear themselves
            if statusMessage and os.clock() >= statusClearAt then
                statusMessage = nil
                drawScreen()
            end
            statusTimer = os.startTimer(0.5)
        end
    end
end

-- Watchdog: if anything inside main() throws (a momentary HTTP hiccup, a
-- dropped peripheral, etc), log it and restart main() after a short pause
-- instead of leaving the panel dead until someone notices and reruns it.
-- Combined with copying this file to /startup.lua, the panel comes back on
-- its own after a server restart AND after any in-game crash.
while true do
    local ok, err = pcall(main)
    if ok then
        break -- main() returned normally (shouldn't happen, but don't loop forever if it does)
    end
    print("Elevator panel crashed: " .. tostring(err))
    print("Restarting in 3 seconds...")
    sleep(3)
end
