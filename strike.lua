-- ==========================================
-- REMOTE ARTILLERY CLIENT (POCKET PC) v19.0
-- (Master Calibration & Pure Physics)
-- CHANGELOG v19.0:
--   - Fixed high-arc solver locking onto the wrong trajectory root.
--     The old code matched "time to cover horizontal distance" against
--     whichever vertical crossing (ascending OR descending) was numerically
--     closer, which frequently picked the ascending crossing for lofted
--     shots. The solver now ONLY considers the true descending landing
--     point, and finds pitch via monotonic bisection instead of scanning
--     for local minima in a noisy diff curve.
--   - getMaxRange() removed; max range is now derived from the real
--     optimal pitch for the current target elevation, not a hardcoded
--     40-degree guess.
-- ==========================================

peripheral.find("modem", function(name) rednet.open(name) end)

-- ==========================================
-- 1. CALIBRATION ZONE
-- ==========================================
local BARREL_LENGTH = 10
local YAW_OFFSET = 0

-- TUNING VARIABLES (Tweak these if shells fall short or overshoot)
local SHELL_DRAG = 0.99
local GRAVITY = 0.05

-- Search bounds / hardware limits
local PITCH_MIN = -30
local PITCH_MAX = 85
local HARDWARE_LIMIT = 60

-- ==========================================
local function wrapAngle(angle) return (angle + 180) % 360 - 180 end

local function speedForCharges(charges, tier)
    return charges * (2.0 + tier * 0.5)
end

-- Simulates a single shot at `pitch` and returns:
--   exactT   - fractional tick count when the shell crosses back DOWN
--              through targetY (the real landing time)
--   dist     - horizontal distance covered by that time
-- Returns nil, nil if the shell never lands at that elevation (can't
-- reach that height, or it's a nonsensical shot at a higher target
-- while already descending).
local function simulateLanding(pitch, targetY, cY, charges, length, tier)
    local initSpeed = speedForCharges(charges, tier)
    local rad = math.rad(pitch)
    local Vw = math.cos(rad) * initSpeed
    local vy = math.sin(rad) * initSpeed
    local xBarrel = length * math.cos(rad)
    local y = cY + math.sin(rad) * length

    -- Can't hit a higher target while already on the way down / flat.
    if y <= targetY and vy <= 0 then return nil, nil end

    local t = 0
    local maxTicks = 3000

    while t < maxTicks do
        local newY = y + vy
        local newVy = SHELL_DRAG * vy - GRAVITY
        t = t + 1

        if vy <= 0 and newY <= targetY then
            -- Crossed downward through target elevation between t-1 and t.
            -- Interpolate the exact fractional tick of impact.
            local frac = 0
            if y ~= newY then frac = (y - targetY) / (y - newY) end
            local exactT = (t - 1) + frac
            local dist = xBarrel + Vw * (1 - SHELL_DRAG ^ exactT) / (1 - SHELL_DRAG)
            return exactT, dist
        end

        y, vy = newY, newVy
    end

    return nil, nil
end

-- Ternary search for the pitch that yields maximum range against the
-- current target elevation (range-vs-pitch is unimodal).
local function findOptimalPitch(targetY, cY, charges, length, tier, lo, hi)
    for _ = 1, 30 do
        local m1 = lo + (hi - lo) / 3
        local m2 = hi - (hi - lo) / 3
        local _, d1 = simulateLanding(m1, targetY, cY, charges, length, tier)
        local _, d2 = simulateLanding(m2, targetY, cY, charges, length, tier)
        d1 = d1 or -1
        d2 = d2 or -1
        if d1 < d2 then lo = m1 else hi = m2 end
    end
    local p = (lo + hi) / 2
    local _, d = simulateLanding(p, targetY, cY, charges, length, tier)
    return p, d
end

-- Bisects for the pitch in [lo, hi] whose landing distance equals `dist`.
-- Requires landing distance to be monotonic across [lo, hi] (true for a
-- single branch split at the optimal-range pitch).
local function bisectPitch(dist, targetY, cY, charges, length, tier, lo, hi)
    local _, dLo = simulateLanding(lo, targetY, cY, charges, length, tier)
    local _, dHi = simulateLanding(hi, targetY, cY, charges, length, tier)
    if not dLo or not dHi then return nil end

    local increasing = dHi > dLo
    if increasing then
        if dist < dLo or dist > dHi then return nil end
    else
        if dist > dLo or dist < dHi then return nil end
    end

    for _ = 1, 40 do
        local mid = (lo + hi) / 2
        local _, dMid = simulateLanding(mid, targetY, cY, charges, length, tier)
        if not dMid then return nil end
        local goLow
        if increasing then goLow = dMid < dist else goLow = dMid > dist end
        if goLow then lo = mid else hi = mid end
    end

    local finalPitch = (lo + hi) / 2
    local finalT = select(1, simulateLanding(finalPitch, targetY, cY, charges, length, tier))
    return finalPitch, finalT
end

-- Returns: pitch, airtimeTicks, status, maxRange
--   status: "OK" | "OUT_OF_RANGE" | "EXCEEDS_60"
local function findBestPitch(dist, targetY, cY, charges, length, tier, useHighArc)
    local pOpt, maxRange = findOptimalPitch(targetY, cY, charges, length, tier, PITCH_MIN, PITCH_MAX)

    if not maxRange or dist > maxRange then
        return nil, nil, "OUT_OF_RANGE", maxRange or 0
    end

    if not useHighArc then
        local pitch, t = bisectPitch(dist, targetY, cY, charges, length, tier, PITCH_MIN, pOpt)
        if not pitch then return nil, nil, "OUT_OF_RANGE", maxRange end
        return pitch, t, "OK", maxRange
    else
        local pitch, t = bisectPitch(dist, targetY, cY, charges, length, tier, pOpt, PITCH_MAX)
        if not pitch then return nil, nil, "OUT_OF_RANGE", maxRange end
        if pitch > HARDWARE_LIMIT then
            return pitch, t, "EXCEEDS_60", maxRange
        end
        return pitch, t, "OK", maxRange
    end
