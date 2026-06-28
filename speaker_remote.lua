--====================================================--
--   MUSIC REMOTE
--   Runs on your Advanced Pocket Computer + Ender Modem.
--   Searches for music and sends it to speaker servers
--   running music_server.lua.
--
--   Save as /startup.lua on your pocket computer.
--====================================================--

local PROTOCOL       = "music_system_v1"
local API_BASE       = "https://ipod-2to6magyna-uc.a.run.app/"
local API_VERSION    = "2.1"

--========== SPEAKER SERVER IDs (CUSTOMIZE ME) ==========--
-- IDs of computers running music_server.lua.
-- Leave empty {} to broadcast to ALL computers on the network.

local SPEAKER_IDS = {
    -- 5,
    -- 8,
}
local BROADCAST = (#SPEAKER_IDS == 0)

--========== PERIPHERAL ==========--

local modem = peripheral.find("modem")
if not modem then error("No Ender Modem! Attach one to the pocket computer.", 0) end
rednet.open(peripheral.getName(modem))

--========== STATE ==========--

local W, H           = term.getSize()
local tab            = 1   -- 1=Search, 2=Queue/Status
local searchText     = nil
local searchResults  = nil
local searchLoading  = false
local searchError    = false
local selectedResult = nil   -- index into searchResults
local statusMsg      = "Ready"
local statusCol      = colours.yellow
local volume         = 1.5   -- 0.0 - 3.0
local remoteStatus   = nil   -- last status response from server
local waitingInput   = false

--========== NETWORKING ==========--

local function sendToSpeakers(msg)
    if BROADCAST then
        rednet.broadcast(msg, PROTOCOL)
    else
        for _, id in ipairs(SPEAKER_IDS) do
            rednet.send(id, msg, PROTOCOL)
        end
    end
end

local function setStatus(msg, col)
    statusMsg = msg
    statusCol = col or colours.yellow
end

local function doSearch(query)
    local url = API_BASE .. "?v=" .. API_VERSION .. "&search=" .. textutils.urlEncode(query)
    searchLoading = true
    searchResults = nil
    searchError   = false
    http.request(url)
    return url
end

--========== DRAWING ==========--

local function cls()
    term.setBackgroundColor(colours.black)
    term.clear()
    term.setCursorPos(1,1)
end

local function writeAt(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    if bg  then term.setBackgroundColor(bg)  end
    if fg  then term.setTextColor(fg)        end
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

local function drawTabs()
    fillLine(1, colours.gray)
    local tabs = { " Search ", " Controls " }
    for i, label in ipairs(tabs) do
        local x = math.floor(W / #tabs * (i - 0.5)) - math.floor(#label / 2) + 1
        local bg = (tab == i) and colours.white or colours.gray
        local fg = (tab == i) and colours.black or colours.white
        writeAt(x, 1, label, fg, bg)
    end
end

local function drawStatus()
    fillLine(H, colours.gray, statusCol, " " .. statusMsg:sub(1, W-1))
end

local function drawSearch()
    -- Search bar
    local barBg = colours.lightGray
    fillLine(3, barBg, colours.black, "  " .. (searchText or "Type to search, Enter to go..."))

    -- Results
    if searchLoading then
        writeAt(2, 5, "Searching...", colours.lightGray, colours.black)
    elseif searchError then
        writeAt(2, 5, "Network error", colours.red, colours.black)
    elseif searchResults then
        for i, result in ipairs(searchResults) do
            local y = 5 + (i-1) * 2
            if y > H - 2 then break end
            local isSelected = (i == selectedResult)
            local bg = isSelected and colours.blue or colours.black
            local fg = isSelected and colours.white or colours.white
            local fg2 = isSelected and colours.lightGray or colours.gray

            fillLine(y,   bg, fg,  "  " .. result.name:sub(1, W-3))
            if y+1 <= H-2 then
                fillLine(y+1, bg, fg2, "  " .. (result.artist or ""):sub(1, W-3))
            end
        end
    else
        writeAt(2, 5, "Search for YouTube songs or playlists", colours.gray, colours.black)
    end
end

local function drawControls()
    -- Shows current status from server and control buttons
    local row = 3
    term.setBackgroundColor(colours.black)

    if remoteStatus then
        local np = remoteStatus.now_playing
        if np then
            writeAt(2, row,   ("Now: " .. np.name):sub(1,W-1),   colours.lime,      colours.black)
            writeAt(2, row+1, ("By:  " .. (np.artist or "")):sub(1,W-1), colours.lightGray, colours.black)
        else
            writeAt(2, row, "Not playing", colours.lightGray, colours.black)
        end
        writeAt(2, row+2, "Queue: " .. (remoteStatus.queue_size or 0) .. " songs", colours.white, colours.black)
    else
        writeAt(2, row, "Press Scan to find speakers", colours.lightGray, colours.black)
    end

    -- Buttons
    local btnY = row + 5
    local col1 = 1
    local col2 = math.floor(W/2) + 1
    local bw   = math.floor(W/2)

    local function btn(x, y, w, label, bg)
        term.setCursorPos(x, y)
        term.setBackgroundColor(bg)
        term.setTextColor(colours.white)
        local pad = math.floor((w - #label) / 2)
        term.write(string.rep(" ", math.max(0, pad)) .. label .. string.rep(" ", math.max(0, w - #label - pad)))
    end

    btn(col1, btnY,   bw, "STOP",   colours.red)
    btn(col2, btnY,   W-col2+1, "SKIP",   colours.gray)
    btn(col1, btnY+2, bw, "VOL -",  colours.gray)
    btn(col2, btnY+2, W-col2+1, "VOL +",  colours.gray)
    btn(col1, btnY+4, W, "SCAN FOR SPEAKERS", colours.blue)

    -- Volume bar
    local volBarY = btnY + 6
    local volPct  = math.floor(volume / 3 * (W-2))
    writeAt(1, volBarY, "[", colours.white, colours.black)
    writeAt(2, volBarY, string.rep("=", volPct) .. string.rep("-", W-2-volPct), colours.lime, colours.black)
    writeAt(W, volBarY, "]", colours.white, colours.black)
    local volStr = string.format("Vol: %.0f%%", volume/3*100)
    writeAt(math.floor((W-#volStr)/2)+1, volBarY, volStr, colours.white, colours.black)
end

local function drawScreen()
    cls()
    drawTabs()
    if tab == 1 then
        drawSearch()
    else
        drawControls()
    end
    drawStatus()
end

--========== SONG ACTION MENU ==========--
-- When a result is selected, show Play Now / Play Next / Add to Queue

local function showSongMenu(song)
    cls()
    term.setBackgroundColor(colours.black)
    writeAt(2, 2, song.name:sub(1,W-2),       colours.white,     colours.black)
    writeAt(2, 3, (song.artist or ""):sub(1,W-2), colours.lightGray, colours.black)

    local opts = { "Play Now", "Play Next", "Add to Queue", "Cancel" }
    local actions = {
        function()
            if song.type == "playlist" and song.playlist_items then
                sendToSpeakers({ action = "play_now", song = song.playlist_items[1] })
                for i = 2, #song.playlist_items do
                    sendToSpeakers({ action = "add_queue", song = song.playlist_items[i] })
                end
                setStatus("Playing playlist: " .. song.name, colours.lime)
            else
                sendToSpeakers({ action = "play_now", song = song })
                setStatus("Playing: " .. song.name, colours.lime)
            end
        end,
        function()
            local items = (song.type == "playlist" and song.playlist_items) and song.playlist_items or { song }
            for i = #items, 1, -1 do
                sendToSpeakers({ action = "play_next", song = items[i] })
            end
            setStatus("Play next: " .. song.name, colours.yellow)
        end,
        function()
            local items = (song.type == "playlist" and song.playlist_items) and song.playlist_items or { song }
            for _, item in ipairs(items) do
                sendToSpeakers({ action = "add_queue", song = item })
            end
            setStatus("Queued: " .. song.name, colours.yellow)
        end,
        function() end,   -- cancel
    }

    for i, opt in ipairs(opts) do
        local y = 5 + (i-1) * 2
        fillLine(y, colours.gray, colours.white, "  " .. opt)
    end

    -- Wait for a click on one of the options
    while true do
        local event, _, x, y = os.pullEvent("mouse_click")
        for i = 1, #opts do
            local oy = 5 + (i-1) * 2
            if y == oy then
                actions[i]()
                return
            end
        end
    end
end

--========== CONTROLS CLICK HANDLER ==========--

local function handleControlsClick(x, y)
    local btnY = 3 + 5   -- must match drawControls
    local col2 = math.floor(W/2) + 1

    if y == btnY then
        if x < col2 then
            sendToSpeakers({ action = "stop" })
            setStatus("Stopped", colours.red)
        else
            sendToSpeakers({ action = "skip" })
            setStatus("Skipped", colours.yellow)
        end
    elseif y == btnY + 2 then
        if x < col2 then
            volume = math.max(0, volume - 0.1)
            sendToSpeakers({ action = "volume", volume = volume })
            setStatus(string.format("Volume: %.0f%%", volume/3*100), colours.yellow)
        else
            volume = math.min(3, volume + 0.1)
            sendToSpeakers({ action = "volume", volume = volume })
            setStatus(string.format("Volume: %.0f%%", volume/3*100), colours.yellow)
        end
    elseif y == btnY + 4 then
        -- Scan
        setStatus("Scanning...", colours.yellow)
        drawScreen()
        sendToSpeakers({ action = "ping" })
        local timer = os.startTimer(2)
        local found = {}
        while true do
            local ev, p1, p2, p3 = os.pullEvent()
            if ev == "rednet_message" then
                local _, msg, proto = p1, p2, p3
                if proto == PROTOCOL and type(msg) == "table" and msg.action == "pong" then
                    table.insert(found, msg)
                    remoteStatus = msg   -- use last pong as status
                end
            elseif ev == "timer" and p1 == timer then
                break
            end
        end
        if #found == 0 then
            setStatus("No speakers found!", colours.red)
        else
            local ids = {}
            for _, s in ipairs(found) do table.insert(ids, "#"..s.id) end
            setStatus("Found: " .. table.concat(ids, ", "), colours.lime)
        end
    end
end

--========== SEARCH CLICK HANDLER ==========--

local currentSearchUrl = nil

local function handleSearchClick(x, y)
    -- Search bar
    if y == 3 then
        -- Input mode
        fillLine(3, colours.white, colours.black, "  ")
        term.setCursorPos(3, 3)
        term.setBackgroundColor(colours.white)
        term.setTextColor(colours.black)
        local input = read()
        if input and #input > 0 then
            searchText = input
            currentSearchUrl = doSearch(input)
            setStatus("Searching...", colours.yellow)
        end
        drawScreen()
        return
    end

    -- Result clicks
    if searchResults then
        for i, result in ipairs(searchResults) do
            local ry = 5 + (i-1) * 2
            if y == ry or y == ry+1 then
                selectedResult = i
                drawScreen()
                sleep(0.1)
                showSongMenu(result)
                selectedResult = nil
                drawScreen()
                return
            end
        end
    end
end

--========== MAIN LOOP ==========--

drawScreen()

while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "mouse_click" then
        local _, x, y = p1, p2, p3
        -- Tab bar
        if y == 1 then
            tab = (x < W/2) and 1 or 2
            drawScreen()
        elseif tab == 1 then
            handleSearchClick(x, y)
        elseif tab == 2 then
            handleControlsClick(x, y)
            drawScreen()
        end

    elseif event == "key" then
        if p1 == keys.tab then
            tab = (tab == 1) and 2 or 1
            drawScreen()
        end

    elseif event == "http_success" then
        local url, handle = p1, p2
        if url == currentSearchUrl then
            local data = textutils.unserialiseJSON(handle.readAll())
            handle.close()
            searchResults = data
            searchLoading = false
            if not data or #data == 0 then
                searchError = true
                setStatus("No results", colours.red)
            else
                setStatus(#data .. " results", colours.lime)
            end
            drawScreen()
        end

    elseif event == "http_failure" then
        local url = p1
        if url == currentSearchUrl then
            searchError   = true
            searchLoading = false
            setStatus("Search failed", colours.red)
            drawScreen()
        end

    elseif event == "rednet_message" then
        local _, msg, proto = p1, p2, p3
        if proto == PROTOCOL and type(msg) == "table" then
            if msg.action == "ack" then
                setStatus(tostring(msg.msg), colours.lime)
                drawScreen()
            elseif msg.action == "status" then
                remoteStatus = msg
                drawScreen()
            end
        end
    end
end
