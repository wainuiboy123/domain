-- ==========================================
-- NODE 3: COMMANDER (POCKET PC) v19
-- (Thin Client - all ballistics now handled by the FDC)
-- CHANGELOG v19:
--   - No longer computes any trajectory itself. Sends a STRIKE_REQ to
--     the Firemission Director (which owns the live cannon roster and
--     the physics), and just relays the human's go/no-go decisions.
-- ==========================================

peripheral.find("modem", function(name) rednet.open(name) end)

term.clear()
term.setCursorPos(1,1)
print("== POCKET ICBM UPLINK ==")

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

print("\nContacting Firemission Director...")
rednet.broadcast({
    cmd = "STRIKE_REQ",
    tX = tX, tY = tY, tZ = tZ,
    charges = charges, tier = chargeTier,
    highArc = isHighArc
}, "CBC_DIRECTOR")

local fdcId, rep = rednet.receive("CBC_DIRECTOR", 5)
if not fdcId or type(rep) ~= "table" or rep.cmd ~= "STRIKE_REP" then
    print("ERROR: No response from FDC.")
    return
end

if rep.count <= 0 then
    print("\n== NO VIABLE CANNONS ==")
    print("No registered cannon can hit that")
    print("target with the given charges/tier.")
    return
end

print("\n" .. rep.count .. " cannon(s) can hit the target.")
print("Fuze: " .. rep.fuze .. " ticks")
if isHighArc then print("Mode: HIGH-ARC MORTAR") else print("Mode: NORMAL FIRE") end

print("\n[C] Cancel, [Enter] Assemble")
if io.read() == "c" then return end

rednet.send(fdcId, {cmd = "EXECUTE"}, "CBC_DIRECTOR")

print("Awaiting battery lock...")
local _, ready = rednet.receive("CBC_DIRECTOR", 30)
if not ready or type(ready) ~= "table" or ready.cmd ~= "BATTERY_READY" then
    print("ERROR: Battery did not report ready.")
    return
end

print("\n!! BATTERY LOCKED !!")
print("Type 'FIRE' to launch:")
if io.read() == "FIRE" then
    rednet.send(fdcId, {cmd = "FIRE"}, "CBC_DIRECTOR")
    print("\n>> SPLASH INBOUND <<")
end
