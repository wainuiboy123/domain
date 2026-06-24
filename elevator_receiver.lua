--====================================================--
--   ELEVATOR RECEIVER
--   For CC: Tweaked + Advanced Peripherals
--   This is the STATIONARY half of the two-script elevator
--   system. It must NOT be on the moving structure -- place
--   it wherever your actual redstone wiring lives, with a
--   wireless or ender modem attached (matching whatever the
--   panel computer uses).
--
--   It just listens for floor requests from the panel
--   ("elevator.lua") over rednet and pulses the matching
--   redstone side for the matching duration.
--====================================================--

--========== PERIPHERAL SETUP ==========--

local modem = peripheral.find("modem")
if not modem then
    error("No wireless/ender modem connected! This receiver needs one to " ..
          "hear the panel's requests.")
end

rednet.open(peripheral.getName(modem))
print("Elevator receiver online.")
print("This receiver's computer ID is: " .. os.getComputerID())
print("Put this ID into RECEIVER_ID in elevator.lua on the panel computer.")

-- Must be the exact same string as PROTOCOL in elevator.lua.
local PROTOCOL = "elevator_panel_v1"

--========== FLOOR -> REDSTONE MAPPING (CUSTOMIZE ME) ==========--
-- side:         redstone side to pulse ("top","bottom","left","right","front","back")
-- pulseSeconds: how long the signal stays on
-- Keys here MUST match the floorId values used in elevator.lua's BUTTONS
-- list and DEFAULT_FLOOR entry.

local FLOORS = {
    ground   = { side = "top",    pulseSeconds = 1 },
    basement = { side = "bottom", pulseSeconds = 1 },
    vault    = { side = "left",   pulseSeconds = 1 },
    command  = { side = "right",  pulseSeconds = 1 },
    top      = { side = "back",   pulseSeconds = 1 },
}

--========== REDSTONE ==========--

local function pulseRedstone(side, seconds)
    redstone.setOutput(side, true)
    sleep(seconds)
    redstone.setOutput(side, false)
end

--========== MAIN LOOP ==========--

local function main()
    while true do
        local senderId, message, protocol = rednet.receive(PROTOCOL)

        if type(message) == "table" and message.action == "goToFloor" then
            local floor = FLOORS[message.floorId]
            if floor then
                print("Floor request: " .. tostring(message.floorId) ..
                      " (from computer #" .. tostring(senderId) .. ")")
                pulseRedstone(floor.side, floor.pulseSeconds)

                -- Acknowledge back to the panel so it can confirm on-screen.
                rednet.send(senderId, { action = "ack", floorId = message.floorId }, PROTOCOL)
            else
                print("Unknown floorId received: " .. tostring(message.floorId))
            end
        end
    end
end

-- Watchdog: auto-restart main() if anything throws, so a momentary error
-- doesn't leave the receiver permanently unresponsive. Combined with
-- copying this file to /startup.lua, the receiver comes back on its own
-- after both server restarts and in-game crashes.
while true do
    local ok, err = pcall(main)
    if ok then
        break
    end
    print("Elevator receiver crashed: " .. tostring(err))
    print("Restarting in 3 seconds...")
    sleep(3)
end