end

term.clear()
term.setCursorPos(1,1)
print("== POCKET ICBM UPLINK ==")
print("Searching for Firebase...")

rednet.broadcast({cmd = "GET_INFO"}, "CBC_ARTILLERY")
local serverId, info = rednet.receive("CBC_ARTILLERY", 3)

if not serverId then
    print("ERROR: No Cannon Server found.")
    return
end

print("Uplink Active! [ID: " .. serverId .. "]")
local cX, cY, cZ = info.x, info.y, info.z

-- ==========================================
-- 2. GET STRIKE COORDINATES
-- ==========================================
print("------------------------")
print("Target X:")
local tX = tonumber(io.read())
print("Target Z:")
local tZ = tonumber(io.read())
print("Target Y (Elevation):")
local tY = tonumber(io.read())

print("Number of Charges:")
local charges = tonumber(io.read())

print("Charge Tier (0=Base, 1-5=Mk1-5):")
local chargeTier = tonumber(io.read()) or 0

print("Fire Mode (1=Normal, 2=High-Arc):")
local modeInput = io.read()
local isHighArc = (modeInput == "2")

-- ==========================================
-- 3. CBC BALLISTIC SIMULATION
-- ==========================================
local dx = tX - cX
local dz = tZ - cZ
local distXZ = math.sqrt(dx^2 + dz^2)

term.clear()
term.setCursorPos(1,1)
print("Simulating Trajectory...")

local targetPitch, airtimeTicks, status, maxRange = findBestPitch(distXZ, tY, cY, charges, BARREL_LENGTH, chargeTier, isHighArc)

if status == "EXCEEDS_60" then
    print("\n== FIRING SOLUTION REJECTED ==")
    print(string.format("Required Pitch : %.1f deg", targetPitch))
    print("Hardware Limit : 60.0 deg")
    print("------------------------------")
    print("FIX: REMOVE powder charges.")
    print("Your payload is too fast for")
    print("a 60-degree High-Arc shot.")
    return
elseif status == "OUT_OF_RANGE" then
    print("\n== FIRING SOLUTION REJECTED ==")
    print(string.format("Target Range   : %dm", math.floor(distXZ)))
    print(string.format("Max Range      : ~%dm", math.floor(maxRange)))
    print("------------------------------")

    if maxRange <= 0 then
        print("FIX: Cannot reach altitude.")
        print("You are shooting uphill and need")
        print("significantly more powder.")
    else
        print(string.format("Shortfall      : %dm", math.floor(distXZ) - math.floor(maxRange)))
        print("------------------------------")
        print("FIX: Add more powder charges or")
        print("upgrade to a higher Tier shell.")
    end
    return
end

local targetYaw = math.deg(math.atan2(-dx, dz)) + YAW_OFFSET
targetYaw = (targetYaw % 360 + 360) % 360
airtimeTicks = math.floor(airtimeTicks)

-- ==========================================
-- 4. REMOTE EXECUTION
-- ==========================================
term.clear()
term.setCursorPos(1,1)
print("Tgt : " .. math.floor(distXZ) .. "m away")
print("Yaw : " .. string.format("%.1f", targetYaw))
print("Ptch: " .. string.format("%.2f", targetPitch))
print("Fuze: " .. airtimeTicks .. " ticks")

if isHighArc then print("Mode: HIGH-ARC MORTAR") else print("Mode: NORMAL FIRE") end

print("\n[C] Cancel, [Enter] Assemble")
if io.read() == "c" then return end

rednet.send(serverId, {cmd = "ASSEMBLE", state = true}, "CBC_ARTILLERY")
rednet.receive("CBC_ARTILLERY", 1)

print("Sending Aim Data...")
rednet.send(serverId, {cmd = "AIM", yaw = targetYaw, pitch = targetPitch}, "CBC_ARTILLERY")

while true do
    rednet.send(serverId, {cmd = "GET_INFO"}, "CBC_ARTILLERY")
    local _, curInfo = rednet.receive("CBC_ARTILLERY", 2)

    if curInfo and curInfo.yaw then
        local curYaw = (curInfo.yaw % 360 + 360) % 360
        local curPitch = curInfo.pitch

        local yDiff = math.abs(wrapAngle(targetYaw - curYaw))
        local pDiff = math.abs(targetPitch - curPitch)

        local x, y = term.getCursorPos()
        term.setCursorPos(1, y)
        term.clearLine()
        term.write(string.format("Y: %.1f | P: %.1f", curYaw, curPitch))

        if yDiff <= 0.5 and pDiff <= 0.5 then
            print("\n\n!! TARGET LOCKED !!")
            break
        end
    end
    os.sleep(0.1)
end

print("\nType 'FIRE' to launch:")
if io.read() == "FIRE" then
    rednet.send(serverId, {cmd = "FIRE", state = true}, "CBC_ARTILLERY")
    os.sleep(0.5)
    rednet.send(serverId, {cmd = "FIRE", state = false}, "CBC_ARTILLERY")
    print("\n>> SPLASH INBOUND <<")
end
