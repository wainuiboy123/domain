-- ============================================================
--  Base Defense & Whitelist System
--  CC: Tweaked + Advanced Peripherals
--
--  Peripherals needed (all directly touching computer):
--    • player_detector  — detects nearby players
--    • chatBox          — sends chat messages
--    • monitor          — 10 wide x 4 tall (text scale 0.5)
--    • inventory (chest) — for confiscted items
--
--  Files saved to disk:
--    players.json       — all player record
--    message_id.txt     — Discord webhook message ID
-- ============================================================

local WEBHOOK_URL     = "https://discord.com/api/webhooks/1518852807694880818/tJ4d23Ba01Mc1ZekjK5yhSiLykKoKofQ2EFskPzR2rT15U8nPDhYLTNUfLm5u6a2othY"
local BOT_USERNAME    = "Base Defense"
local UPDATE_INTERVAL = 0.5      -- seconds (chat warnings fire every tick)
local BASE_RADIUS     = 200    -- metres
local WARNING_SECONDS = 30     -- countdown before inventory taken
local PLAYER_FILE     = "players.json"
local MSG_ID_FILE     = "message_id.txt"

-- ── Permission levels ────────────────────────────────────────
-- Positive = permanent rank, negative = temp rank, 0 = visitor, -99 = blacklist
local RANKS = {
    [5]   = { name = "Command",               short = "CMD",  colour = colours.yellow,    safe = true  },
    [4]   = { name = "Senior Officer",         short = "SNCO", colour = colours.lime,      safe = true  },
    [3]   = { name = "Officer",                short = "OFF",  colour = colours.green,     safe = true  },
    [2]   = { name = "Member",                 short = "MBR",  colour = colours.cyan,      safe = true  },
    [1]   = { name = "Recruit",                short = "RCT",  colour = colours.lightBlue, safe = true  },
    [0]   = { name = "Visitor",                short = "VIS",  colour = colours.white,     safe = false },
    [-1]  = { name = "Temp Recruit",           short = "TRC",  colour = colours.purple,    safe = true  },
    [-2]  = { name = "Temp Member",            short = "TMB",  colour = colours.purple,    safe = true  },
    [-3]  = { name = "Temp Officer",           short = "TOF",  colour = colours.purple,    safe = true  },
    [-4]  = { name = "Temp Senior Officer",    short = "TSN",  colour = colours.purple,    safe = true  },
    [-99] = { name = "Blacklisted",            short = "BAN",  colour = colours.red,       safe = false },
}

local function isSafe(level)
    local r = RANKS[level]
    return r and r.safe or false
end

local function rankName(level)
    local r = RANKS[level]
    return r and r.name or "Visitor"
end

local function rankShort(level)
    local r = RANKS[level]
    return r and r.short or "VIS"
end

local function rankColour(level)
    local r = RANKS[level]
    return r and r.colour or colours.white
end

-- ── Peripherals ──────────────────────────────────────────────
local detector  = peripheral.find("player_detector")
local chatBox   = peripheral.find("chat_box")
local mon       = peripheral.find("monitor")
local chest     = peripheral.find("inventory_manager")  -- any inventory peripheral

if not detector  then error("No player_detector found!", 0) end
if not chatBox   then error("No chatBox found!", 0) end
if not mon       then error("No monitor found!", 0) end

local detectorName = peripheral.getName(detector)

-- ── Detector position ────────────────────────────────────────
local detectorPos = vector.new(0,0,0)
local ok, bp = pcall(function() return peripheral.call(detectorName,"getBlockPos") end)
if ok and bp then
    detectorPos = vector.new(bp.x, bp.y, bp.z)
end

-- ════════════════════════════════════════════════════════════
--  PLAYER DATABASE
--  players[name] = {
--    level    = number,      -- rank level
--    tempEnd  = number|nil,  -- os.epoch("utc") ms when temp expires
--    lastX, lastY, lastZ, lastDim, lastSeen = strings/numbers
--    online   = bool
--  }
-- ════════════════════════════════════════════════════════════
local players = {}

