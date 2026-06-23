local im = peripheral.find("inventory_manager")
local cb = peripheral.find("chat_box")

if not im then error("inventory_manager not found") end
if not cb then error("chat_box not found") end

print("Ready")

while true do
    local _, username, msg = os.pullEvent("chat")

    if msg == "dump" and username == "toastonrye" then
        print("Dumping inventory slots 9-26")

        local items = im.getItems()

        for _, item in pairs(items) do
            if item.slot >= 9 and item.slot <= 26 then
                local ok, err = pcall(function()
                    im.removeItemFromPlayer(item, item.count)
                end)

                if not ok then
                    print("Failed:", err)
                end
            end
        end

        print("Done")
    end
end
