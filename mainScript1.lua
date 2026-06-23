-- ============================================================
--  Base Defense & Whitelist System
--  CC: Tweaked + Advanced Peripherals 0.7.x
--
--  Peripherals needed (all directly touching computer):
--    • player_detector
--    • chat_box
--    • monitor          (8 wide x 4 tall blocks, scale 0.5)
--    • inventory_manager
-- ============================================================

local WEBHOOK_URL     = "https://discord.com/api/webhooks/1518852807694880818/tJ4d23Ba01Mc1ZekjK5yhSiLykKoKofQ2EFskPzR2rT15U8nPDhYLTNUfLm5u6a2othY"
local BOT_USERNAME    = "Base Defense"
local UPDATE_INTERVAL = 0.5
local BASE_RADIUS     = 200
local WARNING_SECONDS = 30
local PLAYER_FILE     = "players.json"
local MSG_ID_FILE     = "message_id.txt"

-- ── Rank definitions ─────────────────────────────────────────
-- level 1-5 = permanent, -1 to -4 = temp, 0 = visitor, -99 = blacklist
local RANKS = {
    [5]   = { name="Command",           short="CMD", col=colours.yellow,    safe=true  },
    [4]   = { name="Senior Officer",    short="SNR", col=colours.lime,      safe=true  },
    [3]   = { name="Officer",           short="OFF", col=colours.green,     safe=true  },
    [2]   = { name="Member",            short="MBR", col=colours.cyan,      safe=true  },
    [1]   = { name="Recruit",           short="RCT", col=colours.lightBlue, safe=true  },
    [0]   = { name="Visitor",           short="VIS", col=colours.white,     safe=false },
    [-1]  = { name="Temp Recruit",      short="TRC", col=colours.purple,    safe=true  },
    [-2]  = { name="Temp Member",       short="TMB", col=colours.purple,    safe=true  },
    [-3]  = { name="Temp Officer",      short="TOF", col=colours.purple,    safe=true  },
    [-4]  = { name="Temp Sr. Officer",  short="TSN", col=colours.purple,    safe=true  },
    [-99] = { name="Blacklisted",       short="BAN", col=colours.red,       safe=false },
}

local function isSafe(lv)  local r=RANKS[lv]; return r and r.safe or false end
local function rName(lv)   local r=RANKS[lv]; return r and r.name  or "Visitor" end
local function rShort(lv)  local r=RANKS[lv]; return r and r.short or "VIS" end
local function rCol(lv)    local r=RANKS[lv]; return r and r.col   or colours.white end

-- ── Peripherals ──────────────────────────────────────────────
local detector = peripheral.find("player_detector")
local chatBox  = peripheral.find("chat_box")
local mon      = peripheral.find("monitor")
local invMgr   = peripheral.find("inventory_manager")

if not detector then error("No player_detector found!", 0) end
if not chatBox  then error("No chat_box found!", 0) end
if not mon      then error("No monitor found!", 0) end
if not invMgr   then print("[WARN] No inventory_manager found — confiscation disabled") end

local detName = peripheral.getName(detector)

-- ── Detector world position ──────────────────────────────────
local dPos = vector.new(0,0,0)
local ok, bp = pcall(function() return peripheral.call(detName,"getBlockPos") end)
if ok and bp then dPos = vector.new(bp.x, bp.y, bp.z) end

local function dist3(x,y,z)
    return math.sqrt((x-dPos.x)^2 + (y-dPos.y)^2 + (z-dPos.z)^2)
end

-- ════════════════════════════════════════════════════════════
--  PLAYER DATABASE
-- ════════════════════════════════════════════════════════════
local players = {}   -- [name] = { level, tempEnd, lastX/Y/Z/Dim/Dist/Seen, online }

local function saveDB()
    local f = fs.open(PLAYER_FILE,"w")
    f.write(textutils.serialiseJSON(players))
    f.close()
end

local function loadDB()
    if not fs.exists(PLAYER_FILE) then return end
    local f = fs.open(PLAYER_FILE,"r")
    local raw = f.readAll(); f.close()
    local ok2,d = pcall(textutils.unserialiseJSON, raw)
    if ok2 and type(d)=="table" then players=d end
end

local function getP(name)
    if not players[name] then players[name]={level=0,online=false} end
    return players[name]
end