local function saveDB()
    local f = fs.open(PLAYER_FILE, "w")
    f.write(textutils.serialiseJSON(players))
    f.close()
end

local function loadDB()
    if not fs.exists(PLAYER_FILE) then return end
    local f = fs.open(PLAYER_FILE, "r")
    local raw = f.readAll()
    f.close()
    local ok2, data = pcall(textutils.unserialiseJSON, raw)
    if ok2 and type(data) == "table" then
        players = data
    end
end

local function getPlayer(name)
    if not players[name] then
        players[name] = { level = 0, online = false }
    end
    return players[name]
end

local function setLevel(name, level, tempSeconds)
    local p = getPlayer(name)
    p.level = level
    if tempSeconds then
        p.tempEnd = os.epoch("utc") + (tempSeconds * 1000)
    else
        p.tempEnd = nil
    end
    saveDB()
end

-- Expire temp ranks
local function checkTempExpiry()
    local now = os.epoch("utc")
    for name, p in pairs(players) do
        if p.tempEnd and now >= p.tempEnd then
            p.level   = 0
            p.tempEnd = nil
            saveDB()
        end
    end
end

-- ════════════════════════════════════════════════════════════
--  WARNING / COUNTDOWN STATE
--  countdowns[name] = seconds remaining
-- ════════════════════════════════════════════════════════════
local countdowns = {}   -- name -> seconds left before confiscation

local function distance3D(x,y,z)
    local dx = x - detectorPos.x
    local dy = y - detectorPos.y
    local dz = z - detectorPos.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- ── Confiscate inventory ─────────────────────────────────────
local function confiscateInventory(playerName)
    -- Advanced Peripherals: getPlayerInventory not available directly.
    -- We use the chatBox to inform, and the inventory manager to pull
    -- items from a player using pullItems if supported, otherwise notify.
    local msg = "[BASE DEFENSE] Time expired, " .. playerName ..
                ". Your inventory has been confiscated."
    chatBox.sendMessageToPlayer(msg, playerName, "BASE DEFENSE")

    -- Try to use inventory manager to pull from player
    if chest then
        local pulled = false
        local ok3, err = pcall(function()
            -- Advanced Peripherals inventoryManager.getItems(player) + removeItem
            local mgr = peripheral.find("inventoryManager")
            if mgr then
                local items = mgr.getItems(playerName)
                if items then
                    for slot, item in pairs(items) do
                        local moved = mgr.removeItem(playerName, slot, item.count)
                        if moved and moved > 0 then
                            -- push into chest
                            pulled = true
                        end
                    end
                end
            end
        end)
        if not ok3 then
            print("[WARN] Inventory pull error: " .. tostring(err))
        end
        if not pulled then
            print("[INFO] Could not pull inventory from " .. playerName ..
                  " — ensure inventoryManager peripheral is connected.")
        end
    end

    countdowns[playerName] = nil
end

-- ════════════════════════════════════════════════════════════
--  MONITOR LAYOUT
--  Monitor is 10w x 4h at text scale 0.5 → 20 cols x 8 rows
--  Left  half (cols 1-10):  Player Tracker  (5 blocks wide)
--  Right half (cols 11-20): Whitelist Manager (5 blocks wide)
--  We render both sides every tick.
-- ════════════════════════════════════════════════════════════

-- Whitelist UI paging
local wlPage      = 1
local wlSelected  = nil   -- selected player name
local WL_PER_PAGE = 4     -- rows available for player list

local function mW(x, y, text, fg, bg)
    mon.setCursorPos(x, y)
    if fg  then mon.setTextColour(fg) end
    if bg  then mon.setBackgroundColour(bg) end
    mon.write(text)
end

local function mFill(y, x1, x2, bg)
    mon.setCursorPos(x1, y)
    mon.setBackgroundColour(bg or colours.black)
    mon.write(string.rep(" ", x2 - x1 + 1))
end

