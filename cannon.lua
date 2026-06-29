--====================================================--
--   CANNON AIM CONTROL
--   For CC: Tweaked + CC:CBC
--   Requires a cannon_mount peripheral attached.
--
--   Lets you set yaw and pitch precisely, shows live
--   telemetry, and fires when you're ready.
--====================================================--

local mount = peripheral.find("cannon_mount")
if not mount then
    error("No cannon_mount peripheral found!", 0)
end

-- Enable computer control
mount.setComputerControl(true)
mount.assemble(true)

local W, H = term.getSize()

--========== STATE ==========--

local inputYaw   = ""
local inputPitch = ""
local activeField = "yaw"   -- "yaw" or "pitch"
local statusMsg  = "Ready"
local statusCol  = colours.yellow
local firing     = false

--========== HELPERS ==========--

local function setStatus(msg, col)
    statusMsg = msg
    statusCol = col or colours.yellow
end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function getInfo()
    local ok, info = pcall(function() return mount.getInfo() end)
    if ok and info then return info end
    return {}
end

--========== DRAWING ==========--

local function cls()
    term.setBackgroundColor(colours.black)
    term.clear()
end

local function writeAt(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg then term.setBackgroundColor(bg) end
    if fg then term.setTextColor(fg) end
    term.write(text)
end

local function fillLine(y, bg, fg, text)
    term.setCursorPos(1, y)
    term.setBackgroundColor(bg or colours.black)
    term.setTextColor(fg or colours.white)
    term.write(string.rep(" ", W))
    if text then
        term.setCursorPos(1, y)
        term.write(text)
    end
end

local function drawScreen()
    local info = getInfo()
    cls()

    -- Title
    fillLine(1, colours.gray, colours.white, " CANNON AIM CONTROL")
    writeAt(W - 8, 1,
        info.assembled and "ASSEMBLED" or " NO MOUNT",
        info.assembled and colours.lime or colours.red,
        colours.gray)

    -- Live telemetry
    term.setBackgroundColor(colours.black)
    writeAt(2, 3, "Live Telemetry", colours.lightGray, colours.black)
    fillLine(4, colours.black)
    writeAt(2, 4,
        string.format("Yaw:   %7.2f deg    Target: %7.2f deg",
            info.yaw or 0, info.targetYaw or 0),
        colours.white, colours.black)
    fillLine(5, colours.black)
    writeAt(2, 5,
        string.format("Pitch: %7.2f deg    Target: %7.2f deg",
            info.pitch or 0, info.targetPitch or 0),
        colours.white, colours.black)

    -- Yaw delta indicator
    local yawDelta   = (info.targetYaw   or 0) - (info.yaw   or 0)
    local pitchDelta = (info.targetPitch or 0) - (info.pitch or 0)
    fillLine(6, colours.black)
    writeAt(2, 6,
        string.format("Delta: yaw %+.2f    pitch %+.2f",
            yawDelta, pitchDelta),
        math.abs(yawDelta) < 0.5 and math.abs(pitchDelta) < 0.5
            and colours.lime or colours.orange,
        colours.black)

    -- Divider
    fillLine(7, colours.gray)

    -- Input fields
    writeAt(2, 9, "Set Yaw   (0 - 360):", colours.lightGray, colours.black)
    local yawBg = (activeField == "yaw") and colours.white or colours.gray
    local yawFg = (activeField == "yaw") and colours.black or colours.lightGray
    fillLine(10, yawBg)
    writeAt(2, 10, " " .. inputYaw .. (activeField == "yaw" and "_" or " "), yawFg, yawBg)

    writeAt(2, 12, "Set Pitch:", colours.lightGray, colours.black)
    local pitchBg = (activeField == "pitch") and colours.white or colours.gray
    local pitchFg = (activeField == "pitch") and colours.black or colours.lightGray
    fillLine(13, pitchBg)
    writeAt(2, 13, " " .. inputPitch .. (activeField == "pitch" and "_" or " "), pitchFg, pitchBg)

    -- Hint
    fillLine(15, colours.black)
    writeAt(2, 15, "Tab=switch field  Enter=apply  Backspace=del", colours.gray, colours.black)

    -- Buttons
    local fireCol = firing and colours.red or colours.gray
    local fireLabel = firing and "  FIRING...  " or "  FIRE  "
    fillLine(H-2, colours.black)
    local btnW = math.floor(W / 2) - 1

    -- APPLY button
    term.setCursorPos(1, H-1)
    term.setBackgroundColor(colours.blue)
    term.setTextColor(colours.white)
    local applyLabel = " APPLY "
    local applyPad = btnW - #applyLabel
    term.write(applyLabel .. string.rep(" ", math.max(0, applyPad)))

    -- FIRE button
    term.setBackgroundColor(fireCol)
    term.setTextColor(colours.white)
    local firePad = W - btnW - #fireLabel
    term.write(string.rep(" ", math.max(0, math.floor(firePad/2))) .. fireLabel
        .. string.rep(" ", math.max(0, W - btnW - #fireLabel - math.floor(firePad/2))))

    -- Status bar
    fillLine(H, colours.gray, statusCol, " " .. statusMsg:sub(1, W-1))
end

--========== APPLY AIM ==========--

local function applyAngles()
    local yaw   = tonumber(inputYaw)
    local pitch = tonumber(inputPitch)

    if not yaw and not pitch then
        setStatus("Enter at least one value", colours.red)
        return
    end

    if yaw then
        yaw = clamp(yaw, 0, 360)
        mount.setTargetYaw(yaw)
        setStatus(string.format("Yaw set to %.2f", yaw), colours.lime)
    end

    if pitch then
        mount.setTargetPitch(pitch)
        setStatus(string.format("Pitch set to %.2f", pitch), colours.lime)
    end

    if yaw and pitch then
        mount.setTargetAngles(yaw, pitch)
        setStatus(string.format("Yaw %.2f  Pitch %.2f", yaw, pitch), colours.lime)
    end
end

--========== INPUT HANDLING ==========--

local function handleKey(key)
    local field = (activeField == "yaw") and inputYaw or inputPitch

    if key == keys.tab then
        activeField = (activeField == "yaw") and "pitch" or "yaw"

    elseif key == keys.enter then
        applyAngles()

    elseif key == keys.backspace then
        field = field:sub(1, -2)
        if activeField == "yaw" then inputYaw = field
        else inputPitch = field end

    elseif key == keys.f then
        -- F key toggles fire
        firing = not firing
        mount.fire(firing)
        setStatus(firing and "FIRING" or "Fire stopped",
                  firing and colours.red or colours.yellow)

    elseif key == keys.up then
        -- Nudge pitch up by 0.5
        local p = tonumber(inputPitch) or (getInfo().targetPitch or 0)
        p = p + 0.5
        inputPitch = string.format("%.1f", p)
        mount.setTargetPitch(p)
        setStatus("Pitch nudged to " .. inputPitch, colours.yellow)

    elseif key == keys.down then
        local p = tonumber(inputPitch) or (getInfo().targetPitch or 0)
        p = p - 0.5
        inputPitch = string.format("%.1f", p)
        mount.setTargetPitch(p)
        setStatus("Pitch nudged to " .. inputPitch, colours.yellow)

    elseif key == keys.left then
        local y = tonumber(inputYaw) or (getInfo().targetYaw or 0)
        y = (y - 0.5 + 360) % 360
        inputYaw = string.format("%.1f", y)
        mount.setTargetYaw(y)
        setStatus("Yaw nudged to " .. inputYaw, colours.yellow)

    elseif key == keys.right then
        local y = tonumber(inputYaw) or (getInfo().targetYaw or 0)
        y = (y + 0.5) % 360
        inputYaw = string.format("%.1f", y)
        mount.setTargetYaw(y)
        setStatus("Yaw nudged to " .. inputYaw, colours.yellow)
    end

    -- Number / decimal / minus input
    local char = keys.getName(key)
    if char and (#char == 1) then
        local c = char
        -- Allow digits, dot, minus (minus only at start)
        if c:match("%d") then
            field = field .. c
            if activeField == "yaw" then inputYaw = field
            else inputPitch = field end
        elseif c == "." and not field:find("%.") then
            field = field .. "."
            if activeField == "yaw" then inputYaw = field
            else inputPitch = field end
        elseif c == "-" and #field == 0 then
            field = "-"
            if activeField == "yaw" then inputYaw = field
            else inputPitch = field end
        end
    end
end

local function handleClick(x, y)
    local btnW = math.floor(W / 2) - 1

    -- Click on yaw field
    if y == 10 then
        activeField = "yaw"
    -- Click on pitch field
    elseif y == 13 then
        activeField = "pitch"
    -- APPLY button
    elseif y == H-1 and x <= btnW then
        applyAngles()
    -- FIRE button
    elseif y == H-1 and x > btnW then
        firing = not firing
        mount.fire(firing)
        setStatus(firing and "FIRING" or "Fire stopped",
                  firing and colours.red or colours.yellow)
    end
end

--========== MAIN LOOP ==========--

-- Pre-populate input fields with current target angles
local info = getInfo()
if info.targetYaw   then inputYaw   = string.format("%.2f", info.targetYaw)   end
if info.targetPitch then inputPitch = string.format("%.2f", info.targetPitch) end

drawScreen()

-- Refresh telemetry every 0.25s even without input
local refreshTimer = os.startTimer(0.25)

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "key" then
        handleKey(p1)
        drawScreen()

    elseif event == "mouse_click" then
        handleClick(p2, p3)
        drawScreen()

    elseif event == "timer" and p1 == refreshTimer then
        -- Live telemetry refresh
        drawScreen()
        refreshTimer = os.startTimer(0.25)
    end
end