local function setLevel(name, lv, tempSecs)
    local p = getP(name)
    p.level = lv
    p.tempEnd = tempSecs and (os.epoch("utc") + tempSecs*1000) or nil
    saveDB()
end

local function checkExpiry()
    local now = os.epoch("utc")
    for name,p in pairs(players) do
        if p.tempEnd and now >= p.tempEnd then
            p.level=0; p.tempEnd=nil; saveDB()
        end
    end
end

-- ════════════════════════════════════════════════════════════
--  CONFISCATION  (AP 0.7.x inventoryManager)
-- ════════════════════════════════════════════════════════════
local countdowns = {}   -- name -> seconds remaining

local function confiscate(playerName)
    pcall(function()
        chatBox.sendMessageToPlayer(
            "[BASE DEFENSE] Time is up, "..playerName..". Inventory confiscated.",
            playerName, "BASE DEFENSE", "<>")
    end)

    if not invMgr then return end

    -- AP 0.7.x: getItems returns table of {slot, name, count, ...}
    local ok2, items = pcall(function() return invMgr.getItems(playerName) end)
    if not ok2 or not items then
        print("[WARN] Could not get items for "..playerName)
        return
    end

    for _, item in pairs(items) do
        -- removeItem(playerName, slot, count)
        local ok3, moved = pcall(function()
            return invMgr.removeItem(playerName, item.slot, item.count)
        end)
        if not ok3 then
            print("[WARN] Could not remove slot "..tostring(item.slot))
        end
    end

    countdowns[playerName] = nil
    print("[CONFISCATED] "..playerName)
end

-- ════════════════════════════════════════════════════════════
--  MONITOR  (8 blocks wide x 4 blocks tall)
--  At text scale 0.5 this gives ~32 cols x 8 rows
--  Left  half cols 1-16  : Player Tracker  (4 blocks)
--  Right half cols 17-32 : Whitelist Mgr   (4 blocks)
--  Text scale 1.0 on whitelist side → we use 0.5 overall and
--  write short labels to fit.
-- ════════════════════════════════════════════════════════════

-- UI state
local wlPage     = 1
local wlSelected = nil
local WL_ROWS    = 4   -- player rows visible per page

-- Helpers
local function mw(x,y,txt,fg,bg)
    mon.setCursorPos(x,y)
    if fg then mon.setTextColour(fg) end
    if bg then mon.setBackgroundColour(bg) end
    mon.write(txt)
end

local function mfill(y,x1,x2,bg)
    mon.setCursorPos(x1,y)
    mon.setBackgroundColour(bg or colours.black)
    mon.write(string.rep(" ",x2-x1+1))
end

