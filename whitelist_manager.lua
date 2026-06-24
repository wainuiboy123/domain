--====================================================--
--   BASE WHITELIST / RANK MANAGER
--   For CC: Tweaked + Advanced Peripherals
--   Requires: a Monitor, a "player_detector" peripheral,
--             and an enabled HTTP API (this computer must
--             be allowed to reach discord.com).
--   Ranks are stored entirely in a Discord message via a
--   webhook, which gets edited in place on every change.
--====================================================--

--========== PERIPHERAL SETUP ==========--

local monitors = { peripheral.find("monitor") }
if #monitors == 0 then
    error("No monitor connected! Attach a monitor to this computer.")
end

local detector = peripheral.find("player_detector")
if not detector then
    error("No player_detector connected!")
end

--========== DISCORD WEBHOOK CONFIG ==========--
-- Paste your webhook URL below. Create one in Discord via:
--   Channel Settings -> Integrations -> Webhooks -> New Webhook -> Copy Webhook URL
-- NOTE: this computer needs HTTP enabled, and "discord.com" must be allowed
-- in the server's CC: Tweaked config (http.rules) or this will fail to connect.
local WEBHOOK_URL = "https://discord.com/api/webhooks/1519150777174724640/5RcOy3OPeehsFBw1wgHhxgszeLRkIKDufW4sg64QCe1kLHqYuR5nOv4JRTO8xZPd8mhF"

-- The message ID gets cached here on disk so we know which Discord message
-- to edit. This file holds ONLY an id (no rank data) -- ranks themselves
-- live in Discord. If this file is ever lost, the program will just post
-- a fresh message and start caching its id again.
local MSG_ID_FILE = "/disc_whitelist_msg_id.txt"

