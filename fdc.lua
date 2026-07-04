-- ==========================================
-- NODE 2: FIREMISSION DIRECTOR v19
-- (Master Physics Calculator & Hub)
-- CHANGELOG v19:
--   - Cannons are no longer discovered by PINGing on demand. Slaves push
--     their coordinates/ID on a heartbeat; the FDC just keeps a live
--     roster (pruning anyone who's gone quiet) and uses whatever's
--     registered at the moment a strike is requested.
--   - Ported the corrected ballistic solver from the pocket client v19:
--     the old findBestPitch()/timeInAir() picked whichever vertical
--     crossing (ascending OR descending) was numerically closer to the
--     horizontal-time estimate, which frequently locked onto the wrong
--     root for lofted shots. The new solver only ever matches against
--     the true descending/landing crossing, and finds pitch via
--     monotonic bisection split at the true optimal-range angle
--     instead of scanning for local minima in a noisy diff curve.
--   - STRIKE_REQ now carries a `highArc` flag from the commander so the
--     FDC solves the correct branch (flat vs lofted) per cannon.
-- ==========================================

peripheral.find("modem", function(name) rednet.open(name) end)

local VELOCITY_PER_BARREL = 0.1
local SHELL_DRAG = 0.99
local GRAVITY = 0.05
local PITCH_MIN = -30
local PITCH_MAX = 85
local HARDWARE_LIMIT = 60
local CANNON_TIMEOUT = 15 -- seconds; drop cannons that haven't checked in recently

local activeCannons = {}  -- [id] = {x=, y=, z=, barrelLength=, yawOffset=, lastSeen=}
local lockedIds = {}      -- [id] = true, cannons that reported LOCKED for the current mission

-- ==========================================
-- PHYSICS (corrected high-arc solver)
-- ==========================================
local function speedForCharges(charges, tier, length)
    return (charges * (2.0 + tier * 0.5)) + (length * VELOCITY_PER_BARREL)
end

-- Simulates a single shot at `pitch` and returns:
--   exactT - fractional tick count when the shell crosses back DOWN
--            through targetY (the real landing time)
--   dist   - horizontal distance covered by that time
-- Returns nil, nil if the shell never lands at that elevation.
local function simulateLanding(pitch, targetY, cY, charges, length, tier)
    local initSpeed = speedForCharges(charges, tier, length)
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

-- Ternary search for the pitch giving maximum range against this target elevation.
local function findOptimalPitch(targetY, cY, charges, length, tier, lo, hi)
    for _ = 1, 30 do
        local m1 = lo + (hi - lo) / 3
        local m2 = hi - (hi - lo) / 3
        local _, d1 = simulateLanding(m1, targetY, cY, charges, length, tier)
        local _, d2 = simulateLanding(m2, targetY, cY, charges, length, tier)
        d1, d2 = d1 or -1, d2 or -1
        if d1 < d2 then lo = m1 else hi = m2 end
    end
    local p = (lo + hi) / 2
    local _, d = simulateLanding(p, targetY, cY, charges, length, tier)
    return p, d
end

-- Bisects for the pitch in [lo, hi] whose landing distance equals `dist`.
-- Requires landing distance to be monotonic across [lo, hi].
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

-- Returns pitch, airtimeTicks, status ("OK"/"OUT_OF_RANGE"/"EXCEEDS_60"), maxRange
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

-- ==========================================
-- BACKGROUND: CANNON ROSTER / LOCK LISTENER
-- Always running, independent of whatever the director loop is doing.
-- ==========================================
local function cannonListener()
    while true do
        local senderId, msg = rednet.receive("CBC_ARTILLERY")
        if type(msg) == "table" then
            if msg.cmd == "REGISTER" then
                activeCannons[senderId] = {
                    x = msg.x, y = msg.y, z = msg.z,
                    barrelLength = msg.barrelLength,
                    yawOffset = msg.yawOffset,
                    lastSeen = os.clock()
                }
            elseif msg.cmd == "LOCKED" then
                lockedIds[senderId] = true
            end
        end
    end
end

local function livingCannons()
    local now = os.clock()
    local live = {}
    for id, data in pairs(activeCannons) do
        if now - data.lastSeen <= CANNON_TIMEOUT then
            live[id] = data
        end
    end
    return live
end

-- ==========================================
-- MAIN: COMMANDER / STRIKE HANDLING
-- ==========================================
local function directorLoop()
    term.clear()
    term.setCursorPos(1,1)
    print("=== FIREMISSION DIRECTOR ACTIVE ===")
    print("ID: " .. os.getComputerID())
    print("-----------------------------------")

    -- Ask any cannons already running to check in right now rather
    -- than waiting for their next heartbeat.
    rednet.broadcast({cmd = "REQUEST_REGISTER"}, "CBC_ARTILLERY")

    while true do
        local senderId, msg = rednet.receive("CBC_DIRECTOR")

        if type(msg) == "table" and msg.cmd == "STRIKE_REQ" then
            print("\n> Strike Request from Commander [" .. senderId .. "]")
            print("> Target: " .. msg.tX .. ", " .. msg.tY .. ", " .. msg.tZ)

            local cannons = livingCannons()
            local knownCount = 0
            for _ in pairs(cannons) do knownCount = knownCount + 1 end
            print("> " .. knownCount .. " cannon(s) known to battery.")

            -- 1. Calculate a solution for every registered cannon.
            local viableCannons = {}
            local maxFuze = 0

            for cid, data in pairs(cannons) do
                local dx = msg.tX - data.x
                local dz = msg.tZ - data.z
                local distXZ = math.sqrt(dx^2 + dz^2)

                local pitch, airtime, status = findBestPitch(
                    distXZ, msg.tY, data.y, msg.charges, data.barrelLength, msg.tier, msg.highArc
                )

                if status == "OK" then
                    local yaw = (math.deg(math.atan2(-dx, dz)) + data.yawOffset) % 360
                    viableCannons[cid] = {yaw = yaw, pitch = pitch}
                    if airtime > maxFuze then maxFuze = airtime end
                else
                    print("  ! Cannon " .. cid .. " cannot hit target (" .. status .. ").")
                end
            end

            -- 2. Report back to the Commander.
            local viableCount = 0
            for _ in pairs(viableCannons) do viableCount = viableCount + 1 end

            rednet.send(senderId, {cmd = "STRIKE_REP", count = viableCount, fuze = math.floor(maxFuze)}, "CBC_DIRECTOR")

            if viableCount > 0 then
                -- 3. Await Assemble Command.
                local _, conf = rednet.receive("CBC_DIRECTOR")
                if conf.cmd == "EXECUTE" then
                    print("> Assembling Battery...")
                    for cid in pairs(viableCannons) do rednet.send(cid, {cmd = "ASSEMBLE"}, "CBC_ARTILLERY") end
                    os.sleep(1)

                    print("> Aiming Battery...")
                    lockedIds = {}
                    for cid, sol in pairs(viableCannons) do
                        rednet.send(cid, {cmd = "AIM", yaw = sol.yaw, pitch = sol.pitch}, "CBC_ARTILLERY")
                    end

                    -- 4. Wait for all to report LOCKED (populated by cannonListener,
                    --    running in parallel, so this never blocks the roster feed).
                    local lockedCount = 0
                    while lockedCount < viableCount do
                        local newCount = 0
                        for cid in pairs(viableCannons) do
                            if lockedIds[cid] then newCount = newCount + 1 end
                        end
                        if newCount ~= lockedCount then
                            lockedCount = newCount
                            print("  - Cannon locked. (" .. lockedCount .. "/" .. viableCount .. ")")
                        end
                        os.sleep(0.1)
                    end

                    print("> ALL CANNONS LOCKED.")
                    rednet.send(senderId, {cmd = "BATTERY_READY"}, "CBC_DIRECTOR")

                    -- 5. Await Fire Command.
                    local _, fireCmd = rednet.receive("CBC_DIRECTOR")
                    if fireCmd.cmd == "FIRE" then
                        print("> FIRING BATTERY!")
                        for cid in pairs(viableCannons) do rednet.send(cid, {cmd = "FIRE"}, "CBC_ARTILLERY") end
                    end
                end
            end
        end
    end
end

parallel.waitForAny(cannonListener, directorLoop)
