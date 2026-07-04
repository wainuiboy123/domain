-- ==========================================
-- NODE 1: CANNON SLAVE SERVER v19
-- (Auto-Alignment & Distributed Computing)
-- CHANGELOG v19:
--   - No longer waits to be PINGed. Broadcasts its own coordinates/ID
--     to the FDC on boot and on a heartbeat interval, so the FDC can
--     maintain a live roster without polling.
--   - Responds instantly to a REQUEST_REGISTER broadcast so a freshly
--     rebooted FDC doesn't have to wait a full heartbeat to see us.
-- ==========================================

local cannon = peripheral.find("cannon_mount")
if not cannon then
    print("FATAL: Cannon mount not found.")
    return
end
peripheral.find("modem", function(name) rednet.open(name) end)
cannon.setComputerControl(true)

-- === INDIVIDUAL CANNON STATS ===
local BARREL_LENGTH = 10
local YAW_OFFSET = 0
local RELOAD_SIDE = "bottom"
local REGISTER_INTERVAL = 5 -- seconds between heartbeat registrations
-- ===============================

local function wrapAngle(angle) return (angle + 180) % 360 - 180 end

local function sendRegistration()
    local info = cannon.getInfo()
    info.cmd = "REGISTER"
    info.barrelLength = BARREL_LENGTH
    info.yawOffset = YAW_OFFSET
    rednet.broadcast(info, "CBC_ARTILLERY")
end

term.clear()
term.setCursorPos(1,1)
print("=== BATTERY SLAVE ACTIVE ===")
print("ID: " .. os.getComputerID() .. " | REGISTERING WITH FDC")

-- Announce ourselves immediately on boot.
sendRegistration()

local function registrationLoop()
    while true do
        os.sleep(REGISTER_INTERVAL)
        sendRegistration()
    end
end

local function commandLoop()
    while true do
        local senderId, msg = rednet.receive("CBC_ARTILLERY")

        if type(msg) == "table" then
            if msg.cmd == "REQUEST_REGISTER" then
                -- An FDC just came online / wants a fresh roster right now.
                sendRegistration()

            elseif msg.cmd == "ASSEMBLE" then
                cannon.assemble(true)

            elseif msg.cmd == "AIM" then
                print("> Aiming to Yaw: " .. math.floor(msg.yaw) .. ", Pitch: " .. math.floor(msg.pitch))
                cannon.setTargetAngles(msg.yaw, msg.pitch)

                -- Distributed Computing: the cannon checks its OWN alignment.
                while true do
                    local curInfo = cannon.getInfo()
                    local curYaw = (curInfo.yaw % 360 + 360) % 360
                    local yDiff = math.abs(wrapAngle(msg.yaw - curYaw))
                    local pDiff = math.abs(msg.pitch - curInfo.pitch)

                    if yDiff <= 0.5 and pDiff <= 0.5 then
                        print("> LOCKED. Notifying FDC.")
                        rednet.send(senderId, {cmd = "LOCKED"}, "CBC_ARTILLERY")
                        break
                    end
                    os.sleep(0.1)
                end

            elseif msg.cmd == "FIRE" then
                print("> EXECUTING FIRE MISSION!")
                cannon.fire(true)
                os.sleep(1.0)
                cannon.fire(false)

                os.sleep(1.0)
                cannon.assemble(false)
                os.sleep(0.5)
                redstone.setOutput(RELOAD_SIDE, true)
                os.sleep(0.5)
                redstone.setOutput(RELOAD_SIDE, false)
            end
        end
    end
end

parallel.waitForAny(registrationLoop, commandLoop)