local function lpad(s,n) s=tostring(s); return s:sub(1,n)..string.rep(" ",math.max(0,n-#s)) end
local function rpad(s,n) s=tostring(s); return string.rep(" ",math.max(0,n-#s))..s:sub(1,n) end

-- Build sorted categorised list for whitelist panel
local function categorise()
    local mem,tmp,ban,vis = {},{},{},{}
    for name,p in pairs(players) do
        local lv = p.level or 0
        if     lv >= 1            then table.insert(mem,{name=name,p=p})
        elseif lv<=-1 and lv>=-4 then table.insert(tmp,{name=name,p=p})
        elseif lv==-99            then table.insert(ban,{name=name,p=p})
        else                           table.insert(vis,{name=name,p=p})
        end
    end
    local byLv = function(a,b) return (a.p.level or 0)>(b.p.level or 0) end
    local byNm = function(a,b) return a.name<b.name end
    table.sort(mem,byLv); table.sort(tmp,byLv)
    table.sort(ban,byNm); table.sort(vis,byNm)

    local out={}
    if #mem>0 then table.insert(out,{hdr="MEMBERS"});   for _,v in ipairs(mem) do table.insert(out,v) end end
    if #tmp>0 then table.insert(out,{hdr="TEMPORARY"}); for _,v in ipairs(tmp) do table.insert(out,v) end end
    if #ban>0 then table.insert(out,{hdr="BLACKLIST"}); for _,v in ipairs(ban) do table.insert(out,v) end end
    if #vis>0 then table.insert(out,{hdr="VISITORS"});  for _,v in ipairs(vis) do table.insert(out,v) end end
    return out
end

local function renderMonitor()
    mon.setTextScale(0.5)
    mon.setBackgroundColour(colours.black)
    mon.clear()

    local W,H = mon.getSize()   -- should be ~32 wide, 8 tall
    local mid  = math.floor(W/2)   -- 16
    local rx   = mid+2              -- right panel start

    -- ══ LEFT: Player Tracker ══════════════════════════════
    -- Title row
    mfill(1,1,mid,colours.grey)
    mw(1,1,lpad("Players",mid),colours.yellow,colours.grey)

    -- Column headers row 2
    mfill(2,1,mid,colours.black)
    mw(1, 2, lpad("Name",7),  colours.lightGrey, colours.black)
    mw(9, 2, lpad("Dst",4),   colours.lightGrey, colours.black)
    mw(13,2, lpad("Rank",4),  colours.lightGrey, colours.black)

    -- Divider row 3
    mw(1,3,string.rep("-",mid),colours.grey,colours.black)

    -- Online players sorted by distance
    local online={}
    for name,p in pairs(players) do
        if p.online then table.insert(online,{name=name,p=p}) end
    end
    table.sort(online,function(a,b) return (a.p.lastDist or 9999)<(b.p.lastDist or 9999) end)

    local row=4
    for _,e in ipairs(online) do
        if row>H-1 then break end
        local p   = e.p
        local col = rCol(p.level or 0)
        local dst = p.lastDist and math.floor(p.lastDist).."m" or "?"
        local cd  = countdowns[e.name]
        local cdS = cd and "!"..cd or ""

        mfill(row,1,mid,colours.black)
        mw(1, row, lpad(e.name:sub(1,7),7),       col,           colours.black)
        mw(9, row, lpad(dst,4),                    colours.cyan,  colours.black)
        mw(13,row, lpad(rShort(p.level or 0),3),   col,           colours.black)
        if cdS~="" then
            mw(mid-#cdS+1,row, cdS, colours.red, colours.black)
        end
        row=row+1
    end

    -- Footer
    mfill(H,1,mid,colours.grey)
    mw(1,H,lpad(" "..#online.." online",mid),colours.grey,colours.grey)

    -- Centre divider
    for r=1,H do mw(mid+1,r,"|",colours.grey,colours.black) end

    -- ══ RIGHT: Whitelist Manager ══════════════════════════
    local rw = W - mid - 1  -- usable right width

    -- Title row
    mfill(1,rx,W,colours.grey)
    mw(rx,1,lpad("Whitelist",rw-4),colours.orange,colours.grey)
    -- Page arrows
    mw(W-2,1,"<", colours.white,colours.grey)
    mw(W,  1,">", colours.white,colours.grey)

    local combined   = categorise()
    local totalPages = math.max(1,math.ceil(#combined/WL_ROWS))
    if wlPage>totalPages then wlPage=totalPages end
    local startIdx   = (wlPage-1)*WL_ROWS+1

    local listRow=2
    for i=startIdx, math.min(startIdx+WL_ROWS-1,#combined) do
        if listRow>H-1 then break end
        local entry=combined[i]
        mfill(listRow,rx,W,colours.black)

        if entry.hdr then
            -- Section header
            mw(rx,listRow,lpad(entry.hdr,rw),colours.yellow,colours.black)
        else
            local p   = entry.p
            local lv  = p.level or 0
            local col = rCol(lv)
            local sel = (wlSelected==entry.name)
            local bg  = sel and colours.grey or colours.black
            local onl = p.online and "\7" or " "   -- bullet if online

            mfill(listRow,rx,W,bg)
            mw(rx,   listRow, onl,                         colours.lime, bg)
            mw(rx+1, listRow, lpad(entry.name:sub(1,8),8), col,          bg)
            mw(rx+9, listRow, lpad(rShort(lv),rw-9),       col,          bg)

            -- Temp countdown
            if p.tempEnd then
                local left = math.max(0,math.floor((p.tempEnd-os.epoch("utc"))/1000))
                local ts   = left.."s"
                mw(W-#ts+1,listRow,ts,colours.purple,bg)
            end
        end
        listRow=listRow+1
    end

    -- Action buttons row H
    mfill(H,rx,W,colours.grey)
    if wlSelected then
        -- Buttons: + - T B with colours
        mw(rx,   H, "+", colours.lime,   colours.grey)
        mw(rx+1, H, "-", colours.orange, colours.grey)
        mw(rx+2, H, "T", colours.purple, colours.grey)
        mw(rx+3, H, "B", colours.red,    colours.grey)
        mw(rx+4, H, " ", colours.white,  colours.grey)
        mw(rx+5, H, lpad(wlSelected:sub(1,rw-5), rw-5), colours.white, colours.grey)
    else
        mw(rx,H,lpad(" tap name",rw),colours.grey,colours.grey)
    end
end

-- ════════════════════════════════════════════════════════════
--  TOUCH HANDLER
-- ════════════════════════════════════════════════════════════
local TEMP_DURATION = 3600  -- 1 hour default for temp ranks

local function handleTouch(x,y)
    mon.setTextScale(0.5)
    local W,H = mon.getSize()
    local mid  = math.floor(W/2)
    local rx   = mid+2

    -- Only handle right panel
    if x <= mid then return end

    -- Title row: page arrows
    if y==1 then
        local combined   = categorise()
        local totalPages = math.max(1,math.ceil(#combined/WL_ROWS))
        if x==W-2 then wlPage=math.max(1,wlPage-1)
        elseif x==W then wlPage=math.min(totalPages,wlPage+1)
        end
        renderMonitor(); return
    end

    -- Bottom row: action buttons
    if y==H and wlSelected then
        local p  = getP(wlSelected)
        local lv = p.level or 0
        if x==rx then
            -- Promote (permanent ranks only, max 5)
            if lv>=1 and lv<5 then setLevel(wlSelected,lv+1)
            elseif lv==0      then setLevel(wlSelected,1)
            end
        elseif x==rx+1 then
            -- Demote
            if lv>1 then setLevel(wlSelected,lv-1)
            elseif lv==1 then setLevel(wlSelected,0)
            end
        elseif x==rx+2 then
            -- Cycle temp rank
            local cycle={[0]=-1,[-1]=-2,[-2]=-3,[-3]=-4,[-4]=0}
            local nxt = cycle[lv]
            if nxt then
                if nxt==0 then setLevel(wlSelected,0)
                else            setLevel(wlSelected,nxt,TEMP_DURATION)
                end
            else
                setLevel(wlSelected,-1,TEMP_DURATION)
            end
        elseif x==rx+3 then
            -- Toggle blacklist
            if lv==-99 then setLevel(wlSelected,0)
            else             setLevel(wlSelected,-99)
            end
        end
        renderMonitor(); return
    end

    -- List rows 2..H-1 : select player
    if y>=2 and y<=H-1 then
        local combined = categorise()
        local idx      = (wlPage-1)*WL_ROWS + (y-2) + 1
        if idx>=1 and idx<=#combined then
            local entry=combined[idx]
            if entry.name then
                wlSelected = (wlSelected==entry.name) and nil or entry.name
            end
        end
        renderMonitor()
    end
end

-- ════════════════════════════════════════════════════════════
--  DISCORD
-- ════════════════════════════════════════════════════════════
local function hPost(url,payload,hdrs)
    hdrs=hdrs or {}; hdrs["Content-Type"]="application/json"
    local r=http.post(url,payload,hdrs)
    if not r then return nil,false end
    local b=r.readAll(); local s=r.getResponseCode(); r.close()
    return b,(s>=200 and s<300),s
end

local function hPatch(url,payload,hdrs)
    hdrs=hdrs or {}; hdrs["Content-Type"]="application/json"
    pcall(function() http.request({url=url,body=payload,headers=hdrs,method="PATCH"}) end)
    while true do
        local ev,_,h=os.pullEvent()
        if ev=="http_success" then
            local b=h.readAll(); local s=h.getResponseCode(); h.close()
            return b,(s>=200 and s<300),s
        elseif ev=="http_failure" then return nil,false end
    end
end

local function hGet(url)
    local r=http.get(url)
    if not r then return nil,false end
    local b=r.readAll(); local s=r.getResponseCode(); r.close()
    return b,(s>=200 and s<300)
end

local function buildDiscord()
    local now   = os.date and os.date("!%Y-%m-%d %H:%M:%S UTC") or "?"
    local lines = {}
    local onl,off={},{}
    for name,p in pairs(players) do
        if p.online then table.insert(onl,{name=name,p=p})
        else              table.insert(off,{name=name,p=p}) end
    end
    table.sort(onl,function(a,b) return (a.p.lastDist or 9999)<(b.p.lastDist or 9999) end)
    table.sort(off,function(a,b) return a.name<b.name end)

    table.insert(lines,"**🛡️ Base Defense** — *"..now.."*")
    table.insert(lines,"```")
    if #onl==0 then
        table.insert(lines,"  (no players online)")
    else
        table.insert(lines,string.format("  %-16s %-5s %7s %8s %5s %8s  %s",
            "Player","Rank","Dist","X","Y","Z","Dimension"))
        table.insert(lines,"  "..string.rep("-",68))
        for _,e in ipairs(onl) do
            local p   = e.p
            local dim = (p.lastDim or "?"):gsub("^minecraft:","")
            local dst = p.lastDist and string.format("%.0fm",p.lastDist) or "?"
            local cd  = countdowns[e.name]
            local warn= cd and ("  ⚠ "..cd.."s") or ""
            table.insert(lines,string.format("  %-16s %-5s %7s %8.1f %5.1f %8.1f  %s%s",
                e.name,rShort(p.level or 0),dst,
                p.lastX or 0,p.lastY or 0,p.lastZ or 0,dim,warn))
        end
    end
    table.insert(lines,"```")

    -- Offline non-safe only
    local offBad={}
    for _,e in ipairs(off) do
        if not isSafe(e.p.level or 0) then table.insert(offBad,e) end
    end
    if #offBad>0 then
        table.insert(lines,"**📴 Offline visitors/blacklisted**")
        table.insert(lines,"```diff")
        table.insert(lines,string.format("  %-16s %-5s %8s %5s %8s  %-8s  %s",
            "Player","Rank","X","Y","Z","LastSeen","Dimension"))
        table.insert(lines,"  "..string.rep("-",68))
        for _,e in ipairs(offBad) do
            local p=e.p
            local dim=(p.lastDim or "?"):gsub("^minecraft:","")
            table.insert(lines,string.format("- %-16s %-5s %8.1f %5.1f %8.1f  %-8s  %s",
                e.name,rShort(p.level or 0),
                p.lastX or 0,p.lastY or 0,p.lastZ or 0,
                p.lastSeen or "?",dim))
        end
        table.insert(lines,"```")
    end

    local tot=0; for _ in pairs(players) do tot=tot+1 end
    table.insert(lines,string.format("-# %d online · %d tracked · Base @ %d,%d,%d",
        #onl,tot,dPos.x,dPos.y,dPos.z))
    return table.concat(lines,"\n")
end

local function loadMsgId()
    if not fs.exists(MSG_ID_FILE) then return nil end
    local f=fs.open(MSG_ID_FILE,"r"); local id=f.readAll():gsub("%s",""); f.close()
    return id~="" and id or nil
end

local function saveMsgId(id)
    local f=fs.open(MSG_ID_FILE,"w"); f.write(id); f.close()
end

local function sendDiscord(content)
    local b,ok2=hPost(WEBHOOK_URL.."?wait=true",
        textutils.serialiseJSON({username=BOT_USERNAME,content=content}))
    if not ok2 then return nil end
    local m=textutils.unserialiseJSON(b)
    return m and m.id or nil
end

local function editDiscord(id,content)
    hPatch(WEBHOOK_URL.."/messages/"..id,
        textutils.serialiseJSON({content=content}))
end

local function parseOffline(content)
    if not content then return end
    local inDiff,count=false,0
    for line in (content.."\n"):gmatch("([^\n]*)\n") do
        if line:match("^```diff") then inDiff=true
        elseif inDiff and line:match("^```") then inDiff=false
        elseif inDiff then
            local rest=line:match("^%- (.+)$")
            if rest and not rest:match("^%-%-") and not rest:match("^Player") then
                local name,x,y,z,seen,dim=
                    rest:match("^(%S+)%s+%S+%s+(%-?%d+%.%d+)%s+(%-?%d+%.%d+)%s+(%-?%d+%.%d+)%s+(%S+)%s+(.+)$")
                if name then
                    local p=getP(name)
                    p.lastX=tonumber(x) or p.lastX
                    p.lastY=tonumber(y) or p.lastY
                    p.lastZ=tonumber(z) or p.lastZ
                    p.lastSeen=seen or p.lastSeen
                    p.lastDim=dim and dim:gsub("%s+$","") or p.lastDim
                    p.online=false
                    count=count+1
                end
            end
        end
    end
    if count>0 then saveDB(); print("Restored "..count.." offline player(s).") end
end

-- ════════════════════════════════════════════════════════════
--  STARTUP
-- ════════════════════════════════════════════════════════════
loadDB()
print("=== Base Defense Starting ===")

local msgId=loadMsgId()
if msgId then
    print("Resuming message "..msgId)
    local b,ok2=hGet(WEBHOOK_URL.."/messages/"..msgId)
    if ok2 then
        local m=textutils.unserialiseJSON(b)
        if m then parseOffline(m.content) end
    else
        print("[WARN] Could not fetch old message, starting fresh.")
        msgId=nil
    end
end

renderMonitor()

if msgId then
    editDiscord(msgId,buildDiscord())
    print("Resumed Discord message.")
else
    msgId=sendDiscord(buildDiscord())
    if msgId then saveMsgId(msgId); print("New Discord message: "..msgId) end
end

print("Running — Ctrl+T to stop.")

-- ════════════════════════════════════════════════════════════
--  MAIN EVENT LOOP
-- ════════════════════════════════════════════════════════════
local tickT    = os.startTimer(UPDATE_INTERVAL)
local discordT = os.startTimer(5)
local warnTick = 0   -- counts 0.5s ticks; warn every 2nd tick = every 1s

while true do
    local ev={os.pullEvent()}

    -- ── Tick ──────────────────────────────────────────────
    if ev[1]=="timer" and ev[2]==tickT then
        tickT  = os.startTimer(UPDATE_INTERVAL)
        warnTick = warnTick + 1
        local doWarn = (warnTick % 2 == 0)  -- every 1 second

        checkExpiry()

        -- Detect players
        local names={}
        local ok2,res=pcall(function() return detector.getOnlinePlayers() end)
        if ok2 and res then names=res
        else
            local r=detector.getPlayersInRange(100000)
            if r then names=r end
        end

        local detected={}
        for _,name in ipairs(names) do
            local pos=detector.getPlayerPos(name)
            if pos then detected[name]=pos end
        end

        -- Mark gone players offline
        for name,p in pairs(players) do
            if p.online and not detected[name] then
                p.online=false
                p.lastSeen=os.date and os.date("!%H:%M:%S") or "?"
                countdowns[name]=nil
                saveDB()
            end
        end

        -- Update detected players
        local changed=false
        for name,pos in pairs(detected) do
            local p=getP(name)
            local d=dist3(pos.x,pos.y,pos.z)
            p.online=true
            p.lastX=pos.x; p.lastY=pos.y; p.lastZ=pos.z
            p.lastDim=pos.dimension; p.lastDist=d
            p.lastSeen=os.date and os.date("!%H:%M:%S") or "?"
            changed=true

            local safe=isSafe(p.level or 0)

            if not safe and d<=BASE_RADIUS then
                -- Initialise countdown
                if countdowns[name]==nil then
                    countdowns[name]=WARNING_SECONDS
                end

                if countdowns[name]>0 then
                    if doWarn then
                        -- Decrement and warn
                        countdowns[name]=countdowns[name]-1
                        local msg=string.format(
                            "WARNING: You are within %dm of the Military Base. Turn around within %d seconds or your inventory will be taken.",
                            BASE_RADIUS, countdowns[name])
                        pcall(function()
                            chatBox.sendMessageToPlayer(msg, name, "BASE DEFENSE", "<>")
                        end)
                    end
                else
                    -- Countdown hit 0
                    confiscate(name)
                end
            else
                -- Safe or out of range
                if not safe and d>BASE_RADIUS then
                    countdowns[name]=nil  -- reset for next entry
                end
                if safe then countdowns[name]=nil end
            end
        end

        if changed then saveDB() end
        renderMonitor()

    -- ── Discord update every 5s ────────────────────────────
    elseif ev[1]=="timer" and ev[2]==discordT then
        discordT=os.startTimer(5)
        pcall(function() editDiscord(msgId,buildDiscord()) end)

    -- ── Monitor touch ──────────────────────────────────────
    elseif ev[1]=="monitor_touch" then
        handleTouch(ev[3],ev[4])
    end
end
