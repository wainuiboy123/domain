-- ============================================================
--  Base Defense & Whitelist System
--  CC: Tweaked + Advanced Peripherals 0.7.x
--
--  Peripherals (all directly touching computer):
--    • player_detector
--    • chat_box
--    • monitor  (8 wide x 4 tall blocks, text scale 0.5)
--    • inventory_manager
--
--  Monitor layout (scale 0.5 → ~40 cols x 8 rows):
--    Cols 1-20  : Player Tracker  (left, unchanged from before)
--    Col  21    : divider
--    Cols 22-40 : Whitelist Manager (right)
--
--  Whitelist right panel layout:
--    Row 1      : title + page arrows
--    Rows 2-5   : player list (4 visible rows)
--    Row 6      : [PROMOTE +] [DEMOTE -]
--    Row 7      : [TEMP >>>]  [BLACKLIST]
--    Row 8      : selected player name / status
-- ============================================================

local WEBHOOK_URL     = "https://discord.com/api/webhooks/1518852807694880818/tJ4d23Ba01Mc1ZekjK5yhSiLykKoKofQ2EFskPzR2rT15U8nPDhYLTNUfLm5u6a2othY"
local BOT_USERNAME    = "Base Defense"
local UPDATE_INTERVAL = 0.5
local BASE_RADIUS     = 200
local WARNING_SECONDS = 30
local PLAYER_FILE     = "players.json"
local MSG_ID_FILE     = "message_id.txt"
local TEMP_DURATION   = 3600   -- default temp rank duration (seconds)

-- ── Ranks ────────────────────────────────────────────────────
local RANKS = {
    [5]   = { name="Command",          short="CMD", col=colours.yellow,    safe=true  },
    [4]   = { name="Senior Officer",   short="SNR", col=colours.lime,      safe=true  },
    [3]   = { name="Officer",          short="OFF", col=colours.green,     safe=true  },
    [2]   = { name="Member",           short="MBR", col=colours.cyan,      safe=true  },
    [1]   = { name="Recruit",          short="RCT", col=colours.lightBlue, safe=true  },
    [0]   = { name="Visitor",          short="VIS", col=colours.white,     safe=false },
    [-1]  = { name="Temp Recruit",     short="TRC", col=colours.purple,    safe=true  },
    [-2]  = { name="Temp Member",      short="TMB", col=colours.purple,    safe=true  },
    [-3]  = { name="Temp Officer",     short="TOF", col=colours.purple,    safe=true  },
    [-4]  = { name="Temp Sr Officer",  short="TSN", col=colours.purple,    safe=true  },
    [-99] = { name="Blacklisted",      short="BAN", col=colours.red,       safe=false },
}

local function isSafe(lv) local r=RANKS[lv]; return r and r.safe or false end
local function rShort(lv) local r=RANKS[lv]; return r and r.short or "VIS" end
local function rCol(lv)   local r=RANKS[lv]; return r and r.col   or colours.white end
local function rName(lv)  local r=RANKS[lv]; return r and r.name  or "Visitor" end

-- ── Peripherals ──────────────────────────────────────────────
local detector = peripheral.find("player_detector")
local chatBox  = peripheral.find("chat_box")
local mon      = peripheral.find("monitor")
local invMgr   = peripheral.find("inventory_manager")

if not detector then error("No player_detector found!", 0) end
if not chatBox  then error("No chat_box found!", 0) end
if not mon      then error("No monitor found!", 0) end
if not invMgr   then print("[WARN] No inventory_manager — confiscation disabled") end

local detName = peripheral.getName(detector)

-- ── Detector position ────────────────────────────────────────
local dPos = vector.new(0,0,0)
do
    local ok,bp = pcall(function() return peripheral.call(detName,"getBlockPos") end)
    if ok and bp then dPos = vector.new(bp.x,bp.y,bp.z) end
end

local function dist3(x,y,z)
    return math.sqrt((x-dPos.x)^2+(y-dPos.y)^2+(z-dPos.z)^2)
end