-- Combine all monitors into one virtual "mon" (mirrors original script's approach)
local mon = {}
for funcName, _ in pairs(monitors[1]) do
    mon[funcName] = function(...)
        local args = { ... }
        for i = 1, #monitors - 1 do
            monitors[i][funcName](table.unpack(args))
        end
        return monitors[#monitors][funcName](table.unpack(args))
    end
end

mon.setTextScale(0.5)
local W, H = mon.getSize()

--========== RANK DEFINITIONS ==========--

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
    bg          = colors.black,
    headerBg    = colors.gray,
    headerText  = colors.white,
    rowBg       = colors.black,
    rowBgAlt    = colors.gray,      -- slight banding for readability
    selectedBg  = colors.blue,
    colHeadFg   = colors.lightGray,
    panelBg     = colors.gray,
    promote     = colors.green,
    demote      = colors.orange,    -- demote button color
    blacklist   = colors.red,       -- dark red equivalent (red is the darkest stock red)
    btnTextOn   = colors.white,
    btnDisabled = colors.gray,
    scrollBg    = colors.gray,
    scrollBtn   = colors.lightGray,
}

--========== STATE ==========--

local players = {}        -- { {name=..., rank=...}, ... } sorted list currently shown
local rankData = {}        -- persisted table: { [username] = rankLevel }
local selectedName = nil   -- currently selected username
local scrollOffset = 0     -- for scrolling the player list
local listRowHeight = 1
local listStartY = 4
local listEndY = H - 6      -- leave room for buttons
local rowsVisible = 0

local button = {}          -- clickable regions: buttons + player rows

--========== DISCORD PERSISTENCE ==========--

-- A small status flag so the UI can show sync state without blocking clicks.
local syncStatus = "idle"   -- "idle" | "syncing" | "error"
local lastError = nil

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

local function setCachedMessageId(id)
    local h = fs.open(MSG_ID_FILE, "w")
    if h then
        h.write(id)
        h.close()
    end
end

-- Builds the embed body Discord will display, and a fenced data block
-- ("username:level" per line) that we parse back out on load. Keeping the
-- data in a code block makes the message human-readable AND machine-parseable.
local function buildEmbedPayload(data)
    local names = {}
    for k in pairs(data) do table.insert(names, k) end
    table.sort(names, function(a, b)
        if data[a] ~= data[b] then return data[a] > data[b] end
        return a < b
    end)

    local lines = {}
    local dataLines = {}
    for _, name in ipairs(names) do
        local lvl = data[name]
        local info = RANKS[lvl] or RANKS[0]
        table.insert(lines, string.format("**%s** — %s (%d)", name, info.name, lvl))
        table.insert(dataLines, string.format("%s:%d", name, lvl))
    end
    if #lines == 0 then
        table.insert(lines, "_No ranked players yet._")
    end

    local description = table.concat(lines, "\n")
        .. "\n```\n" .. table.concat(dataLines, "\n") .. "\n```"

    return {
        embeds = {
            {
                title = "Base Whitelist - Current Ranks",
                description = description,
                color = 0x2ECC71,
                footer = { text = "Last updated automatically by the whitelist computer" },
            },
        },
    }
end

-- Parses the fenced "username:level" block back out of a message's embed description.
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
-- re-queueing any unrelated events so the main loop doesn't lose them
-- (monitor touches, timers, playerJoin/playerLeave, etc).
local function waitForHttp(url)
    while true do
        local event, evUrl, p3, p4 = os.pullEvent()
        if (event == "http_success" or event == "http_failure") and evUrl == url then
            return event, p3, p4
        else
            os.queueEvent(event, evUrl, p3, p4)
            -- yield so we don't spin hot if nothing else is pulling these
            os.sleep(0)
        end
    end
end

-- Pushes the given rank table to Discord: edits the cached message if we have
-- one, otherwise posts a new message (with ?wait=true so we get its id back).
local function pushToDiscord(data)
    syncStatus = "syncing"
    local payload = buildEmbedPayload(data)
    local body = textutils.serialiseJSON(payload)
    local headers = { ["Content-Type"] = "application/json" }

    local msgId = getCachedMessageId()

    if msgId then
        local patchUrl = WEBHOOK_URL .. "/messages/" .. msgId
        local ok = pcall(http.request, {
            url = patchUrl,
            body = body,
            method = "PATCH",
            headers = headers,
        })
        if ok then
            local event, handle = waitForHttp(patchUrl)
            if event == "http_success" then
                if handle then handle.close() end
                syncStatus = "idle"
                return true
            end
            -- PATCH failed (message likely deleted on Discord's side) --
            -- fall through below and post a fresh message instead.
            msgId = nil
        end
    end

    if not msgId then
        local postUrl = WEBHOOK_URL .. "?wait=true"
        local ok = pcall(http.request, {
            url = postUrl,
            body = body,
            method = "POST",
            headers = headers,
        })
        if not ok then
            syncStatus = "error"
            lastError = "Failed to send HTTP request"
            return false
        end
        local event, handle = waitForHttp(postUrl)
        if event == "http_success" then
            local respBody = handle.readAll()
            handle.close()
            local parsed = textutils.unserialiseJSON(respBody)
            if parsed and parsed.id then
                setCachedMessageId(parsed.id)
            end
            syncStatus = "idle"
            return true
        else
            syncStatus = "error"
            lastError = "Discord rejected the request"
            return false
        end
    end

    syncStatus = "error"
    return false
end

-- Pulls the current rank table from the Discord message (recovery path / boot load).
local function pullFromDiscord()
    local msgId = getCachedMessageId()
    if not msgId then return {} end

    local getUrl = WEBHOOK_URL .. "/messages/" .. msgId
    local ok = pcall(http.request, { url = getUrl, method = "GET" })
    if not ok then return {} end

    local event, handle = waitForHttp(getUrl)
    if event == "http_success" then
        local respBody = handle.readAll()
        handle.close()
        local parsed = textutils.unserialiseJSON(respBody)
        if parsed and parsed.embeds and parsed.embeds[1] then
            return parseRanksFromDescription(parsed.embeds[1].description)
        end
        return {}
    end
    return {}
end

local function loadData()
    rankData = pullFromDiscord()
end

local function saveData()
    -- Only ranks above 0 (or blacklisted at -1) ever get persisted; 0 is
    -- default and is never written to the Discord message.
    local toSave = {}
    for k, v in pairs(rankData) do
        if v ~= 0 then
            toSave[k] = v
        end
    end
    pushToDiscord(toSave)
end

local function getRank(username)
    return rankData[username] or 0
end

--========== DRAW HELPERS ==========--

local function clear()
    mon.setBackgroundColor(THEME.bg)
    mon.setTextColor(colors.white)
    mon.clear()
end

local function centerText(y, text, fg, bg)
    mon.setBackgroundColor(bg or THEME.bg)
    mon.setTextColor(fg or colors.white)
    local x = math.floor((W - #text) / 2) + 1
    mon.setCursorPos(1, y)
    mon.write(string.rep(" ", W))
    mon.setCursorPos(x, y)
    mon.write(text)
end

local function drawHeader()
    centerText(1, "BASE WHITELIST MANAGER", colors.yellow, THEME.bg)

    -- small sync-status indicator in the top-right corner
    mon.setBackgroundColor(THEME.bg)
    mon.setCursorPos(W - 9, 1)
    if syncStatus == "syncing" then
        mon.setTextColor(colors.yellow)
        mon.write("Syncing..")
    elseif syncStatus == "error" then
        mon.setTextColor(colors.red)
        mon.write("Sync FAIL")
    else
        mon.setTextColor(colors.lime)
        mon.write(" Synced  ")
    end

    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    mon.setCursorPos(1, 2)
    mon.write(string.rep(" ", W))
    mon.setCursorPos(2, 2)
    mon.write("USERNAME")
    local rankColX = math.floor(W * 0.55)
    mon.setCursorPos(rankColX, 2)
    mon.write("RANK")
    local lvlColX = W - 7
    mon.setCursorPos(lvlColX, 2)
    mon.write("LEVEL")
end

-- registers a button region (re-used for both nav buttons and player rows)
local function setButtonRegion(name, func, param, xmin, xmax, ymin, ymax)
    button[name] = {
        func = func, param = param,
        xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
    }
end

local function clearButtons()
    button = {}
end

-- fill a rectangular button area with centered text (from original script's `fill`)
local function fillRect(text, bg, fg, xmin, xmax, ymin, ymax)
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg or colors.white)
    local width = xmax - xmin + 1
    local yspot = math.floor((ymin + ymax) / 2)
    local leftPad = math.floor((width - #text) / 2)
    local rightPad = width - #text - leftPad
    for y = ymin, ymax do
        mon.setCursorPos(xmin, y)
        if y == yspot then
            mon.write(string.rep(" ", math.max(0, leftPad)))
            mon.write(text)
            mon.write(string.rep(" ", math.max(0, rightPad)))
        else
            mon.write(string.rep(" ", width))
        end
    end
end

--========== PLAYER LIST ==========--

local function refreshPlayerList()
    local online = detector.getOnlinePlayers()
    players = {}
    for _, name in ipairs(online) do
        table.insert(players, { name = name, rank = getRank(name) })
    end
    table.sort(players, function(a, b)
        if a.rank ~= b.rank then
            return a.rank > b.rank  -- highest rank first
        end
        return a.name < b.name      -- alphabetical tie-breaker
    end)
    rowsVisible = listEndY - listStartY + 1
    if scrollOffset > math.max(0, #players - rowsVisible) then
        scrollOffset = math.max(0, #players - rowsVisible)
    end
end

local function drawPlayerRow(y, p, isSelected)
    local rankInfo = RANKS[p.rank] or RANKS[0]
    local rowBg = isSelected and THEME.selectedBg or THEME.bg

    mon.setBackgroundColor(rowBg)
    mon.setCursorPos(1, y)
    mon.write(string.rep(" ", W))

    -- username
    mon.setTextColor(isSelected and colors.white or colors.white)
    mon.setCursorPos(2, y)
    mon.write(p.name)

    -- rank name, colored
    local rankColX = math.floor(W * 0.55)
    mon.setCursorPos(rankColX, y)
    mon.setTextColor(rankInfo.color)
    mon.write(rankInfo.name)

    -- level number
    local lvlColX = W - 7
    mon.setCursorPos(lvlColX, y)
    mon.setTextColor(rankInfo.color)
    mon.write(tostring(p.rank))

    mon.setBackgroundColor(THEME.bg)
end

local function selectPlayer(name)
    selectedName = name
    drawScreen()
end

local function drawPlayerList()
    rowsVisible = listEndY - listStartY + 1
    for i = 1, rowsVisible do
        local idx = i + scrollOffset
        local y = listStartY + i - 1
        local p = players[idx]
        if p then
            drawPlayerRow(y, p, p.name == selectedName)
            setButtonRegion("row_" .. p.name, selectPlayer, p.name, 1, W, y, y)
        else
            mon.setBackgroundColor(THEME.bg)
            mon.setCursorPos(1, y)
            mon.write(string.rep(" ", W))
        end
    end

    -- scroll indicators
    mon.setBackgroundColor(THEME.bg)
    if scrollOffset > 0 then
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(W, listStartY)
        mon.write("^")
        setButtonRegion("scroll_up", function()
            scrollOffset = math.max(0, scrollOffset - 1)
            drawScreen()
        end, nil, W, W, listStartY, listStartY)
    end
    if scrollOffset + rowsVisible < #players then
        mon.setTextColor(colors.yellow)
        mon.setCursorPos(W, listEndY)
        mon.write("v")
        setButtonRegion("scroll_down", function()
            scrollOffset = scrollOffset + 1
            drawScreen()
        end, nil, W, W, listEndY, listEndY)
    end
end

--========== ACTION BUTTONS ==========--

-- Applies a local rank change, redraws immediately (so the screen never
-- looks frozen), then syncs to Discord in the background and redraws again
-- once that finishes (to confirm success or flag an error).
local function applyRankChange(username, newLevel)
    if newLevel == 0 then
        rankData[username] = nil
    else
        rankData[username] = newLevel
    end
    refreshPlayerList()
    drawScreen()           -- instant feedback, shows "Syncing..."
    saveData()              -- blocking HTTP call to Discord
    refreshPlayerList()
    drawScreen()            -- final state, shows "Synced" or "Sync FAIL"
end

local function doPromote()
    if not selectedName then return end
    local lvl = math.min(MAX_RANK, getRank(selectedName) + 1)
    applyRankChange(selectedName, lvl)
end

local function doDemote()
    if not selectedName then return end
    local lvl = math.max(MIN_RANK, getRank(selectedName) - 1)
    applyRankChange(selectedName, lvl)
end

local function doBlacklist()
    if not selectedName then return end
    applyRankChange(selectedName, -1)
end

local function drawActionButtons()
    local btnTop = H - 4
    local btnBottom = H - 1
    local gap = 1
    local third = math.floor((W - gap * 2) / 3)

    local x1min, x1max = 1, third
    local x2min, x2max = third + 1 + gap, third * 2 + gap
    local x3min, x3max = third * 2 + gap * 2 + 1, W

    local hasSelection = selectedName ~= nil

    -- PROMOTE
    fillRect(
        "PROMOTE",
        hasSelection and THEME.promote or THEME.btnDisabled,
        colors.white, x1min, x1max, btnTop, btnBottom
    )
    setButtonRegion("btn_promote", doPromote, nil, x1min, x1max, btnTop, btnBottom)

    -- DEMOTE
    fillRect(
        "DEMOTE",
        hasSelection and THEME.demote or THEME.btnDisabled,
        colors.white, x2min, x2max, btnTop, btnBottom
    )
    setButtonRegion("btn_demote", doDemote, nil, x2min, x2max, btnTop, btnBottom)

    -- BLACKLIST
    fillRect(
        "BLACKLIST",
        hasSelection and THEME.blacklist or THEME.btnDisabled,
        colors.white, x3min, x3max, btnTop, btnBottom
    )
    setButtonRegion("btn_blacklist", doBlacklist, nil, x3min, x3max, btnTop, btnBottom)

    -- Selected player info line just above buttons
    mon.setBackgroundColor(THEME.bg)
    mon.setCursorPos(1, btnTop - 1)
    mon.write(string.rep(" ", W))
    mon.setCursorPos(2, btnTop - 1)
    if selectedName then
        local rankInfo = RANKS[getRank(selectedName)] or RANKS[0]
        mon.setTextColor(colors.white)
        mon.write("Selected: ")
        mon.setTextColor(colors.yellow)
        mon.write(selectedName)
        mon.setTextColor(colors.white)
        mon.write("  (")
        mon.setTextColor(rankInfo.color)
        mon.write(rankInfo.name)
        mon.setTextColor(colors.white)
        mon.write(")")
    else
        mon.setTextColor(colors.lightGray)
        mon.write("Select a player above to manage their rank")
    end
end

--========== MASTER DRAW ==========--

function drawScreen()
    clearButtons()
    clear()
    drawHeader()
    drawPlayerList()
    drawActionButtons()
end

--========== EVENT LOOP ==========--

local function checkClick(x, y)
    for _, data in pairs(button) do
        if y >= data.ymin and y <= data.ymax and x >= data.xmin and x <= data.xmax then
            if data.param ~= nil then
                data.func(data.param)
            else
                data.func()
            end
            return true
        end
    end
    return false
end

local function main()
    -- quick boot screen while we pull the current ranks from Discord
    mon.setBackgroundColor(THEME.bg)
    mon.clear()
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(2, 2)
    mon.write("Loading ranks from Discord...")

    loadData()
    refreshPlayerList()
    drawScreen()

    local refreshTimer = os.startTimer(5)

    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "monitor_touch" then
            checkClick(p2, p3)
        elseif event == "timer" and p1 == refreshTimer then
            refreshPlayerList()
            drawScreen()
            refreshTimer = os.startTimer(5)
        elseif event == "playerJoin" or event == "playerLeave" then
            refreshPlayerList()
            drawScreen()
        end
    end
end

main()
