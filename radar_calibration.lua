--====================================================--
--   RADAR CALIBRATION TOOL
--   Run this BEFORE radar_tracker.lua to find your
--   exact degrees/second and verify CW/CCW direction.
--
--   Step 1: finds deg/sec by timing a known rotation
--   Step 2: verifies yaw calculation is correct
--====================================================--

local CLUTCH_SIDE    = "bottom"
local GEARSHIFT_SIDE = "top"
local MOTOR_RPM      = 30    -- what your motor is set to (just for display)

-- World position of the bearing block
local RADAR_X = 558
local RADAR_Y = -54
local RADAR_Z = -60

local detector = peripheral.find("player_detector")
if not detector then
    error("No player_detector found!", 0)
end

local function setClutch(state)  redstone.setOutput(CLUTCH_SIDE, state) end
local function setGearshift(ccw) redstone.setOutput(GEARSHIFT_SIDE, ccw) end

local function normalise(a)
    return ((a % 360) + 360) % 360
end

local function stopAll()
    setClutch(false)
    setGearshift(false)
end

stopAll()

print("=== RADAR CALIBRATION ===")
print("")
print("This will run two tests:")
print("  1. Spin for exactly 10 seconds, you mark start/end visually")
print("  2. Verify yaw calculation by standing at a known direction")
print("")
print("Make sure radar faces NORTH (0 deg) before starting.")
print("Press any key to begin...")
os.pullEvent("key")

--====================================================--
--  TEST 1: Measure deg/sec
--  Spin the radar for exactly 10 seconds clockwise,
--  you count how many full rotations + partial it did.
--====================================================--

print("")
print("=== TEST 1: Speed Measurement ===")
print("Watch the radar carefully.")
print("Note its starting direction, then count full rotations.")
print("")
print("Press any key to start spinning (will spin for 10 seconds)...")
os.pullEvent("key")

setGearshift(false)  -- clockwise
setClutch(true)

local startMs = os.epoch("utc")
print("Spinning CW for 10 seconds... count the rotations!")

sleep(10)

setClutch(false)
local endMs = os.epoch("utc")
local elapsed = (endMs - startMs) / 1000.0

print("")
print("Stopped. Elapsed: " .. string.format("%.2f", elapsed) .. "s")
print("")
print("How many full rotations did it complete?")
print("(e.g. type 2 for 2 full rotations, or 0.5 for half a rotation)")
io.write("> ")
local rotations = tonumber(io.read())
if not rotations then
    print("Invalid input, using 0.5 as default")
    rotations = 0.5
end

local totalDeg  = rotations * 360
local degPerSec = totalDeg / elapsed

print("")
print("Results:")
print(string.format("  Motor RPM    : %d", MOTOR_RPM))
print(string.format("  Rotations    : %.2f", rotations))
print(string.format("  Total degrees: %.1f", totalDeg))
print(string.format("  Deg/sec      : %.2f", degPerSec))
print(string.format("  Effective RPM: %.2f", degPerSec / 6))
print(string.format("  Speed ratio  : 1/%.2f  (motor:bearing)", MOTOR_RPM / (degPerSec / 6)))
print("")
print(">> Set BEARING_RPM = " .. string.format("%.1f", degPerSec / 6) .. " in radar_tracker.lua")
print("   (or set DEG_PER_SEC directly to " .. string.format("%.2f", degPerSec) .. ")")

--====================================================--
--  TEST 2: Verify CW direction
--  Make sure clockwise in software = clockwise visually
--====================================================--

print("")
print("=== TEST 2: Direction Verification ===")
print("Face the radar North again, then press any key.")
print("It will spin clockwise for 2 seconds (should rotate ~east).")
io.write("> ")
os.pullEvent("key")

local predictedDeg = degPerSec * 2
print(string.format("Spinning CW for 2 seconds (expecting ~%.0f deg rotation)...", predictedDeg))

setGearshift(false)
setClutch(true)
sleep(2)
setClutch(false)

print("")
print("The radar should now be pointing roughly " .. string.format("%.0f", normalise(predictedDeg)) .. " deg from North.")
print("Which direction is it actually pointing? (rough compass: N/NE/E/SE/S/SW/W/NW)")
io.write("> ")
local dir = io.read()
print("")

local dirMap = {
    N=0, NE=45, E=90, SE=135, S=180, SW=225, W=270, NW=315,
    n=0, ne=45, e=90, se=135, s=180, sw=225, w=270, nw=315,
}
local actualDeg = dirMap[dir]
if actualDeg then
    local err = normalise(actualDeg) - normalise(predictedDeg)
    if err > 180 then err = err - 360 end
    print(string.format("Predicted: %.0f deg,  Actual: %.0f deg,  Error: %+.0f deg", predictedDeg, actualDeg, err))
    if math.abs(err) > 90 then
        print(">> DIRECTION IS LIKELY INVERTED!")
        print("   Try swapping CLUTCH_SIDE and GEARSHIFT_SIDE, or flip your gearshift redstone.")
        print("   Alternatively add: local INVERT_DIR = true  to radar_tracker.lua")
    elseif math.abs(err) < 45 then
        print(">> Direction looks correct!")
    else
        print(">> Partial mismatch — check your BEARING_RPM value.")
    end
else
    print("Unrecognised direction, skipping analysis.")
end

--====================================================--
--  TEST 3: Yaw calculation check
--  Stand somewhere specific and verify desired yaw matches
--====================================================--

print("")
print("=== TEST 3: Yaw Calculation ===")
print("Stand DUE EAST of the radar (same Y is fine).")
print("The desired yaw should read 90 degrees.")
print("Press any key when you're in position...")
os.pullEvent("key")

local pos = nil
local names
local ok, result = pcall(function() return detector.getOnlinePlayers() end)
if ok and result then names = result end
if names and #names > 0 then
    pos = detector.getPlayerPos(names[1])
end

if pos then
    local dx = pos.x - RADAR_X
    local dz = pos.z - RADAR_Z
    local hdist = math.sqrt(dx*dx + dz*dz)
    local radians = math.atan2(dx, -dz)
    local desiredYaw = normalise(math.deg(radians))

    print(string.format("Player pos : %.1f, %.1f, %.1f", pos.x, pos.y, pos.z))
    print(string.format("Radar pos  : %d, %d, %d", RADAR_X, RADAR_Y, RADAR_Z))
    print(string.format("dx=%.1f  dz=%.1f  hdist=%.1f", dx, dz, hdist))
    print(string.format("Desired yaw: %.1f deg", desiredYaw))
    print("")
    if math.abs(desiredYaw - 90) < 20 then
        print(">> Yaw calculation looks CORRECT! (close to 90 deg for East)")
    else
        print(">> Yaw seems OFF. Expected ~90 for East, got " .. string.format("%.1f", desiredYaw))
        print("   Your radar X/Z coords may be wrong, or Minecraft's axes are flipped on your server.")
        -- Try alternative formula
        local alt = normalise(math.deg(math.atan2(-dx, dz)))
        print("   Alternative formula gives: " .. string.format("%.1f", alt) .. " deg")
        if math.abs(alt - 90) < 20 then
            print("   >> Try flipping the formula in radar_tracker.lua!")
        end
    end
else
    print("Could not get player position — make sure you're within detector range.")
end

print("")
print("=== CALIBRATION COMPLETE ===")
print("Use the values above to update radar_tracker.lua config.")
stopAll()
