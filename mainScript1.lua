local inv = peripheral.find("inventory_manager")

if not inv then
    error("inventory_manager not found")
end

-- get linked player inventory (THIS is the correct function in your build)
local items = inv.getInventory()

if not items then
    error("No items found / memory card not linked")
end

print("Transferring items...")

for _, item in pairs(items) do
    if item and item.count and item.slot then
        pcall(function()
            inv.removeItemFromPlayer(item, item.count)
        end)
    end
end

print("Done!")