local function pad(s, n)
    s = tostring(s)
    if #s >= n then return s:sub(1,n) end
    return s .. string.rep(" ", n - #s)
end

local function rpad(s, n)
    s = tostring(s)
    if #s >= n then return s:sub(1,n) end
    return string.rep(" ", n - #s) .. s
end

-- Sort players into display categories
local function categorise()
    local members  = {}
    local temps    = {}
    local blacklist= {}
    local visitors = {}

    for name, p in pairs(players) do
        local lv = p.level or 0
        if lv >= 1 and lv <= 5 then
            table.insert(members,   { name=name, p=p })
        elseif lv <= -1 and lv >= -4 then
            table.insert(temps,     { name=name, p=p })
        elseif lv == -99 then
            table.insert(blacklist, { name=name, p=p })
        else
            table.insert(visitors,  { name=name, p=p })
        end
    end

    local function byLevel(a,b) return (a.p.level or 0) > (b.p.level or 0) end
    local function byName(a,b)  return a.name < b.name end
    table.sort(members,   byLevel)
    table.sort(temps,     byLevel)
    table.sort(blacklist, byName)
    table.sort(visitors,  byName)

    local combined = {}
    if #members  > 0 then
        table.insert(combined, { header = "-- MEMBERS --" })
        for _,v in ipairs(members)   do table.insert(combined, v) end
    end
    if #temps    > 0 then
        table.insert(combined, { header = "-- TEMPORARY --" })
        for _,v in ipairs(temps)     do table.insert(combined, v) end
    end
    if #blacklist> 0 then
        table.insert(combined, { header = "-- BLACKLIST --" })
        for _,v in ipairs(blacklist) do table.insert(combined, v) end
    end
    if #visitors > 0 then
        table.insert(combined, { header = "-- VISITORS --" })
        for _,v in ipairs(visitors)  do table.insert(combined, v) end
    end
    return combined
end

local function renderMonitor()
    mon.setTextScale(0.5)
    mon.setBackgroundColour(colours.black)
    mon.clear()

    local W, H = mon.getSize()
    -- With a 10-block-wide monitor at scale 0.5 → typically 40 chars wide, 8 tall
    -- We split at midpoint
    local mid = math.floor(W / 2)

    -- ════ LEFT SIDE: Player Tracker ════
    -- Title bar
    mFill(1, 1, mid, colours.grey)
    mW(1, 1, pad(" Players", mid), colours.yellow, colours.grey)

    -- Headers
    mW(1, 2, pad("Name",         8),  colours.lightGrey, colours.black)
    mW(9, 2, pad("Dist",         5),  colours.lightGrey, colours.black)
    mW(14,2, pad("Rank",         mid-13), colours.lightGrey, colours.black)

    -- Divider
    mW(1, 3, string.rep("-", mid), colours.grey, colours.black)

    -- Online players sorted by distance
    local onlineList = {}
    for name, p in pairs(players) do
        if p.online then
            table.insert(onlineList, { name=name, p=p })
        end
    end
    table.sort(onlineList, function(a,b)
        return (a.p.lastDist or 9999) < (b.p.lastDist or 9999)
    end)

    local row = 4
    local maxRows = H - 1  -- leave footer row
    for _, entry in ipairs(onlineList) do
        if row > maxRows then break end
        local p    = entry.p
        local name = entry.name
        local dist = p.lastDist and string.format("%dm", math.floor(p.lastDist)) or "?"
        local col  = rankColour(p.level or 0)
        local cd   = countdowns[name]
        local cdStr= cd and ("!"..cd.."s") or ""

        mFill(row, 1, mid, colours.black)
        mW(1,  row, pad(name:sub(1,7), 7),   col,             colours.black)
        mW(9,  row, pad(dist, 5),             colours.cyan,    colours.black)
        mW(14, row, pad(rankShort(p.level or 0), 4), col,     colours.black)
        if cdStr ~= "" then
            mW(mid-#cdStr, row, cdStr, colours.red, colours.black)
        end
        row = row + 1
    end

    -- Footer (online count)
    mFill(H, 1, mid, colours.grey)
    mW(1, H, pad(" "..#onlineList.." online", mid), colours.grey, colours.grey)

    -- Divider between halves
    for r = 1, H do
        mW(mid+1, r, "|", colours.grey, colours.black)
    end

    -- ════ RIGHT SIDE: Whitelist Manager ════
    local rx = mid + 2  -- right panel start column
    local rw = W - mid - 1  -- right panel width

    mFill(1, mid+2, W, colours.grey)
    mW(rx, 1, pad(" Whitelist", rw), colours.orange, colours.grey)

    local combined = categorise()
    local totalPages = math.max(1, math.ceil(#combined / WL_PER_PAGE))
    if wlPage > totalPages then wlPage = totalPages end

    -- Page nav arrows on title bar
    mW(W-3, 1, " < ", colours.white, colours.grey)
    mW(W,   1, ">",   colours.white, colours.grey)

    -- List entries for this page
    local startIdx = (wlPage - 1) * WL_PER_PAGE + 1
    local listRow  = 2

    for i = startIdx, math.min(startIdx + WL_PER_PAGE - 1, #combined) do
        if listRow > H - 1 then break end
        local entry = combined[i]
        mFill(listRow, rx, W, colours.black)

        if entry.header then
            -- Section header
            mW(rx, listRow, pad(entry.header, rw), colours.yellow, colours.black)
        else
            local p      = entry.p
            local name   = entry.name
            local lv     = p.level or 0
            local col    = rankColour(lv)
            local isOnl  = p.online and "*" or " "
            local isSel  = (wlSelected == name)
            local bg     = isSel and colours.grey or colours.black

            mFill(listRow, rx, W, bg)
            mW(rx,   listRow, isOnl,                      colours.lime,  bg)
            mW(rx+1, listRow, pad(name:sub(1,8), 8),      col,           bg)
            mW(rx+9, listRow, pad(rankShort(lv), rw-9),   col,           bg)

            -- Temp timer
            if p.tempEnd then
                local left = math.max(0, math.floor((p.tempEnd - os.epoch("utc")) / 1000))
                local tStr = left.."s"
                mW(W - #tStr, listRow, tStr, colours.purple, bg)
            end
        end
        listRow = listRow + 1
    end

    -- ── Action buttons on bottom row ──
    mFill(H, mid+2, W, colours.grey)
    -- Only show if someone selected
    if wlSelected then
        mW(rx,    H, "+", colours.lime,   colours.grey)
        mW(rx+1,  H, "-", colours.red,    colours.grey)
        mW(rx+2,  H, "T", colours.purple, colours.grey)
        mW(rx+3,  H, "B", colours.red,    colours.grey)
        mW(rx+5,  H, pad(wlSelected:sub(1,8), 8), colours.white, colours.grey)
    else
        mW(rx, H, pad(" click name to select", rw), colours.grey, colours.grey)
    end
end

-- ════════════════════════════════════════════════════════════
--  MONITOR TOUCH HANDLER
-- ════════════════════════════════════════════════════════════
local tempDuration = 3600  -- default: 1 hour for temp ranks (seconds)

local function handleTouch(x, y)
    mon.setTextScale(0.5)
    local W, H = mon.getSize()
    local mid  = math.floor(W / 2)
    local rx   = mid + 2

    -- Right side only
    if x <= mid then return end

    -- Page arrows on row 1
    if y == 1 then
        local combined   = categorise()
        local totalPages = math.max(1, math.ceil(#combined / WL_PER_PAGE))
        if x >= W-3 and x <= W-1 then  -- < arrow
            wlPage = math.max(1, wlPage - 1)
        elseif x == W then             -- > arrow
            wlPage = math.min(totalPages, wlPage + 1)
        end
        renderMonitor()
        return
    end

    -- Bottom row action buttons
    if y == H and wlSelected then
        local p  = getPlayer(wlSelected)
        local lv = p.level or 0
        if x == rx then
            -- + promote (max 5)
            if lv < 5 then setLevel(wlSelected, math.min(5, lv + 1)) end
        elseif x == rx+1 then
            -- - demote (min 0, but not blacklist)
            if lv > 0 then setLevel(wlSelected, math.max(0, lv - 1)) end
        elseif x == rx+2 then
            -- T = cycle temp rank (visitor -> TRC -> TMB -> TOF -> TSN -> visitor)
            local tempCycle = {[0]=-1, [-1]=-2, [-2]=-3, [-3]=-4, [-4]=0}
            local next = tempCycle[lv]
            if next then
                if next == 0 then
                    setLevel(wlSelected, 0)
                else
                    setLevel(wlSelected, next, tempDuration)
                end
            else
                setLevel(wlSelected, -1, tempDuration)
            end
        elseif x == rx+3 then
            -- B = blacklist toggle
            if lv == -99 then
                setLevel(wlSelected, 0)
            else
                setLevel(wlSelected, -99)
            end
        end
        renderMonitor()
        return
    end

    -- Player list rows 2..H-1
    if y >= 2 and y <= H-1 then
        local combined = categorise()
        local startIdx = (wlPage - 1) * WL_PER_PAGE + 1
        local idx      = startIdx + (y - 2)
        if idx >= 1 and idx <= #combined then
            local entry = combined[idx]
            if entry.name then
                if wlSelected == entry.name then
                    wlSelected = nil  -- deselect
                else
                    wlSelected = entry.name
                end
            end
        end
        renderMonitor()
    end
end

-- ════════════════════════════════════════════════════════════
--  DISCORD WEBHOOK
-- ════════════════════════════════════════════════════════════
local function httpPost(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    local r = http.post(url, payload, headers)
    if not r then return nil, false end
    local b = r.readAll()
    local s = r.getResponseCode()
    r.close()
    return b, (s>=200 and s<300), s
end

local function httpPatch(url, payload, headers)
    headers = headers or {}
    headers["Content-Type"] = "application/json"
    pcall(function()
        http.request({url=url, body=payload, headers=headers, method="PATCH"})
    end)
    while true do
        local ev, _, h = os.pullEvent()
        if ev == "http_success" then
            local b = h.readAll(); local s = h.getResponseCode(); h.close()
            return b, (s>=200 and s<300), s
        elseif ev == "http_failure" then
            return nil, false
        end
    end
end

local function httpGet(url, headers)
    headers = headers or {}
    local r = http.get(url, headers)
    if not r then return nil, false end
    local b = r.readAll(); local s = r.getResponseCode(); r.close()
    return b, (s>=200 and s<300)
end

local function buildDiscord()
    local now    = os.date and os.date("!%Y-%m-%d %H:%M:%S UTC") or "?"
    local lines  = {}
    local online = {}
    local offline= {}

    for name, p in pairs(players) do
        if p.online then table.insert(online, {name=name,p=p})
        else             table.insert(offline,{name=name,p=p}) end
    end
    table.sort(online,  function(a,b) return (a.p.lastDist or 9999)<(b.p.lastDist or 9999) end)
    table.sort(offline, function(a,b) return a.name < b.name end)

    table.insert(lines, "**🛡️ Base Defense — Live Feed** — *"..now.."*")

    -- Online
    table.insert(lines, "```")
    if #online == 0 then
        table.insert(lines, "  (no players online)")
    else
        table.insert(lines, string.format("  %-16s %-6s %8s %7s %5s %7s  %s",
            "Player","Rank","Dist","X","Y","Z","Dimension"))
        table.insert(lines, "  "..string.rep("-",72))
        for _, e in ipairs(online) do
            local p   = e.p
            local dim = (p.lastDim or "?"):gsub("^minecraft:","")
            local dist= p.lastDist and string.format("%.0fm",p.lastDist) or "?"
            local cd  = countdowns[e.name]
            local warn= cd and (" ⚠️ "..cd.."s") or ""
            table.insert(lines, string.format("  %-16s %-6s %8s %7.1f %5.1f %7.1f  %s%s",
                e.name, rankShort(p.level or 0), dist,
                p.lastX or 0, p.lastY or 0, p.lastZ or 0, dim, warn))
        end
    end
    table.insert(lines, "```")

    -- Offline (diff block, red)
    local offlineUnsafe = {}
    for _, e in ipairs(offline) do
        if not isSafe(e.p.level or 0) then table.insert(offlineUnsafe, e) end
    end
    if #offlineUnsafe > 0 then
        table.insert(lines, "**📴 Offline visitors/blacklisted — last known**")
        table.insert(lines, "```diff")
        table.insert(lines, string.format("  %-16s %-6s %7s %5s %7s  %-10s  %s",
            "Player","Rank","X","Y","Z","LastSeen","Dimension"))
        table.insert(lines, "  "..string.rep("-",70))
        for _, e in ipairs(offlineUnsafe) do
            local p   = e.p
            local dim = (p.lastDim or "?"):gsub("^minecraft:","")
            table.insert(lines, string.format("- %-16s %-6s %7.1f %5.1f %7.1f  %-10s  %s",
                e.name, rankShort(p.level or 0),
                p.lastX or 0, p.lastY or 0, p.lastZ or 0,
                p.lastSeen or "?", dim))
        end
        table.insert(lines, "```")
    end

    local total = 0; for _ in pairs(players) do total=total+1 end
    table.insert(lines, string.format(
        "-# %d online · %d total tracked · Base @ %d,%d,%d",
        #online, total, detectorPos.x, detectorPos.y, detectorPos.z))

    return table.concat(lines, "\n")
end

local function loadMsgId()
    if not fs.exists(MSG_ID_FILE) then return nil end
    local f = fs.open(MSG_ID_FILE,"r")
    local id = f.readAll():gsub("%s","")
    f.close()
    return id ~= "" and id or nil
end

local function saveMsgId(id)
    local f = fs.open(MSG_ID_FILE,"w")
    f.write(id); f.close()
end

local function fetchMsg(id)
    local b, ok2 = httpGet(WEBHOOK_URL.."/messages/"..id)
    if not ok2 then return nil end
    local m = textutils.unserialiseJSON(b)
    return m and m.content or nil
end

local function sendMsg(content)
    local payload = textutils.serialiseJSON({username=BOT_USERNAME, content=content})
    local b, ok2 = httpPost(WEBHOOK_URL.."?wait=true", payload)
    if not ok2 then return nil end
    local m = textutils.unserialiseJSON(b)
    return m and m.id or nil
end

local function editMsg(id, content)
    local payload = textutils.serialiseJSON({content=content})
    httpPatch(WEBHOOK_URL.."/messages/"..id, payload)
end

-- Parse offline players from Discord diff block on restart
local function parseDiscordOffline(content)
    if not content then return end
    local inDiff = false
    local count  = 0
    for line in (content.."\n"):gmatch("([^\n]*)\n") do
        if line:match("^```diff") then inDiff = true
        elseif inDiff and line:match("^```") then inDiff = false
        elseif inDiff then
            local rest = line:match("^%- (.+)$")
            if rest and not rest:match("^%-%-") and not rest:match("^Player") then
                local name, x, y, z, seen, dim =
                    rest:match("^(%S+)%s+%S+%s+(%-?%d+%.%d+)%s+(%-?%d+%.%d+)%s+(%-?%d+%.%d+)%s+(%S+)%s+(.+)$")
                if name then
                    local p      = getPlayer(name)
                    p.lastX      = tonumber(x) or p.lastX
                    p.lastY      = tonumber(y) or p.lastY
                    p.lastZ      = tonumber(z) or p.lastZ
                    p.lastSeen   = seen or p.lastSeen
                    p.lastDim    = dim and dim:gsub("%s+$","") or p.lastDim
                    p.online     = false
                    count        = count + 1
                end
            end
        end
    end
    if count > 0 then
        saveDB()
        print("Restored "..count.." offline player(s) from Discord.")
    end
end

-- ════════════════════════════════════════════════════════════
--  MAIN LOOP STATE
-- ════════════════════════════════════════════════════════════
loadDB()

print("=== Base Defense System Starting ===")
print("Detector: "..detectorName)
if chest then print("Chest: "..peripheral.getName(chest)) end
print("")

-- Restore from Discord
local msgId = loadMsgId()
if msgId then
    print("Found message ID: "..msgId)
    local content = fetchMsg(msgId)
    if content then
        parseDiscordOffline(content)
    else
        print("[WARN] Could not fetch Discord message, starting fresh.")
        msgId = nil
    end
end

-- Initial render
renderMonitor()

-- Send/resume Discord
if msgId then
    editMsg(msgId, buildDiscord())
    print("Resumed Discord message: "..msgId)
else
    msgId = sendMsg(buildDiscord())
    if msgId then
        saveMsgId(msgId)
        print("New Discord message: "..msgId)
    end
end

print("Running — Ctrl+T to stop.")
print("")

-- ── Event loop ───────────────────────────────────────────────
local tickTimer = os.startTimer(UPDATE_INTERVAL)
local discordTimer = os.startTimer(5)

while true do
    local ev = { os.pullEvent() }
    local evName = ev[1]

    -- ── 1-second tick ──
    if evName == "timer" and ev[2] == tickTimer then
        tickTimer = os.startTimer(UPDATE_INTERVAL)
        checkTempExpiry()

        -- Get all detected players
        local detectedNames = {}
        local ok3, result = pcall(function() return detector.getOnlinePlayers() end)
        if ok3 and result then
            detectedNames = result
        else
            local r = detector.getPlayersInRange(100000)
            if r then detectedNames = r end
        end

        -- Build detected set with positions
        local detected = {}
        for _, name in ipairs(detectedNames) do
            local pos = detector.getPlayerPos(name)
            if pos then
                detected[name] = pos
            end
        end

        -- Mark previously online players as offline if not detected
        for name, p in pairs(players) do
            if p.online and not detected[name] then
                p.online    = false
                p.lastSeen  = os.date and os.date("!%H:%M:%S") or "?"
                countdowns[name] = nil  -- cancel countdown if they leave
                saveDB()
            end
        end

        -- Update detected players
        for name, pos in pairs(detected) do
            local p      = getPlayer(name)
            local dist   = distance3D(pos.x, pos.y, pos.z)
            p.online     = true
            p.lastX      = pos.x
            p.lastY      = pos.y
            p.lastZ      = pos.z
            p.lastDim    = pos.dimension
            p.lastDist   = dist
            p.lastSeen   = os.date and os.date("!%H:%M:%S") or "?"

            local safe = isSafe(p.level or 0)

            if not safe and dist <= BASE_RADIUS then
                -- Start or continue countdown
                if not countdowns[name] then
                    countdowns[name] = WARNING_SECONDS
                end

                if countdowns[name] > 0 then
                    -- Send warning message
                    local msg = string.format(
                        "⚠ YOU ARE WITHIN %dm OF THE MILITARY BASE. TURN AROUND WITHIN %d SECONDS TO AVOID YOUR INVENTORY BEING TAKEN.",
                        BASE_RADIUS, countdowns[name])
                    pcall(function()
                        chatBox.sendMessageToPlayer(msg, name, "BASE DEFENSE")
                    end)
                    countdowns[name] = countdowns[name] - 1
                else
                    -- Time's up
                    confiscateInventory(name)
                end
            else
                -- Safe player or outside radius — clear countdown
                if countdowns[name] then
                    if dist > BASE_RADIUS then
                        -- Left the zone, reset their countdown for next time
                        countdowns[name] = nil
                    end
                    -- If safe (whitelisted), also clear
                    if safe then
                        countdowns[name] = nil
                    end
                end
            end
        end

        saveDB()
        renderMonitor()

    -- ── Discord update every 5 seconds ──
    elseif evName == "timer" and ev[2] == discordTimer then
        discordTimer = os.startTimer(5)
        local ok4, err = pcall(function()
            editMsg(msgId, buildDiscord())
        end)
        if not ok4 then print("[Discord ERR] "..tostring(err)) end

    -- ── Monitor touch ──
    elseif evName == "monitor_touch" then
        -- ev = { "monitor_touch", monName, x, y }
        handleTouch(ev[3], ev[4])

    -- ── Chat events (optional: listen for admin commands) ──
    elseif evName == "chat" then
        -- future: in-game commands
    end
end
