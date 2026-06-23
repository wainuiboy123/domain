local mon = peripheral.find("monitor")
local cb = peripheral.find("chat_box")

if not mon then error("No monitor found") end

mon.setTextScale(1)

local function drawFrame(x1, y1, x2, y2, color)
    mon.setBackgroundColor(color or colors.gray)

    for y = y1, y2 do
        mon.setCursorPos(x1, y)
        mon.write(string.rep(" ", x2 - x1 + 1))
    end

    mon.setBackgroundColor(colors.black)
end

local button = {
    name = "test",
    xmin = 2,
    xmax = 12,
    ymin = 3,
    ymax = 5,
    active = false
}

local function drawButton()
    local color = button.active and colors.lime or colors.red

    mon.setBackgroundColor(color)

    for y = button.ymin, button.ymax do
        mon.setCursorPos(button.xmin, y)
        mon.write(string.rep(" ", button.xmax - button.xmin + 1))
    end

    -- text
    mon.setTextColor(colors.white)
    mon.setCursorPos(5, 4)
    mon.write("test")

    mon.setBackgroundColor(colors.black)
end

local function drawUI()
    mon.clear()

    -- FRAME FIRST
    drawFrame(1, 1, 51, 3, colors.gray)

    -- BUTTON SECOND
    drawButton()
end

local function onClick()
    cb.sendMessage("test")
end

drawUI()

while true do
    local _, _, x, y = os.pullEvent("monitor_touch")

    if x >= button.xmin and x <= button.xmax and y >= button.ymin and y <= button.ymax then
        button.active = not button.active
        drawUI()
        onClick()
    end
end
