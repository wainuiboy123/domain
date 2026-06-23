local mon = peripheral.find("monitor")
local cb = peripheral.find("chat_box")
if not mon then
    error("No monitor found")
end

mon.setTextScale(1)

-- button data
local button = {
    name = "test",
    xmin = 2,
    xmax = 12,
    ymin = 3,
    ymax = 5,
    active = false
}

local function drawButton()
    mon.clear()

    local color = button.active and colors.lime or colors.red
    mon.setBackgroundColor(color)

    for y = button.ymin, button.ymax do
        mon.setCursorPos(button.xmin, y)
        mon.write(string.rep(" ", button.xmax - button.xmin + 1))
    end

    -- center text
    mon.setCursorPos(4, 4)
    mon.setTextColor(colors.white)
    mon.write("test")

    mon.setBackgroundColor(colors.black)
end

local function onClick()
    cb.sendMessage("test")
end

drawButton()

while true do
    local _, _, x, y = os.pullEvent("monitor_touch")

    if x >= button.xmin and x <= button.xmax and y >= button.ymin and y <= button.ymax then
        button.active = not button.active
        drawButton()
        onClick()
    end
end
