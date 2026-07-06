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
print("Enter values one at a time when")
print("prompted, OR type them all on one")
print("line separated by spaces, in order:")
print("X Z Y Charges Tier Mode(1/2)")
print("------------------------")

-- Shared token buffer: if a line contains multiple values, they get
-- queued up and handed out one at a time to the remaining prompts
-- without asking again. If it only has one (or none), we just fall
-- back to prompting for the next field normally.
local tokenBuffer = {}
local function nextToken(promptText)
    while #tokenBuffer == 0 do
        print(promptText)
        local line = io.read() or ""
        for tok in line:gmatch("%S+") do table.insert(tokenBuffer, tok) end
    end
    return table.remove(tokenBuffer, 1)
end

local tX = tonumber(nextToken("Target X:"))
local tZ = tonumber(nextToken("Target Z:"))
local tY = tonumber(nextToken("Target Y (Elevation):"))
local charges = tonumber(nextToken("Number of Charges:"))
local chargeTier = tonumber(nextToken("Charge Tier (0=Base, 1-5=Mk1-5):")) or 0
local modeToken = nextToken("Fire Mode (1=Normal, 2=High-Arc):")
local isHighArc = (modeToken == "2")

if not (tX and tZ and tY and charges) then
    print("\nERROR: Missing or invalid target data.")
    print("Restart and enter numeric values.")
    return
end

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
