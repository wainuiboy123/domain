--[[
    HOTSPOT HEATMAP
    ---------------
    Tracks tracked players' positions using the Player Detector peripheral
    (type "playerDetector"), polling as fast as practically possible while
    they're online, and displays a live, connected trail/heatmap on a
    monitor named "monitor" using sub-pixel rendering (~6x more pixels
    than the monitor's character grid).

    REQUIRES: pixelbox_lite.lua in the same folder as this script.

    Grid layout:
      - Bottom-left pixel  = the player's most -X/-Z position seen this login
      - Top-right pixel    = the player's most +X/+Z position seen this login
      - Color goes from blue (rarely visited) to red (frequently visited)
      - The bounding box (and the whole map) rescales live as the player
        wanders further out, so it always fits their full travelled area
      - Tracking resets fresh every time the player logs back in

    Click (right-click / "use") any spot on the monitor to print the
    approximate real-world coordinates of the hottest pixel under that
    click to this computer's terminal. (Minecraft only reports which
    character cell was touched, not the exact sub-pixel - so we report
    whichever of that cell's sub-pixels was visited most.)

    COMMANDS:
      add <username>        - start tracking a player
      remove <username>     - stop tracking a player
      list                  - show tracked players
      watch <username>      - show this player's heatmap on the monitor
      status                - show who's online right now
      reset <username>      - wipe this player's current session data
      exit                  - quit
]]

-- ===================== CONFIG =====================
local POLL_INTERVAL = 0.05  -- seconds between position checks (~1 game tick,
                             -- the fastest a CC:Tweaked timer can fire)
local MAX_SAMPLES   = 4000  -- cap on stored points per player session, so
                             -- fast polling + long sessions can't slowly
                             -- balloon memory/render time into "too long
                             -- without yielding" errors. Oldest points are
                             -- dropped first; raise this if your server
                             -- handles it fine.
local LINE_STEP      = 1    -- blocks between interpolated points, so fast
                             -- movement still draws as a continuous line
local LINE_MAX_GAP   = 200  -- don't connect jumps bigger than this (login,
                             -- teleport, dimension change, etc.)

local PLAYERS_FILE  = "tracked_players.txt"

local GRADIENT = {
    colors.blue, colors.cyan, colors.lightBlue, colors.green,
    colors.lime, colors.yellow, colors.orange, colors.red
}
local EMPTY_COLOR = colors.black

-- ===================== LIBRARIES =====================
local pixelbox = dofile("pixelbox_lite.lua")

-- ===================== PERIPHERALS =====================
-- Per Advanced Peripherals docs: use peripheral.find("playerDetector") to
-- get a callable handle (the playerJoin/playerLeave EVENTS fire without
-- needing find/wrap, but calling getPlayerPos requires this).
local pd = peripheral.find("playerDetector")
if not pd then
    error("No player_detector found. Check it's connected to this computer.")
end

local mon = peripheral.wrap("monitor")
if not mon then
    error("No peripheral named 'monitor' found. Check it's connected and named correctly.")
end

mon.setTextScale(0.5) -- smallest scale = max character resolution, which
                       -- also maximizes the sub-pixel resolution below

local box = pixelbox.new(mon)
local GRID_W, GRID_H = box.width, box.height -- sub-pixel canvas size (~6x
                                              -- the character grid)

-- ===================== STATE =====================
local players = {}         -- { [name] = true }
local sessions = {}        -- sessions[name] = { active, minX,maxX,minZ,maxZ, samples = {} }
local watchedPlayer = nil
local lastBounds = nil     -- bounding box used for the last render
local lastGrid = nil       -- grid[col][row] = count, from the last render
local lastMaxCount = 0

-- ===================== PERSISTENCE =====================
local function loadPlayers()
    if not fs.exists(PLAYERS_FILE) then return {} end
    local f = fs.open(PLAYERS_FILE, "r")
    local contents = f.readAll()
    f.close()
    local ok, result = pcall(textutils.unserialize, contents)
    if ok and result then return result end
    return {}
end

local function savePlayers()
    local f = fs.open(PLAYERS_FILE, "w")
    f.write(textutils.serialize(players))
    f.close()
end

-- ===================== HELPERS =====================
local function tryGetPos(name)
    local ok, result = pcall(function() return pd.getPlayerPos(name) end)
    if not ok or not result then return nil end
    if type(result) == "table" and result.x then
        return result.x, result.y, result.z, result.dimension or "unknown"
    end
    return nil
end

local function newSession()
    return {
        active = false,
        minX = nil, maxX = nil, minZ = nil, maxZ = nil,
        samples = {},   -- raw {x=, z=} points; grid is rebuilt from these
                        -- on every draw, so a growing bounding box rescales
                        -- ALL prior points instead of leaving them stuck
                        -- at their old position.
    }
end

local function ensureSession(name)
    if not sessions[name] then sessions[name] = newSession() end
    return sessions[name]
