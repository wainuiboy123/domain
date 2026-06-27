--====================================================--v2
--   RADAR TRACKER
--   CC: Tweaked + Advanced Peripherals + Create
--
--   Hardware required (all wired to this computer):
--     - player_detector  (Advanced Peripherals)
--     - redstone_integrator  OR direct redstone wiring
--       with two outputs:
--         CLUTCH_SIDE  : true = clutch engaged (rotating)
--         GEARSHIFT_SIDE: true = counter-clockwise, false = clockwise
--
--   Create rotational setup:
--     Motor → Clutch → Gearshift → Bearing → Radar
--
--   On startup the radar MUST be manually facing due North (0°).
--   The script dead-reckons the heading from that calibration point.
--
--   Save as /startup.lua for auto-run on boot.
--====================================================--

--========== CONFIG ==========--

-- Redstone sides for the two control signals.
-- If you're using a Redstone Integrator peripheral instead of direct
-- redstone outputs, swap the setOutput calls in setClutch/setGearshift
-- below to use peripheral.call("redstone_integrator", "setOutput", side, state).
local CLUTCH_SIDE    = "bottom"    -- redstone side controlling the clutch
local GEARSHIFT_SIDE = "top"   -- redstone side controlling the gearshift

-- RPM of the rotational system at the bearing.
-- Measure this in-game with a Speedometer or Stressometer.
-- At 16 RPM the bearing rotates 96 degrees/second.
local BEARING_RPM = 30

-- How close (degrees) is "close enough" to stop rotating.
-- Smaller = more precise but may oscillate. 2° is a good balance.
local TOLERANCE_DEG = 2

-- How many seconds between each update cycle.
-- Lower = smoother tracking but more CPU. 0.05 = 20 updates/sec.
local UPDATE_INTERVAL = 0.05

--558 -54 -60
-- Fixed world position of the radar/bearing block.
-- You MUST set these to your radar's actual coordinates.
local RADAR_X = 558
local RADAR_Y = -54
local RADAR_Z = -60

-- Range (metres) to search for players.
-- Advanced Peripherals player_detector max is typically 100000.
local DETECT_RANGE = 1000

--========== DERIVED CONSTANTS ==========--

-- Degrees per second the bearing rotates at BEARING_RPM.
-- 1 RPM = 6 deg/sec (360/60). So RPM * 6 = deg/sec.
local DEG_PER_SEC = BEARING_RPM * 6

--========== PERIPHERAL SETUP ==========--

local detector = peripheral.find("player_detector")
if not detector then
    error("No player_detector found! Attach one to this computer.", 0)
end

print("=== Radar Tracker ===")
print("Detector  : " .. peripheral.getName(detector))
print("Radar pos : " .. RADAR_X .. ", " .. RADAR_Y .. ", " .. RADAR_Z)
print("RPM       : " .. BEARING_RPM .. " (" .. DEG_PER_SEC .. " deg/s)")
print("Tolerance : " .. TOLERANCE_DEG .. " deg")
print("")
print("Ensure radar is facing NORTH (0 deg) before starting.")
print("Enabling clutch so radar becomes a physics object...")
print("Press any key when ready to begin tracking...")

-- Engage clutch now so the bearing becomes a moveable physics object
-- while you manually rotate the radar to face North.
setClutch(true)
setGearshift(false)

os.pullEvent("key")

-- Disengage until tracking starts
setClutch(false)

--========== STATE ==========--

-- Software estimate of the radar's current heading, in degrees [0, 360).
local currentYaw = 0.0

-- Whether the clutch is currently engaged.
local clutchOn = false

-- Direction currently rotating: 1 = clockwise, -1 = CCW, 0 = stopped.
local rotDir = 0

-- Timestamp of the last time we updated the yaw estimate.
local lastUpdateTime = os.clock()

--========== REDSTONE CONTROL ==========--

local function setClutch(state)
    -- state: true = engage clutch (allow rotation), false = stop
    redstone.setOutput(CLUTCH_SIDE, state)
    clutchOn = state
end

local function setGearshift(ccw)
    -- ccw: true = counter-clockwise, false = clockwise
    redstone.setOutput(GEARSHIFT_SIDE, ccw)
end

local function stopRadar()
    setClutch(false)
    rotDir = 0
end

local function rotateClockwise()
    setGearshift(false)
    setClutch(true)
    rotDir = 1
end

local function rotateCounterClockwise()
    setGearshift(true)
    setClutch(true)
    rotDir = -1
end

-- Always stop cleanly on exit
local function cleanup()
    stopRadar()
    -- Make sure gearshift is in a neutral state
    setGearshift(false)
end

--========== YAW MATH ==========--

-- Normalise any angle into [0, 360).
local function normalise(angle)
    return ((angle % 360) + 360) % 360
end

-- Shortest signed angular distance from `from` to `to`.
-- Returns a value in (-180, 180].
-- Positive = clockwise, negative = counter-clockwise.
local function angularDelta(from, to)
    local diff = normalise(to) - normalise(from)
    if diff > 180  then diff = diff - 360 end
    if diff <= -180 then diff = diff + 360 end
    return diff