-- ════════════════════════════════════════════════════════════
--  DATABASE
--  players[name] = {
--    level   : number  (rank level)
--    tempEnd : number|nil  (os.epoch ms when temp expires)
--    online  : bool
--    lastX/Y/Z/Dim/Dist/Seen : position data
--  }
-- ════════════════════════════════════════════════════════════
local players = {}

local function saveDB()
    local f=fs.open(PLAYER_FILE,"w")
    f.write(textutils.serialiseJSON(players)); f.close()
end

local function loadDB()
    if not fs.exists(PLAYER_FILE) then return end
    local f=fs.open(PLAYER_FILE,"r")
    local raw=f.readAll(); f.close()
    local ok,d=pcall(textutils.unserialiseJSON,raw)
    if ok and type(d)=="table" then players=d end
end

local function getP(name)
    if not players[name] then players[name]={level=0,online=false} end
    return players[name]
end

local function setLevel(name,lv,tempSecs)
    local p=getP(name)
    p.level=lv
    p.tempEnd=tempSecs and (os.epoch("utc")+tempSecs*1000) or nil
    saveDB()
end

local function checkExpiry()
    local now=os.epoch("utc")
    for name,p in pairs(players) do
        if p.tempEnd and now>=p.tempEnd then
            p.level=0; p.tempEnd=nil; saveDB()
        end
    end
end

-- ════════════════════════════════════════════════════════════
--  CONFISCATION  (AP 0.7.x)
-- ════════════════════════════════════════════════════════════
local countdowns = {}

local function confiscate(playerName)
    pcall(function()
        chatBox.sendMessageToPlayer(
            "[BASE DEFENSE] Time is up, "..playerName..
            ". Your inventory has been confiscated.",
            playerName,"BASE DEFENSE","<>")
    end)

    if not invMgr then
        print("[INFO] No inventory_manager — cannot confiscate "..playerName)
        countdowns[playerName]=nil
        return
    end

    local ok2,items=pcall(function() return invMgr.getItems(playerName) end)
    if not ok2 or not items then
        print("[WARN] getItems failed for "..playerName)
        countdowns[playerName]=nil
        return
    end

    for _,item in pairs(items) do
        pcall(function()
            invMgr.removeItem(playerName, item.slot, item.count)
        end)
    end

    countdowns[playerName]=nil
    print("[CONFISCATED] "..playerName)
end

-- ════════════════════════════════════════════════════════════
--  MONITOR RENDERING
--
--  Scale 0.5 on an 8×4 block monitor → ~40 wide, 8 tall
--  Left  (cols 1-19)  : tracker
--  Col 20             : divider
--  Right (cols 21-40) : whitelist  (20 chars wide)
-- ════════════════════════════════════════════════════════════

-- UI state
local wlPage     = 1
local wlSelected = nil
local WL_LIST_ROWS = 4  -- rows 2-5 are the scrollable player list

-- Zone definitions for touch detection (set during render)
-- Each entry: { x1,y1,x2,y2, action=string }
local touchZones = {}

local function addZone(x1,y1,x2,y2,action)
    table.insert(touchZones,{x1=x1,y1=y1,x2=x2,y2=y2,action=action})
end

local function clearZones() touchZones={} end

-- Helpers
local function mw(x,y,txt,fg,bg)
    mon.setCursorPos(x,y)
    if fg then mon.setTextColour(fg) end
    if bg then mon.setBackgroundColour(bg) end
    mon.write(txt)
end

