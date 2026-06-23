local inv = peripheral.find("inventoryManager")

if not inv then
    error("Inventory Manager not found!")
end

print("Moving items...")

for slot = 1, 41 do
    local ok, err = pcall(function()
        inv.removeItemFromPlayer("down", slot)
    end)

    if not ok then
        print("Slot " .. slot .. ": " .. tostring(err))
    end
end

print("Done!")