end

-- Calculate the desired yaw from the radar to a world position.
-- Minecraft yaw: 0 = North (-Z), 90 = East (+X), 180 = South (+Z), 270 = West (-X).
-- math.atan2 returns the angle from +X axis, so we convert.
local function yawToTarget(px, pz)
    local dx = px - RADAR_X
    local dz = pz - RADAR_Z
    -- atan2(dx, -dz) gives Minecraft yaw in radians: North=0, East=90, etc.
    local radians = math.atan2(dx, -dz)
    return normalise(math.deg(radians))
end

--========== PLAYER DETECTION ==========--

-- Returns the position of the nearest player, or nil if none found.
local function getNearestPlayer()
    local ok, names = pcall(function()
        return detector.getPlayersInRange(DETECT_RANGE)
    end)
    if not ok or not names or #names == 0 then
        -- Fallback: try getOnlinePlayers
        local ok2, allNames = pcall(function()
            return detector.getOnlinePlayers()
        end)
        if not ok2 or not allNames or #allNames == 0 then
            return nil
        end
        names = allNames
    end

    local nearest     = nil
    local nearestDist = math.huge

    for _, name in ipairs(names) do
        local pos = detector.getPlayerPos(name)
        if pos then
            local dx   = pos.x - RADAR_X
            local dz   = pos.z - RADAR_Z
            -- Horizontal distance only — radar only rotates horizontally
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist < nearestDist then
                nearestDist = dist
                nearest = { name = name, x = pos.x, y = pos.y, z = pos.z, dist = dist }
            end
        end
    end

    return nearest
end

--========== DEAD-RECKONING YAW UPDATE ==========--

-- Call this every tick BEFORE issuing new movement commands.
-- Updates currentYaw based on how long the bearing has been rotating.
local function updateYawEstimate()
    local now     = os.clock()
    local elapsed = now - lastUpdateTime
    lastUpdateTime = now

    if clutchOn and rotDir ~= 0 then
        local delta = DEG_PER_SEC * elapsed * rotDir
        currentYaw  = normalise(currentYaw + delta)
    end
end

--========== STATUS DISPLAY ==========--

-- Prints a compact one-line status to the terminal.
-- Overwrites the same line each cycle for a live dashboard feel.
local lineCount = 0
local function printStatus(target, desiredYaw, delta)
    -- Move cursor up to overwrite previous status block (4 lines)
    if lineCount > 0 then
        for _ = 1, lineCount do
            term.clearLine()
            local _, y = term.getCursorPos()
            if y > 1 then term.setCursorPos(1, y - 1) end
        end
        term.clearLine()
        term.setCursorPos(1, select(2, term.getCursorPos()))
    end

    if target then
        print(string.format("Target  : %s  (%.1fm)", target.name, target.dist))
        print(string.format("Desired : %.1f deg   Current : %.1f deg", desiredYaw, currentYaw))
        print(string.format("Delta   : %.1f deg   Dir: %s",
            delta,
            rotDir ==  1 and "CW  >>>" or
            rotDir == -1 and "CCW <<<" or
            "STOP ---"
        ))
        lineCount = 3
    else
        print("Target  : none — radar stopped")
        print(string.format("Current : %.1f deg", currentYaw))
        lineCount = 2
    end
end

--========== MAIN LOOP ==========--

print("")
print("Tracking started. Ctrl+T to stop.")
print("")
lineCount = 0

lastUpdateTime = os.clock()

local running = true

-- Catch terminate so we can clean up the redstone outputs
local function main()
    while true do
        -- 1. Update our yaw estimate based on elapsed rotation time
        updateYawEstimate()

        -- 2. Find the nearest player
        local target = getNearestPlayer()

        if not target then
            -- No target — stop the radar
            if clutchOn then stopRadar() end
            printStatus(nil, 0, 0)
        else
            -- 3. Calculate desired heading and angular error
            local desiredYaw = yawToTarget(target.x, target.z)
            local delta      = angularDelta(currentYaw, desiredYaw)

            -- 4. Drive toward the target
            if math.abs(delta) <= TOLERANCE_DEG then
                -- Within tolerance — stop
                if clutchOn then stopRadar() end
            elseif delta > 0 then
                -- Need to rotate clockwise
                if rotDir ~= 1 then rotateClockwise() end
            else
                -- Need to rotate counter-clockwise
                if rotDir ~= -1 then rotateCounterClockwise() end
            end

            printStatus(target, desiredYaw, delta)
        end

        -- 5. Wait before next cycle
        sleep(UPDATE_INTERVAL)
    end
end

-- Watchdog wraps main so Ctrl+T cleans up and any crash restarts
while true do
    local ok, err = pcall(main)
    cleanup()
    if not ok then
        if tostring(err):find("Terminated") then
            print("")
            print("Radar tracker stopped. Redstone outputs cleared.")
            break
        end
        print("Crashed: " .. tostring(err))
        print("Restarting in 3 seconds...")
        sleep(3)
        lastUpdateTime = os.clock()
        lineCount = 0
    else
        break
    end
end