end

-- Push one raw point into a session, updating bounds and the sample cap.
local function addPoint(s, x, z)
    if not s.minX then
        s.minX, s.maxX, s.minZ, s.maxZ = x, x, z, z
    else
        if x < s.minX then s.minX = x end
        if x > s.maxX then s.maxX = x end
        if z < s.minZ then s.minZ = z end
        if z > s.maxZ then s.maxZ = z end
    end
    table.insert(s.samples, { x = x, z = z })
    if #s.samples > MAX_SAMPLES then
        table.remove(s.samples, 1)
    end
end

-- Record a new position, interpolating from the last one so the trail
-- reads as a continuous connected line rather than scattered dots.
local function recordSample(name, x, z)
    local s = ensureSession(name)

    if s.lastX and s.lastZ then
        local dx, dz = x - s.lastX, z - s.lastZ
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist > 0 and dist <= LINE_MAX_GAP then
            local steps = math.floor(dist / LINE_STEP)
            for i = 1, steps - 1 do
                local t = i / steps
                addPoint(s, s.lastX + dx * t, s.lastZ + dz * t)
            end
        end
    end

    addPoint(s, x, z)
    s.lastX, s.lastZ = x, z
end

-- Map a world coordinate to a sub-pixel cell using a session's CURRENT bounds.
local function worldToCell(s, x, z)
    local col, row
    if s.maxX == s.minX then
        col = math.ceil(GRID_W / 2)
    else
        col = 1 + math.floor((x - s.minX) / (s.maxX - s.minX) * (GRID_W - 1) + 0.5)
    end
    if s.maxZ == s.minZ then
        row = math.ceil(GRID_H / 2)
    else
        -- flip Z so max Z (top-right requirement) ends up at the top row
        row = 1 + math.floor((s.maxZ - z) / (s.maxZ - s.minZ) * (GRID_H - 1) + 0.5)
    end
    col = math.max(1, math.min(GRID_W, col))
    row = math.max(1, math.min(GRID_H, row))
    return col, row
end

-- Rebuild the full grid + max count from raw samples, using the
-- session's current bounds. This is what makes the heatmap rescale
-- itself whenever a player travels outside the previously-seen area.
local function rebuildGrid(name)
    local s = sessions[name]
    if not s or not s.minX then return nil, 0 end

    local grid = {}
    local maxCount = 0
    for _, p in ipairs(s.samples) do
        local col, row = worldToCell(s, p.x, p.z)
        grid[col] = grid[col] or {}
        grid[col][row] = (grid[col][row] or 0) + 1
        if grid[col][row] > maxCount then maxCount = grid[col][row] end
    end
    return grid, maxCount
end

