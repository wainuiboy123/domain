--[[
    HOTSPOT HEATMAP
    ---------------
    Tracks tracked players' positions using a Player Detector peripheral
    named "player_detector", polling every 3 seconds while they're online.

    The currently "watched" player's movement is displayed as a live
    heatmap on a monitor (default peripheral name "heatmap_monitor", or
    it'll grab any connected monitor if that name isn't found), using the
    maximum character resolution the monitor supports.

    Grid layout:
      - Bottom-left pixel  = the player's most -X/-Z position seen this login
      - Top-right pixel    = the player's most +X/+Z position seen this login
      - Color goes from blue (rarely visited) to red (frequently visited)
      - Tracking resets fresh every time the player logs back in

    Click (right-click / "use") any pixel on the monitor to print that
    pixel's approximate real-world coordinates to this computer's terminal.

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
local POLL_INTERVAL = 3     -- seconds between position checks
local PLAYERS_FILE  = "tracked_players.txt"

local GRADIENT = {
    colors.blue, colors.cyan, colors.lightBlue, colors.green,
    colors.lime, colors.yellow, colors.orange, colors.red
}
local EMPTY_COLOR = colors.black

-- ===================== PERIPHERALS =====================
local pd = peripheral.wrap("player_detector")
if not pd then
    error("No peripheral named 'player_detector' found. Check it's connected and named correctly.")
end

local mon = peripheral.wrap("heatmap_monitor") or peripheral.find("monitor")
if not mon then
    error("No monitor found. Connect one (ideally named 'heatmap_monitor').")
end

mon.setTextScale(0.5) -- smallest scale = max character resolution
local GRID_W, GRID_H = mon.getSize()

-- ===================== STATE =====================
local players = {}         -- { [name] = true }
local sessions = {}        -- sessions[name] = { active, minX,maxX,minZ,maxZ, samples = {} }
local watchedPlayer = nil
local lastBounds = nil     -- bounding box used for the last render, for touch lookups

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

-- Record a sample point into the player's session, updating bounds.
local function recordSample(name, x, z)
    local s = ensureSession(name)
    if not s.minX then
        s.minX, s.maxX, s.minZ, s.maxZ = x, x, z, z
    else
        if x < s.minX then s.minX = x end
        if x > s.maxX then s.maxX = x end
        if z < s.minZ then s.minZ = z end
        if z > s.maxZ then s.maxZ = z end
    end
    s.lastX, s.lastZ = x, z
    table.insert(s.samples, { x = x, z = z })
end

-- Map a world coordinate to a grid cell using a session's CURRENT bounds.
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
    mon.setBackgroundColor(EMPTY_COLOR)
    mon.clear()

    local s = sessions[name]
    if not s or not s.minX then
        lastBounds = nil
        return
    end

    local grid, maxCount = rebuildGrid(name)

    for col = 1, GRID_W do
        for row = 1, GRID_H do
            local count = (grid[col] and grid[col][row]) or 0
            local color = colorFor(count, maxCount)
            if color ~= EMPTY_COLOR then
                mon.setCursorPos(col, row)
                mon.setBackgroundColor(color)
                mon.write(" ")
            end
        end
    end

    lastBounds = {
        name = name,
        minX = s.minX, maxX = s.maxX, minZ = s.minZ, maxZ = s.maxZ,
        y = s.lastY,
    }
end

-- Convert a clicked monitor cell back into approximate world coordinates.
local function pixelToCoords(col, row)
    if not lastBounds then return nil end
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

-- ===================== POLLING =====================
local function pollOnce()
    for name in pairs(players) do
        local s = ensureSession(name)
        local x, y, z = tryGetPos(name)

        if x then
            if not s.active then
                -- Catches the case where the computer started up while the
                -- player was already online (no playerJoin event fires for
                -- that, since they didn't just join).
                s.active = true
            end
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
-- player_detector fires these directly once connected, no wrap needed.
-- This gives us an exact, instant moment to reset a session, rather
-- than inferring it from the next 3-second poll.
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
            mon.setBackgroundColor(EMPTY_COLOR)
            mon.clear()
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
        print("Commands: add <name> | remove <name> | list | watch <name> | status | reset <name> | exit")

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
        if watchedPlayer then
            local x, z = pixelToCoords(tx, ty)
            if x then
                print(string.format(
                    "Clicked pixel (%d,%d) -> approx coords: X=%d Z=%d (%s)",
                    tx, ty, x, z, watchedPlayer
                ))
            end
        end
    end
end

-- ===================== MAIN =====================
players = loadPlayers()
for name in pairs(players) do ensureSession(name) end

parallel.waitForAny(commandLoop, pollLoop, touchLoop, joinLeaveLoop)
