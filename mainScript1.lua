local inv = peripheral.find("inventory_manager")

if not inv then
    error("inventory_manager not found")
end

-- get all items from the bound player (memory card must already be inserted)
local items = inv.getPlayerItems()

if not items then
    error("No player linked / memory card not set correctly")
end

print("Moving items...")

for _, item in pairs(items) do
    -- item includes: name, count, slot, etc.
    local ok, err = pcall(function()
        inv.removeItemFromPlayer(
            item,      -- IMPORTANT: pass full item table, not slot number
            item.count
        )
    end)

    if not ok then
        print("Failed removing:", err)
    end
end

print("Done!")
