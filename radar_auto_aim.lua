--====================================================--v4
--   RADAR TRACKER
--   CC: Tweaked + Advanced Peripherals + Create
--
--   Hardware required (all wired to this computer):
--     - player_detector  (Advanced Peripherals)
--     - Two redstone outputs:
--         CLUTCH_SIDE   : true = clutch engaged (rotating)
--         GEARSHIFT_SIDE: true = counter-clockwise, false = clockwise
--
--   Create rotational setup:
--     Motor -> Clutch -> Gearshift -> Bearing -> Radar
--
--   On startup the radar MUST be manually facing due North (0 deg).
--   The script dead-reckons the heading from that calibration point.
--
--   Save as /startup.lua for auto-run on boot.
--====================================================--

--========== CONFIG ==========--

local CLUTCH_SIDE    = "left"    -- redstone side controlling the clutch
local GEARSHIFT_SIDE = "right"   -- redstone side controlling the gearshift

-- RPM of the rotational system AT THE BEARING.
-- Measure in-game with a Speedometer placed on the shaft going into the bearing.
local BEARING_RPM = 30

-- How close (degrees) is "close enough" to stop rotating.
-- Larger = less jitter, but less precise. Start with 3-5 and tune down.
local TOLERANCE_DEG = 4

-- Seconds between update cycles. 0.1 = 10 updates/sec (plenty for this use case).
-- Too low and sleep() rounding eats your timing accuracy.
local UPDATE_INTERVAL = 0.1

-- Fixed world position of the BEARING block (not the radar model, the bearing itself).
local RADAR_X = 558
local RADAR_Y = -54
local RADAR_Z = -60

-- Minimum horizontal distance (metres) before we bother tracking.
-- Prevents the "spinning in circles" bug when the player is almost directly above.
local MIN_TRACK_DIST = 3

-- Range to search for players.
local DETECT_RANGE = 10000

--========== DERIVED CONSTANTS ==========--

-- At N RPM, the bearing does N/60 full rotations per second = N*6 degrees/second.
local DEG_PER_SEC = BEARING_RPM * 6

--========== PERIPHERAL SETUP ==========--

local detector = peripheral.find("player_detector")
if not detector then
    error("No player_detector found! Attach one to this computer.", 0)
end

--========== STATE ==========--

local currentYaw     = 0.0    -- software estimate of heading, degrees [0, 360)
local clutchOn       = false
local rotDir         = 0      -- 1 = CW, -1 = CCW, 0 = stopped
-- Wall-clock time tracking using os.epoch for accuracy.
-- os.clock() measures CPU time in CC:Tweaked, NOT wall time — don't use it.
local lastEpochMs    = os.epoch("utc")

--========== REDSTONE CONTROL ==========--

local function setClutch(state)
    redstone.setOutput(CLUTCH_SIDE, state)
    clutchOn = state
end

local function setGearshift(ccw)
    redstone.setOutput(GEARSHIFT_SIDE, ccw)
end

local function stopRadar()
    -- Stop clutch FIRST so the bearing halts, then update state.
    setClutch(false)
    rotDir = 0
end

local function rotateClockwise()
    -- Set gearshift direction BEFORE engaging clutch to avoid a momentary wrong-direction pulse.
    setGearshift(false)
    setClutch(true)
    rotDir = 1
end

local function rotateCounterClockwise()
    setGearshift(true)
    setClutch(true)
    rotDir = -1
end

local function cleanup()
    stopRadar()
    setGearshift(false)
end

--========== STARTUP CALIBRATION ==========--

print("=== Radar Tracker ===")
print("Detector  : " .. peripheral.getName(detector))
print("Radar pos : " .. RADAR_X .. ", " .. RADAR_Y .. ", " .. RADAR_Z)
print("RPM       : " .. BEARING_RPM .. "  (" .. DEG_PER_SEC .. " deg/s)")
print("Tolerance : " .. TOLERANCE_DEG .. " deg")
print("")
print("Ensure radar is facing NORTH (0 deg) before pressing a key.")
print("Engaging clutch so you can spin the radar to face North...")

setGearshift(false)
setClutch(true)     -- engage so bearing becomes a physics object you can rotate

os.pullEvent("key")

setClutch(false)    -- stop before tracking starts
print("")
print("Calibrated. Starting tracker...")
print("")

--========== YAW MATH ==========--

local function normalise(angle)
    return ((angle % 360) + 360) % 360
end

-- Shortest signed delta from `from` to `to`, result in (-180, 180].
-- Positive = clockwise, negative = counter-clockwise.
local function angularDelta(from, to)
    local diff = normalise(to) - normalise(from)
    if diff >  180 then diff = diff - 360 end
    if diff <= -180 then diff = diff + 360 end
    return diff
end

-- Bearing (yaw) from radar to a world XZ position, in Minecraft convention:
--   North (-Z) = 0, East (+X) = 90, South (+Z) = 180, West (-X) = 270
--
-- FIXED: previous version used atan2(dx, -dz) which is mathematically correct
-- BUT Lua's math.atan2(y, x) takes (y, x) not (x, y).
-- We want the angle measured clockwise from North, so:
--   angle = atan2(dx, -dz)   <- dx is the "east" component, -dz is the "north" component
-- This IS correct as written, but only if atan2 is called as atan2(dx, -dz).
-- Lua's math.atan2(a, b) = atan(a/b), so atan2(dx, -dz) = atan(dx / -dz). Correct.
local function yawToTarget(px, pz)
    local dx = px - RADAR_X
    local dz = pz - RADAR_Z
    local radians = math.atan2(dx, -dz)
    return normalise(math.deg(radians))
