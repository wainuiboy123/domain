local mon = peripheral.find("monitor")
if not mon then error("No monitor found") end

mon.setTextScale(1)

-- =========================
-- CORE FUNCTIONS
-- =========================

local function clearScreen(bg)
    mon.setBackgroundColor(bg or colors.black)
    mon.clear()
end

local function drawBox(x1, y1, x2, y2, color)
    mon.setBackgroundColor(color or colors.gray)

    for y = y1, y2 do
        mon.setCursorPos(x1, y)
        mon.write(string.rep(" ", x2 - x1 + 1))
    end

    mon.setBackgroundColor(colors.black)
end

local function drawBorder(x1, y1, x2, y2, color)
    mon.setTextColor(color or colors.white)

    mon.setCursorPos(x1, y1)
    mon.write(string.rep("-", x2 - x1 + 1))

    mon.setCursorPos(x1, y2)
    mon.write(string.rep("-", x2 - x1 + 1))

    for y = y1 + 1, y2 - 1 do
        mon.setCursorPos(x1, y)
        mon.write("|")
        mon.setCursorPos(x2, y)
        mon.write("|")
    end
end

local function drawText(x, y, text, color)
    mon.setTextColor(color or colors.white)
    mon.setCursorPos(x, y)
    mon.write(text)
end

local function drawCenteredText(x1, y1, x2, y2, text, color)
    mon.setTextColor(color or colors.white)

    local x = math.floor((x1 + x2 - #text) / 2) + 1
    local y = math.floor((y1 + y2) / 2)

    mon.setCursorPos(x, y)
    mon.write(text)
end

-- =========================
-- BUTTON SYSTEM
-- =========================

local buttons = {}

local function createButton(name, text, x1, y1, x2, y2)
    buttons[name] = {
        text = text,
        x1 = x1, y1 = y1,
        x2 = x2, y2 = y2,
        active = false
    }
end

local function drawButton(btn)
    local color = btn.active and colors.lime or colors.red

    drawBox(btn.x1, btn.y1, btn.x2, btn.y2, color)
    drawCenteredText(btn.x1, btn.y1, btn.x2, btn.y2, btn.text, colors.white)
end

local function drawAllButtons()
    for _, btn in pairs(buttons) do
        drawButton(btn)
    end
end

local function isInside(btn, x, y)
    return x >= btn.x1 and x <= btn.x2 and y >= btn.y1 and y <= btn.y2
end

local function handleClick(x, y)
    for name, btn in pairs(buttons) do
        if isInside(btn, x, y) then
            btn.active = not btn.active
            return name, btn
        end
    end
    return nil
end

-- =========================
-- EXAMPLE ACTION
-- =========================

local function onButtonPress(name)
    if name == "dump" then
        print("Dump button pressed")

        local im = peripheral.find("inventory_manager")
        if im then
            local items = im.getItems()
            for _, item in pairs(items) do
                if item.slot >= 9 and item.slot <= 26 then
                    im.removeItemFromPlayer(item, item.count)
                end
            end
        end
    end
end

-- =========================
-- UI SETUP
-- =========================

clearScreen()

drawBox(1, 1, 51, 3, colors.gray)
drawCenteredText(1, 1, 51, 3, "ADMIN PANEL")

createButton("dump", "DUMP", 2, 5, 12, 7)

drawAllButtons()

-- =========================
-- MAIN LOOP
-- =========================

while true do
    local _, _, x, y = os.pullEvent("monitor_touch")

    local name = handleClick(x, y)

    if name then
        clearScreen()

        drawBox(1, 1, 51, 3, colors.gray)
        drawCenteredText(1, 1, 51, 3, "ADMIN PANEL")

        drawAllButtons()

        onButtonPress(name)
    end
end