local function mfill(y,x1,x2,bg,fg,txt)
    mon.setCursorPos(x1,y)
    mon.setBackgroundColour(bg or colours.black)
    if fg then mon.setTextColour(fg) end
    local s=string.rep(" ",x2-x1+1)
    if txt then
        -- centre text
        local pad=math.max(0,math.floor((x2-x1+1-#txt)/2))
        s=string.rep(" ",pad)..txt..string.rep(" ",x2-x1+1-pad-#txt)
    end
    mon.write(s)
end

local function lp(s,n) s=tostring(s); return (s..string.rep(" ",n)):sub(1,n) end
local function rp(s,n) s=tostring(s); return (string.rep(" ",n)..s):sub(-n) end

-- Build categorised list (everyone ever seen)
local function categorise()
    local mem,tmp,ban,vis={},{},{},{}
    for name,p in pairs(players) do
        local lv=p.level or 0
        if     lv>=1 and lv<=5   then table.insert(mem,{name=name,p=p})
        elseif lv<=-1 and lv>=-4 then table.insert(tmp,{name=name,p=p})
        elseif lv==-99            then table.insert(ban,{name=name,p=p})
        else                           table.insert(vis,{name=name,p=p})
        end
    end
    local byLv=function(a,b) return (a.p.level or 0)>(b.p.level or 0) end
    local byNm=function(a,b) return a.name<b.name end
    table.sort(mem,byLv); table.sort(tmp,byLv)
    table.sort(ban,byNm); table.sort(vis,byNm)

    local out={}
    if #mem>0 then
        table.insert(out,{hdr="--- MEMBERS ---"})
        for _,v in ipairs(mem) do table.insert(out,v) end
    end
    if #tmp>0 then
        table.insert(out,{hdr="-- TEMPORARY --"})
        for _,v in ipairs(tmp) do table.insert(out,v) end
    end
    if #ban>0 then
        table.insert(out,{hdr="-- BLACKLIST ---"})
        for _,v in ipairs(ban) do table.insert(out,v) end
    end
    if #vis>0 then
        table.insert(out,{hdr="--- VISITORS ---"})
        for _,v in ipairs(vis) do table.insert(out,v) end
    end
    return out
end

local function renderMonitor()
    mon.setTextScale(0.5)
    mon.setBackgroundColour(colours.black)
    mon.clear()
    clearZones()

    local W,H=mon.getSize()
    -- Expect W≈40, H≈8 for an 8-wide 4-tall monitor at scale 0.5
    local mid=20          -- left panel ends col 20
    local div=mid+1       -- divider col 21
    local rx=mid+2        -- right panel starts col 22
    local rw=W-rx+1       -- right panel width

    -- ════ LEFT: Player Tracker (unchanged from original) ════

    -- Title bar row 1
    mfill(1,1,mid,colours.grey)
    mw(1,1,lp(" Player Tracker",mid),colours.yellow,colours.grey)

    -- Column headers row 2
    mw(1, 2,lp("Name",8),   colours.lightGrey,colours.black)
    mw(9, 2,lp("Dist",5),   colours.lightGrey,colours.black)
    mw(14,2,lp("Rank",4),   colours.lightGrey,colours.black)
    mw(18,2,lp("CD",3),     colours.lightGrey,colours.black)

    -- Divider row 3
    mw(1,3,string.rep("-",mid),colours.grey,colours.black)

    -- Online players sorted by distance
    local online={}
    for name,p in pairs(players) do
        if p.online then table.insert(online,{name=name,p=p}) end
    end
    table.sort(online,function(a,b)
        return (a.p.lastDist or 9999)<(b.p.lastDist or 9999)
    end)

    local row=4
    for i,e in ipairs(online) do
        if row>H-1 then break end
        local p   = e.p
        local lv  = p.level or 0
        local col = rCol(lv)
        -- rank colour: top 3 by distance get special colours
        if     i==1 then col=colours.yellow
        elseif i==2 then col=colours.white
        elseif i==3 then col=colours.orange
        end
        -- but keep rank colour if they have one
        col = rCol(lv)

        local dst = p.lastDist and (math.floor(p.lastDist).."m") or "?"
        local cd  = countdowns[e.name]
        local cdS = cd and tostring(cd) or ""

        mfill(row,1,mid,colours.black)
        mw(1, row,lp(e.name:sub(1,7),8),  col,           colours.black)
        mw(9, row,lp(dst,5),               colours.cyan,  colours.black)
        mw(14,row,lp(rShort(lv),4),        col,           colours.black)
        if cdS~="" then
            mw(18,row,lp(cdS.."s",3),      colours.red,   colours.black)
        end
        row=row+1
    end

    -- Footer row H (left side)
    mfill(H,1,mid,colours.grey)
    mw(1,H,lp(" "..#online.." online",mid),colours.grey,colours.grey)

    -- ════ DIVIDER ════
    for r=1,H do mw(div,r,"|",colours.grey,colours.black) end

    -- ════ RIGHT: Whitelist Manager ════

    -- Row 1: Title + page nav
    mfill(1,rx,W,colours.grey)
    mw(rx,1,lp(" Whitelist",rw-4),colours.orange,colours.grey)
    -- Page arrows as visible buttons
    mw(W-2,1,"[<]",colours.white,colours.grey)
    mw(W,  1,">",  colours.white,colours.grey)
    addZone(W-2,1,W-1,1,"page_prev")
    addZone(W,  1,W,  1,"page_next")

    -- Rows 2-5: Player list
    local combined   = categorise()
    local totalPages = math.max(1,math.ceil(#combined/WL_LIST_ROWS))
    if wlPage>totalPages then wlPage=totalPages end
    local startIdx   = (wlPage-1)*WL_LIST_ROWS+1

    for i=0,WL_LIST_ROWS-1 do
        local listRow = 2+i
        local idx     = startIdx+i
        mfill(listRow,rx,W,colours.black)

        if idx<=#combined then
            local entry=combined[idx]
            if entry.hdr then
                -- Section header
                mw(rx,listRow,lp(entry.hdr,rw),colours.yellow,colours.black)
            else
                local p   = entry.p
                local lv  = p.level or 0
                local col = rCol(lv)
                local sel = (wlSelected==entry.name)
                local bg  = sel and colours.grey or colours.black
                local dot = p.online and "\7" or " "

                mfill(listRow,rx,W,bg)
                mw(rx,   listRow, dot,                          colours.lime,  bg)
                mw(rx+1, listRow, lp(entry.name:sub(1,9),9),   col,           bg)
                mw(rx+10,listRow, lp(rShort(lv),3),             col,           bg)

                -- Temp timer
                if p.tempEnd then
                    local left=math.max(0,math.floor((p.tempEnd-os.epoch("utc"))/1000))
                    local m2=math.floor(left/60)
                    local ts= m2>0 and (m2.."m") or (left.."s")
                    mw(W-#ts,listRow,ts,colours.purple,bg)
                end

                addZone(rx,listRow,W,listRow,"select:"..entry.name)
            end
        end
    end

    -- ── Big action buttons rows 6-7 ──
    -- Row 6: [  PROMOTE +  ] [  DEMOTE -  ]
    local btnW = math.floor(rw/2)
    local b1x  = rx
    local b2x  = rx + btnW

    -- PROMOTE button
    mfill(6, b1x, b2x-1, colours.green)
    mw(b1x, 6, lp("", math.floor((btnW-9)/2)), colours.green, colours.green)
    local promLabel = " PROMOTE +"
    mw(b1x, 6, lp(promLabel, btnW-1), colours.white, colours.green)
    addZone(b1x, 6, b2x-1, 6, "promote")

    -- DEMOTE button
    mfill(6, b2x, W, colours.orange)
    mw(b2x, 6, lp(" DEMOTE -", W-b2x+1), colours.white, colours.orange)
    addZone(b2x, 6, W, 6, "demote")

    -- Row 7: [  TEMP >>>  ] [ BLACKLIST  ]
    -- TEMP button
    mfill(7, b1x, b2x-1, colours.purple)
    mw(b1x, 7, lp(" TEMP >>>", btnW-1), colours.white, colours.purple)
    addZone(b1x, 7, b2x-1, 7, "temp")

    -- BLACKLIST button
    mfill(7, b2x, W, colours.red)
    mw(b2x, 7, lp(" BLACKLIST", W-b2x+1), colours.white, colours.red)
    addZone(b2x, 7, W, 7, "blacklist")

    -- Row 8: Selected player info
    mfill(8, rx, W, colours.grey)
    if wlSelected then
        local p  = getP(wlSelected)
        local lv = p.level or 0
        local info= lp(" "..wlSelected:sub(1,9).." | "..rName(lv):sub(1,8), rw)
        mw(rx, 8, info, rCol(lv), colours.grey)
    else
        mw(rx, 8, lp(" Tap a name above", rw), colours.grey, colours.grey)
    end

    -- Page indicator
    if totalPages>1 then
        local pg=tostring(wlPage).."/"..tostring(totalPages)
        mw(W-#pg+1,8,pg,colours.lightGrey,colours.grey)
    end
end

-- ════════════════════════════════════════════════════════════
--  TOUCH HANDLER
-- ════════════════════════════════════════════════════════════
local function handleTouch(tx,ty)
    for _,zone in ipairs(touchZones) do
        if tx>=zone.x1 and tx<=zone.x2 and ty>=zone.y1 and ty<=zone.y2 then
            local act=zone.action

            if act=="page_prev" then
                wlPage=math.max(1,wlPage-1)

            elseif act=="page_next" then
                local combined=categorise()
                local tot=math.max(1,math.ceil(#combined/WL_LIST_ROWS))
                wlPage=math.min(tot,wlPage+1)

            elseif act:sub(1,7)=="select:" then
                local name=act:sub(8)
                wlSelected=(wlSelected==name) and nil or name

            elseif act=="promote" and wlSelected then
                local p=getP(wlSelected); local lv=p.level or 0
                if lv<=-1 and lv>=-4 then
                    -- clear temp, set visitor
                    setLevel(wlSelected,0)
                elseif lv>=0 and lv<5 then
                    setLevel(wlSelected,lv+1)
                end

            elseif act=="demote" and wlSelected then
                local p=getP(wlSelected); local lv=p.level or 0
                if lv>0 then
                    setLevel(wlSelected,lv-1)
                elseif lv==0 then
                    -- already visitor, do nothing
                end

            elseif act=="temp" and wlSelected then
                -- Cycle: 0→-1→-2→-3→-4→0
                local p=getP(wlSelected); local lv=p.level or 0
                local cycle={[0]=-1,[-1]=-2,[-2]=-3,[-3]=-4,[-4]=0}
                local nxt=cycle[lv]
                if nxt then
                    if nxt==0 then setLevel(wlSelected,0)
                    else            setLevel(wlSelected,nxt,TEMP_DURATION)
                    end
                else
                    setLevel(wlSelected,-1,TEMP_DURATION)
                end

            elseif act=="blacklist" and wlSelected then
                local p=getP(wlSelected); local lv=p.level or 0
                if lv==-99 then setLevel(wlSelected,0)
                else             setLevel(wlSelected,-99)
                end
            end

            renderMonitor()
            return
        end
    end
end

-- ════════════════════════════════════════════════════════════
--  DISCORD
-- ════════════════════════════════════════════════════════════
local function hPost(url,body)
    local r=http.post(url,body,{["Content-Type"]="application/json"})
    if not r then return nil,false end
    local b=r.readAll(); local s=r.getResponseCode(); r.close()
    return b,(s>=200 and s<300),s
end

local function hPatch(url,body)
    pcall(function()
        http.request({url=url,body=body,
            headers={["Content-Type"]="application/json"},method="PATCH"})
    end)
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
    local now=os.date and os.date("!%Y-%m-%d %H:%M:%S UTC") or "?"
    local lines={}
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
            local p=e.p
            local dim=(p.lastDim or "?"):gsub("^minecraft:","")
            local dst=p.lastDist and string.format("%.0fm",p.lastDist) or "?"
            local cd=countdowns[e.name]
            local warn=cd and ("  ⚠ "..cd.."s") or ""
            table.insert(lines,string.format("  %-16s %-5s %7s %8.1f %5.1f %8.1f  %s%s",
                e.name,rShort(p.level or 0),dst,
                p.lastX or 0,p.lastY or 0,p.lastZ or 0,dim,warn))
        end
    end
    table.insert(lines,"```")

    -- Offline non-safe
    local offBad={}
    for _,e in ipairs(off) do
        if not isSafe(e.p.level or 0) then table.insert(offBad,e) end
    end
    if #offBad>0 then
        table.insert(lines,"**📴 Offline visitors/blacklisted — last known**")
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
    table.insert(lines,string.format(
        "-# %d online · %d total tracked · Base @ %d,%d,%d",
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
    if count>0 then saveDB(); print("Restored "..count.." player(s) from Discord.") end
end

-- ════════════════════════════════════════════════════════════
--  STARTUP
-- ════════════════════════════════════════════════════════════
loadDB()
print("=== Base Defense Starting ===")
print("Detector : "..detName)
print("Monitor  : "..peripheral.getName(mon))
if invMgr then print("Inv Mgr  : "..peripheral.getName(invMgr)) end

local msgId=loadMsgId()
if msgId then
    print("Resuming Discord message: "..msgId)
    local b,ok2=hGet(WEBHOOK_URL.."/messages/"..msgId)
    if ok2 then
        local m=textutils.unserialiseJSON(b)
        if m then parseOffline(m.content) end
    else
        print("[WARN] Could not fetch old message — starting fresh.")
        msgId=nil
    end
end

renderMonitor()

if msgId then
    editDiscord(msgId,buildDiscord())
else
    msgId=sendDiscord(buildDiscord())
    if msgId then saveMsgId(msgId); print("New message ID: "..msgId) end
end

print("Running — Ctrl+T to stop.")

-- ════════════════════════════════════════════════════════════
--  MAIN LOOP
-- ════════════════════════════════════════════════════════════
local tickT    = os.startTimer(UPDATE_INTERVAL)
local discordT = os.startTimer(5)
local warnTick = 0

while true do
    local ev={os.pullEvent()}

    -- ── 0.5s tick ─────────────────────────────────────────
    if ev[1]=="timer" and ev[2]==tickT then
        tickT    = os.startTimer(UPDATE_INTERVAL)
        warnTick = warnTick+1
        local doWarn = (warnTick%2==0)  -- every 1 second

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

        -- Players that vanished → mark offline
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

            -- First time we've seen this player → add to DB as visitor
            if not p.level then p.level=0 end

            p.online=true
            p.lastX=pos.x; p.lastY=pos.y; p.lastZ=pos.z
            p.lastDim=pos.dimension; p.lastDist=d
            p.lastSeen=os.date and os.date("!%H:%M:%S") or "?"
            changed=true

            local safe=isSafe(p.level or 0)

            if not safe and d<=BASE_RADIUS then
                if countdowns[name]==nil then
                    countdowns[name]=WARNING_SECONDS
                end

                if countdowns[name]>0 then
                    if doWarn then
                        countdowns[name]=countdowns[name]-1
                        local msg=string.format(
                            "⚠ YOU ARE WITHIN %dm OF THE MILITARY BASE. TURN AROUND WITHIN %d SECONDS TO AVOID YOUR INVENTORY BEING TAKEN.",
                            BASE_RADIUS, countdowns[name])
                        pcall(function()
                            chatBox.sendMessageToPlayer(msg,name,"BASE DEFENSE","<>")
                        end)
                    end
                else
                    confiscate(name)
                end
            else
                if not safe and d>BASE_RADIUS then countdowns[name]=nil end
                if safe then countdowns[name]=nil end
            end
        end

        if changed then saveDB() end
        renderMonitor()

    -- ── Discord every 5s ───────────────────────────────────
    elseif ev[1]=="timer" and ev[2]==discordT then
        discordT=os.startTimer(5)
        pcall(function() editDiscord(msgId,buildDiscord()) end)

    -- ── Monitor touch ──────────────────────────────────────
    elseif ev[1]=="monitor_touch" then
        handleTouch(ev[3],ev[4])
    end
end