local function colorFor(count, maxCount)
    if count == 0 or maxCount == 0 then return EMPTY_COLOR end
    local intensity = count / maxCount
    local idx = math.ceil(intensity * #GRADIENT)
    idx = math.max(1, math.min(#GRADIENT, idx))
    return GRADIENT[idx]
end

-- ===================== RENDERING =====================
local function drawHeatmap(name)
    local s = sessions[name]
    if not s or not s.minX then
        box:clear(EMPTY_COLOR)
        box:render()
        lastBounds, lastGrid, lastMaxCount = nil, nil, 0
        return
    end

    local grid, maxCount = rebuildGrid(name)

    for col = 1, GRID_W do
        local column = grid[col]
        for row = 1, GRID_H do
            local count = column and column[row] or 0
            box.canvas[row][col] = colorFor(count, maxCount)
        end
    end
    box:render()

    lastBounds = {
        name = name,
        minX = s.minX, maxX = s.maxX, minZ = s.minZ, maxZ = s.maxZ,
        y = s.lastY,
    }
    lastGrid = grid
    lastMaxCount = maxCount
end

-- Convert a sub-pixel cell back into approximate world coordinates.
local function cellToWorld(col, row)
    local b = lastBounds
    local x, z
    if b.maxX == b.minX then
        x = b.minX
    else
        x = b.minX + (col - 1) / (GRID_W - 1) * (b.maxX - b.minX)
    end
    if b.maxZ == b.minZ then
        z = b.minZ
    else
        z = b.maxZ - (row - 1) / (GRID_H - 1) * (b.maxZ - b.minZ)
    end
    return math.floor(x + 0.5), math.floor(z + 0.5)
end

-- A monitor_touch event only gives us a character cell, which covers a
-- 2 (wide) x 3 (tall) block of sub-pixels. Report whichever of those
-- six was visited most, falling back to the cell's center if empty.
local function touchToCoords(charX, charY)
    if not lastBounds then return nil end

    local colStart = (charX - 1) * 2 + 1
    local rowStart = (charY - 1) * 3 + 1

    local bestCol, bestRow, bestCount = colStart, rowStart, -1
    for dc = 0, 1 do
        for dr = 0, 2 do
            local col, row = colStart + dc, rowStart + dr
            if col >= 1 and col <= GRID_W and row >= 1 and row <= GRID_H then
                local count = (lastGrid and lastGrid[col] and lastGrid[col][row]) or 0
                if count > bestCount then
                    bestCount = count
                    bestCol, bestRow = col, row
                end
            end
        end
    end

    return cellToWorld(bestCol, bestRow)
end

-- ===================== POLLING =====================
local function pollOnce()
    for name in pairs(players) do
        local s = ensureSession(name)
        local x, y, z = tryGetPos(name)

        if x then
            s.active = true
            s.lastY = y
            recordSample(name, x, z)
        else
            s.active = false
        end
    end

    if watchedPlayer then
        drawHeatmap(watchedPlayer)
    end
end

-- ===================== JOIN/LEAVE EVENTS =====================
-- player_detector fires these directly once connected, no wrap/find
-- needed for the events themselves. This gives us an exact, instant
-- moment to reset a session, rather than inferring it from a poll.
local function joinLeaveLoop()
    while true do
        local event, username = os.pullEvent()
        if event == "playerJoin" and players[username] then
            sessions[username] = newSession()
            sessions[username].active = true
            print(username .. " logged in - starting new heatmap session.")
            if watchedPlayer == username then
                drawHeatmap(username)
            end
        elseif event == "playerLeave" and players[username] then
            local s = sessions[username]
            if s then s.active = false end
            print(username .. " logged out - freezing heatmap.")
        elseif event == "hotspot_exit" then
            return
        end
    end
end

-- ===================== COMMANDS =====================
local function printStatus()
    for name in pairs(players) do
        local x, y, z = tryGetPos(name)
        if x then
            print(name .. ": ONLINE at (" .. x .. ", " .. y .. ", " .. z .. ")")
        else
            print(name .. ": offline")
        end
    end
end

local function handleCommand(line)
    local args = {}
    for word in line:gmatch("%S+") do table.insert(args, word) end
    local cmd = args[1]

    if cmd == "add" and args[2] then
        players[args[2]] = true
        ensureSession(args[2])
        savePlayers()
        print("Now tracking " .. args[2])

    elseif cmd == "remove" and args[2] then
        players[args[2]] = nil
        sessions[args[2]] = nil
        if watchedPlayer == args[2] then
            watchedPlayer = nil
            box:clear(EMPTY_COLOR)
            box:render()
        end
        savePlayers()
        print("Stopped tracking " .. args[2])

    elseif cmd == "list" then
        local any = false
        for name in pairs(players) do
            any = true
            print(" - " .. name .. (watchedPlayer == name and "  [watched]" or ""))
        end
        if not any then print("No players tracked yet.") end

    elseif cmd == "watch" and args[2] then
        if not players[args[2]] then
            print(args[2] .. " isn't tracked. Use 'add' first.")
        else
            watchedPlayer = args[2]
            drawHeatmap(watchedPlayer)
            print("Watching " .. args[2] .. " on the monitor.")
        end

    elseif cmd == "status" then
        printStatus()

    elseif cmd == "reset" and args[2] then
        sessions[args[2]] = newSession()
        if watchedPlayer == args[2] then drawHeatmap(args[2]) end
        print("Cleared session data for " .. args[2])

    elseif cmd == "exit" or cmd == "quit" then
        savePlayers()
        print("Saving and exiting...")
        return false

    elseif cmd == "help" then
        print("Commands: add <n> | remove <n> | list | watch <n> | status | reset <n> | exit")

    else
        print("Unknown command. Type 'help' for a list of commands.")
    end

    return true
end

-- ===================== LOOPS =====================
local function commandLoop()
    print("Hotspot Heatmap running. Type 'help' for commands.")
    while true do
        write("> ")
        local line = read()
        if handleCommand(line) == false then
            os.queueEvent("hotspot_exit")
            return
        end
    end
end

local function pollLoop()
    while true do
        local timerId = os.startTimer(POLL_INTERVAL)
        while true do
            local event, id = os.pullEvent()
            if event == "timer" and id == timerId then
                break
            elseif event == "hotspot_exit" then
                return
            end
        end
        pollOnce()
    end
end

local function touchLoop()
    while true do
        local event, side, tx, ty = os.pullEvent("monitor_touch")
        if watchedPlayer and lastBounds then
            local x, z = touchToCoords(tx, ty)
            if x then
                print(string.format(
                    "Clicked (%d,%d) -> approx coords: X=%d Z=%d (%s)",
                    tx, ty, x, z, watchedPlayer
                ))
            end
        end
    end
end

-- ===================== MAIN =====================
players = loadPlayers()
for name in pairs(players) do ensureSession(name) end

box:clear(EMPTY_COLOR)
box:render()

parallel.waitForAny(commandLoop, pollLoop, touchLoop, joinLeaveLoop)