end

--========== DEAD RECKONING ==========--

-- Updates currentYaw based on actual wall-clock time elapsed since last call.
-- Uses os.epoch("utc") in milliseconds — this is real wall time, unlike os.clock().
-- IMPORTANT: call this at the START of each cycle, before issuing new commands,
-- so the estimate reflects what happened during the previous sleep().
local function updateYawEstimate()
    local nowMs   = os.epoch("utc")
    local elapsed = (nowMs - lastEpochMs) / 1000.0   -- convert ms -> seconds
    lastEpochMs   = nowMs

    -- Only accumulate rotation if the clutch was actually engaged last cycle.
    -- rotDir tracks direction, clutchOn tracks whether we were really moving.
    if clutchOn and rotDir ~= 0 then
        currentYaw = normalise(currentYaw + DEG_PER_SEC * elapsed * rotDir)
    end
end

--========== PLAYER DETECTION ==========--

local function getNearestPlayer()
    local names
    local ok, result = pcall(function()
        return detector.getPlayersInRange(DETECT_RANGE)
    end)
    if ok and result and #result > 0 then
        names = result
    else
        local ok2, result2 = pcall(function()
            return detector.getOnlinePlayers()
        end)
        if ok2 and result2 and #result2 > 0 then
            names = result2
        else
            return nil
        end
    end

    local nearest     = nil
    local nearestDist = math.huge

    for _, name in ipairs(names) do
        local pos = detector.getPlayerPos(name)
        if pos then
            local dx   = pos.x - RADAR_X
            local dz   = pos.z - RADAR_Z
            -- Horizontal distance only. If the player is within MIN_TRACK_DIST
            -- horizontally the bearing is basically on top of them and atan2
            -- becomes unreliable — skip them.
            local hdist = math.sqrt(dx * dx + dz * dz)
            if hdist >= MIN_TRACK_DIST and hdist < nearestDist then
                nearestDist = hdist
                nearest = {
                    name  = name,
                    x     = pos.x,
                    y     = pos.y,
                    z     = pos.z,
                    hdist = hdist,
                }
            end
        end
    end

    return nearest
end

--========== STATUS DISPLAY ==========--

local statusLines = 0

local function printStatus(target, desiredYaw, delta)
    -- Erase previous status lines
    if statusLines > 0 then
        local _, cy = term.getCursorPos()
        for _ = 1, statusLines do
            local _, y = term.getCursorPos()
            term.clearLine()
            if y > 1 then
                term.setCursorPos(1, y - 1)
            end
        end
        term.clearLine()
        term.setCursorPos(1, select(2, term.getCursorPos()))
    end

    if target then
        print(string.format("Target  : %-16s  dist=%.1fm", target.name, target.hdist))
        print(string.format("Desired : %6.1f deg    Current : %6.1f deg", desiredYaw, currentYaw))
        print(string.format("Delta   : %+6.1f deg    Dir     : %s",
            delta,
            rotDir ==  1 and "CW  >>>" or
            rotDir == -1 and "CCW <<<" or
            "STOP ---"
        ))
        statusLines = 3
    else
        print("Target  : none (no player, or all within " .. MIN_TRACK_DIST .. "m) — stopped")
        print(string.format("Current : %.1f deg", currentYaw))
        statusLines = 2
    end
end

--========== MAIN LOOP ==========--

print("Tracking. Ctrl+T to stop.")
print("")
statusLines = 0
lastEpochMs = os.epoch("utc")

local function main()
    while true do
        -- Step 1: update yaw estimate for time elapsed since last cycle
        updateYawEstimate()

        -- Step 2: find target
        local target = getNearestPlayer()

        if not target then
            if clutchOn then stopRadar() end
            printStatus(nil, 0, 0)
        else
            -- Step 3: calculate where we need to point
            local desiredYaw = yawToTarget(target.x, target.z)
            local delta      = angularDelta(currentYaw, desiredYaw)

            -- Step 4: drive toward target using shortest path
            if math.abs(delta) <= TOLERANCE_DEG then
                -- On target — stop
                if clutchOn then stopRadar() end
            elseif delta > 0 then
                -- Positive delta = need to go clockwise
                if rotDir ~= 1 then
                    rotateClockwise()
                end
            else
                -- Negative delta = need to go counter-clockwise
                if rotDir ~= -1 then
                    rotateCounterClockwise()
                end
            end

            printStatus(target, desiredYaw, delta)
        end

        -- Step 5: sleep, then loop (yaw estimate will account for this sleep duration)
        sleep(UPDATE_INTERVAL)
    end
end

while true do
    local ok, err = pcall(main)
    cleanup()
    if not ok then
        if tostring(err):find("Terminated") then
            print("")
            print("Stopped. Redstone cleared.")
            break
        end
        print("Crashed: " .. tostring(err))
        print("Restarting in 3s...")
        sleep(3)
        lastEpochMs = os.epoch("utc")
        statusLines = 0
    else
        break
    end
end
