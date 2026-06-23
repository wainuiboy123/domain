local im = peripheral.find("inventory_manager")
local cb = peripheral.find("chat_box")

if not im then error("inventory manager not found") end
if not cb then error("chat_box not found") end

print("Running dumper")

while true do
    local e, username, msg = os.pullEvent("chat")

    if msg == "dump" and username == "wainuiomata" then
        print("Dumping inventory slots 9-26")

        local items = im.getItems()

        for _, item in pairs(items) do
            if item.slot >= 9 and item.slot <= 26 then
                pcall(function()
                    im.removeItemFromPlayer(item, item.count)
                end)
            end
        end

        print("Done")
    end
end
