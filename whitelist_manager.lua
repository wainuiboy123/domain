--====================================================--
--   BASE WHITELIST / RANK MANAGER
--   For CC: Tweaked + Advanced Peripherals
--   Requires: a Monitor, a "player_detector", and an
--             "nbt_storage" peripheral connected via
--             wired/ender modem (or directly adjacent).
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

local nbt = peripheral.find("nbt_storage")
if not nbt then
    error("No nbt_storage connected!")
end

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
    demote      = colors.pink,      -- "light red"
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

--========== NBT PERSISTENCE ==========--

local function loadData()
    local ok, data = pcall(function() return nbt.read() end)
    rankData = {}
    if ok and type(data) == "table" then
        for k, v in pairs(data) do
            local lvl = tonumber(v)
            if lvl and lvl >= MIN_RANK and lvl <= MAX_RANK and lvl ~= 0 then
                rankData[k] = lvl
            end
        end
    end
end

local function saveData()
    -- Only ranks above 0 (or blacklisted at -1) get persisted; 0 is default and never stored.
    local toSave = {}
    for k, v in pairs(rankData) do
        if v ~= 0 then
            toSave[k] = v
        end
    end
    nbt.writeTable(toSave)
end

local function getRank(username)
    return rankData[username] or 0
end

local function setRank(username, level)
    if level <= 0 then
        rankData[username] = nil   -- 0 or below default isn't stored... but -1 (blacklist) must persist
    end
    if level == 0 then
        rankData[username] = nil
    else
        rankData[username] = level
    end
    saveData()
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
    local yspot = math.floor((ymin + ymax) / 2)
    local xspot = math.floor((xmax - xmin - #text) / 2)
    for y = ymin, ymax do
        mon.setCursorPos(xmin, y)
        if y == yspot then
            mon.write(string.rep(" ", xspot))
            mon.write(text)
            mon.write(string.rep(" ", math.max(0, xmax - xmin + 1 - xspot - #text)))
        else
            mon.write(string.rep(" ", xmax - xmin + 1))
        end
    end
end

--========== PLAYER LIST ==========--

local function refreshPlayerList()
    local online = detector.getOnlinePlayers()
    table.sort(online)
    players = {}
    for _, name in ipairs(online) do
        table.insert(players, { name = name, rank = getRank(name) })
    end
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

local function doPromote()
    if not selectedName then return end
    local lvl = getRank(selectedName)
    lvl = math.min(MAX_RANK, lvl + 1)
    setRank(selectedName, lvl)
    refreshPlayerList()
    drawScreen()
end

local function doDemote()
    if not selectedName then return end
    local lvl = getRank(selectedName)
    lvl = math.max(MIN_RANK, lvl - 1)
    setRank(selectedName, lvl)
    refreshPlayerList()
    drawScreen()
end

local function doBlacklist()
    if not selectedName then return end
    setRank(selectedName, -1)
    refreshPlayerList()
    drawScreen()
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
        hasSelection and "PROMOTE" or "PROMOTE",
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
