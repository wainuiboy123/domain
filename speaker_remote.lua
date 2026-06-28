--====================================================--v2
--   MUSIC REMOTE
--   Runs on your Advanced Pocket Computer + Ender Modem.
--   Mirrors the look & feel of music_server.lua, but
--   sends rednet commands to speaker servers instead of
--   playing audio locally.
--
--   Save as /startup.lua on your pocket computer.
--====================================================--

local PROTOCOL    = "music_system_v1"
local API_BASE    = "https://ipod-2to6magyna-uc.a.run.app/"
local API_VERSION = "2.1"

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
-- Mirrors music_server.lua's state as closely as possible. Since this
-- computer has no speakers, "playing" / "now_playing" / "queue" / etc.
-- are a *mirror* of the remote server's state, kept in sync via
-- "status" rednet messages broadcast back from music_server.lua.

local width, height = term.getSize()
local tab = 1   -- 1 = Now Playing, 2 = Search

local waiting_for_input = false
local last_search       = nil
local last_search_url   = nil
local search_results    = nil
local search_error      = false
local in_search_result  = false
local clicked_result    = nil

local playing     = false
local queue       = {}
local now_playing = nil
local looping     = 0
local volume      = 1.5

local is_loading = false
local is_error   = false

local have_status = false   -- have we heard from any speaker server yet?

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

--========== DRAWING ==========--
-- Laid out to match music_server.lua's drawNowPlaying / drawSearch
-- as closely as possible.

function redrawScreen()
    if waiting_for_input then
        return
    end

    term.setCursorBlink(false)
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Top tabs
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.clearLine()

    local tabs = { " Now Playing ", " Search " }

    for i = 1, #tabs, 1 do
        if tab == i then
            term.setTextColor(colors.black)
            term.setBackgroundColor(colors.white)
        else
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.gray)
        end

        term.setCursorPos((math.floor((width / #tabs) * (i - 0.5))) - math.ceil(#tabs[i] / 2) + 1, 1)
        term.write(tabs[i])
    end

    if tab == 1 then
        drawNowPlaying()
    elseif tab == 2 then
        drawSearch()
    end
end

function drawNowPlaying()
    if now_playing ~= nil then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.setCursorPos(2, 3)
        term.write(now_playing.name)
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, 4)
        term.write(now_playing.artist or "")
    else
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lightGray)
        term.setCursorPos(2, 3)
        if have_status then
            term.write("Not playing")
        else
            term.write("Press Scan to find speakers")
        end
    end

    if is_loading == true then
        term.setTextColor(colors.gray)
        term.setBackgroundColor(colors.black)
        term.setCursorPos(2, 5)
        term.write("Loading...")
    elseif is_error == true then
        term.setTextColor(colors.red)
        term.setBackgroundColor(colors.black)
        term.setCursorPos(2, 5)
        term.write("Network error")
    end

    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.gray)

    if playing then
        term.setCursorPos(2, 6)
        term.write(" Stop ")
    else
        if now_playing ~= nil or #queue > 0 then
            term.setTextColor(colors.white)
            term.setBackgroundColor(colors.gray)
        else
            term.setTextColor(colors.lightGray)
            term.setBackgroundColor(colors.gray)
        end
        term.setCursorPos(2, 6)
        term.write(" Play ")
    end

    if now_playing ~= nil or #queue > 0 then
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.gray)
    else
        term.setTextColor(colors.lightGray)
        term.setBackgroundColor(colors.gray)
    end
    term.setCursorPos(2 + 7, 6)
    term.write(" Skip ")

    if looping ~= 0 then
        term.setTextColor(colors.black)
        term.setBackgroundColor(colors.white)
    else
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.gray)
    end
    term.setCursorPos(2 + 7 + 7, 6)
    if looping == 0 then
        term.write(" Loop Off ")
    elseif looping == 1 then
        term.write(" Loop Queue ")
    else
        term.write(" Loop Song ")
    end

    term.setCursorPos(2, 8)
    paintutils.drawBox(2, 8, 25, 8, colors.gray)
    local barWidth = math.floor(24 * (volume / 3) + 0.5) - 1
    if not (barWidth == -1) then
        paintutils.drawBox(2, 8, 2 + barWidth, 8, colors.white)
    end
    if volume < 0.6 then
        term.setCursorPos(2 + barWidth + 2, 8)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
    else
        term.setCursorPos(2 + barWidth - 3 - (volume == 3 and 1 or 0), 8)
        term.setBackgroundColor(colors.white)
        term.setTextColor(colors.black)
    end
    term.write(math.floor(100 * (volume / 3) + 0.5) .. "%")

    -- "Scan" button (remote-specific addition, since we have no local
    -- speakers and need a way to discover/refresh server state)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(2, 9)
    term.clearLine()
    term.setCursorPos(2, 9)
    term.write(" Scan for speakers ")

    if #queue > 0 then
        term.setBackgroundColor(colors.black)
        for i = 1, #queue do
            term.setTextColor(colors.white)
            term.setCursorPos(2, 11 + (i - 1) * 2)
            term.write(queue[i].name)
            term.setTextColor(colors.lightGray)
            term.setCursorPos(2, 12 + (i - 1) * 2)
            term.write(queue[i].artist or "")
        end
    end
end

function drawSearch()
    -- Search bar
    paintutils.drawFilledBox(2, 3, width - 1, 5, colors.lightGray)
    term.setBackgroundColor(colors.lightGray)
    term.setCursorPos(3, 4)
    term.setTextColor(colors.black)
    term.write(last_search or "Search...")

    -- Search results
    if search_results ~= nil then
        term.setBackgroundColor(colors.black)
        for i = 1, #search_results do
            term.setTextColor(colors.white)
            term.setCursorPos(2, 7 + (i - 1) * 2)
            term.write(search_results[i].name)
            term.setTextColor(colors.lightGray)
            term.setCursorPos(2, 8 + (i - 1) * 2)
            term.write(search_results[i].artist or "")
        end
    else
        term.setCursorPos(2, 7)
        term.setBackgroundColor(colors.black)
        if search_error == true then
            term.setTextColor(colors.red)
            term.write("Network error")
        elseif last_search_url ~= nil then
            term.setTextColor(colors.lightGray)
            term.write("Searching...")
        else
            term.setCursorPos(1, 7)
            term.setTextColor(colors.lightGray)
            print("Tip: You can paste YouTube video or playlist links.")
        end
    end

    -- Fullscreen song options
    if in_search_result == true then
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setCursorPos(2, 2)
        term.setTextColor(colors.white)
        term.write(search_results[clicked_result].name)
        term.setCursorPos(2, 3)
        term.setTextColor(colors.lightGray)
        term.write(search_results[clicked_result].artist or "")

        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)

        term.setCursorPos(2, 6)
        term.clearLine()
        term.write("Play now")

        term.setCursorPos(2, 8)
        term.clearLine()
        term.write("Play next")

        term.setCursorPos(2, 10)
        term.clearLine()
        term.write("Add to queue")

        term.setCursorPos(2, 13)
        term.clearLine()
        term.write("Cancel")
    end
end

--========== HELPERS FOR SENDING SONGS ==========--

local function expandItems(result)
    if result.type == "playlist" and result.playlist_items then
        return result.playlist_items
    else
        return { result }
    end
end

--========== MAIN LOOPS ==========--
-- Structured like music_server.lua: a UI loop, and a network loop,
-- run together with parallel.waitForAny.

function uiLoop()
    redrawScreen()

    while true do
        if waiting_for_input then
            parallel.waitForAny(
                function()
                    term.setCursorPos(3, 4)
                    term.setBackgroundColor(colors.white)
                    term.setTextColor(colors.black)
                    local input = read()

                    if string.len(input) > 0 then
                        last_search = input
                        last_search_url = API_BASE .. "?v=" .. API_VERSION .. "&search=" .. textutils.urlEncode(input)
                        http.request(last_search_url)
                        search_results = nil
                        search_error = false
                    else
                        last_search = nil
                        last_search_url = nil
                        search_results = nil
                        search_error = false
                    end

                    waiting_for_input = false
                    os.queueEvent("redraw_screen")
                end,
                function()
                    while waiting_for_input do
                        local event, button, x, y = os.pullEvent("mouse_click")
                        if y < 3 or y > 5 or x < 2 or x > width - 1 then
                            waiting_for_input = false
                            os.queueEvent("redraw_screen")
                            break
                        end
                    end
                end
            )
        else
            parallel.waitForAny(
                function()
                    local event, button, x, y = os.pullEvent("mouse_click")

                    if button == 1 then
                        -- Tabs
                        if in_search_result == false then
                            if y == 1 then
                                if x < width / 2 then
                                    tab = 1
                                else
                                    tab = 2
                                end
                                redrawScreen()
                            end
                        end

                        if tab == 2 and in_search_result == false then
                            -- Search box click
                            if y >= 3 and y <= 5 and x >= 1 and x <= width - 1 then
                                paintutils.drawFilledBox(2, 3, width - 1, 5, colors.white)
                                term.setBackgroundColor(colors.white)
                                waiting_for_input = true
                            end

                            -- Search result click
                            if search_results then
                                for i = 1, #search_results do
                                    if y == 7 + (i - 1) * 2 or y == 8 + (i - 1) * 2 then
                                        term.setBackgroundColor(colors.white)
                                        term.setTextColor(colors.black)
                                        term.setCursorPos(2, 7 + (i - 1) * 2)
                                        term.clearLine()
                                        term.write(search_results[i].name)
                                        term.setTextColor(colors.gray)
                                        term.setCursorPos(2, 8 + (i - 1) * 2)
                                        term.clearLine()
                                        term.write(search_results[i].artist or "")
                                        sleep(0.2)
                                        in_search_result = true
                                        clicked_result = i
                                        redrawScreen()
                                    end
                                end
                            end
                        elseif tab == 2 and in_search_result == true then
                            -- Search result menu clicks (sends rednet commands
                            -- instead of playing locally)

                            term.setBackgroundColor(colors.white)
                            term.setTextColor(colors.black)

                            if y == 6 then
                                term.setCursorPos(2, 6)
                                term.clearLine()
                                term.write("Play now")
                                sleep(0.2)
                                in_search_result = false

                                local result = search_results[clicked_result]
                                local items = expandItems(result)
                                sendToSpeakers({ action = "play_now", song = items[1] })
                                for i = 2, #items do
                                    sendToSpeakers({ action = "add_queue", song = items[i] })
                                end
                            end

                            if y == 8 then
                                term.setCursorPos(2, 8)
                                term.clearLine()
                                term.write("Play next")
                                sleep(0.2)
                                in_search_result = false

                                local result = search_results[clicked_result]
                                local items = expandItems(result)
                                for i = #items, 1, -1 do
                                    sendToSpeakers({ action = "play_next", song = items[i] })
                                end
                            end

                            if y == 10 then
                                term.setCursorPos(2, 10)
                                term.clearLine()
                                term.write("Add to queue")
                                sleep(0.2)
                                in_search_result = false

                                local result = search_results[clicked_result]
                                local items = expandItems(result)
                                for _, item in ipairs(items) do
                                    sendToSpeakers({ action = "add_queue", song = item })
                                end
                            end

                            if y == 13 then
                                term.setCursorPos(2, 13)
                                term.clearLine()
                                term.write("Cancel")
                                sleep(0.2)
                                in_search_result = false
                            end

                            redrawScreen()
                        elseif tab == 1 and in_search_result == false then
                            -- Now playing tab clicks

                            if y == 6 then
                                -- Play/Stop button
                                if x >= 2 and x < 2 + 6 then
                                    if playing or now_playing ~= nil or #queue > 0 then
                                        term.setBackgroundColor(colors.white)
                                        term.setTextColor(colors.black)
                                        term.setCursorPos(2, 6)
                                        if playing then
                                            term.write(" Stop ")
                                        else
                                            term.write(" Play ")
                                        end
                                        sleep(0.2)
                                    end
                                    if playing then
                                        sendToSpeakers({ action = "stop" })
                                    else
                                        sendToSpeakers({ action = "play" })
                                    end
                                end

                                -- Skip button
                                if x >= 2 + 7 and x < 2 + 7 + 6 then
                                    if now_playing ~= nil or #queue > 0 then
                                        term.setBackgroundColor(colors.white)
                                        term.setTextColor(colors.black)
                                        term.setCursorPos(2 + 7, 6)
                                        term.write(" Skip ")
                                        sleep(0.2)

                                        sendToSpeakers({ action = "skip" })
                                    end
                                end

                                -- Loop button
                                if x >= 2 + 7 + 7 and x < 2 + 7 + 7 + 12 then
                                    if looping == 0 then
                                        looping = 1
                                    elseif looping == 1 then
                                        looping = 2
                                    else
                                        looping = 0
                                    end
                                    sendToSpeakers({ action = "loop", looping = looping })
                                end
                            end

                            if y == 8 then
                                -- Volume slider
                                if x >= 1 and x < 2 + 24 then
                                    volume = (x - 1) / 24 * 3
                                    sendToSpeakers({ action = "volume", volume = volume })
                                end
                            end

                            if y == 9 then
                                -- Scan button
                                term.setBackgroundColor(colors.gray)
                                term.setTextColor(colors.white)
                                term.setCursorPos(2, 9)
                                term.clearLine()
                                term.setCursorPos(2, 9)
                                term.write(" Scanning... ")
                                sendToSpeakers({ action = "ping" })
                            end

                            redrawScreen()
                        end
                    end
                end,
                function()
                    local event, button, x, y = os.pullEvent("mouse_drag")

                    if button == 1 then
                        if tab == 1 and in_search_result == false then
                            if y >= 7 and y <= 9 then
                                -- Volume slider
                                if x >= 1 and x < 2 + 24 then
                                    volume = (x - 1) / 24 * 3
                                    sendToSpeakers({ action = "volume", volume = volume })
                                end
                            end

                            redrawScreen()
                        end
                    end
                end,
                function()
                    local event = os.pullEvent("redraw_screen")
                    redrawScreen()
                end
            )
        end
    end
end

function httpLoop()
    while true do
        parallel.waitForAny(
            function()
                local event, url, handle = os.pullEvent("http_success")

                if url == last_search_url then
                    search_results = textutils.unserialiseJSON(handle.readAll())
                    handle.close()
                    if not search_results or #search_results == 0 then
                        search_results = nil
                        search_error = true
                    end
                    os.queueEvent("redraw_screen")
                end
            end,
            function()
                local event, url = os.pullEvent("http_failure")

                if url == last_search_url then
                    search_error = true
                    os.queueEvent("redraw_screen")
                end
            end
        )
    end
end

function netLoop()
    -- Listens for "status" broadcasts from music_server.lua and mirrors
    -- its state into our own (now_playing, queue, playing, looping, volume),
    -- the same fields drawNowPlaying() reads from.
    while true do
        local _, msg, proto = rednet.receive(PROTOCOL)
        if type(msg) == "table" then
            if msg.action == "status" or msg.action == "pong" then
                have_status = true
                if msg.now_playing ~= nil then now_playing = msg.now_playing end
                if msg.queue        ~= nil then queue        = msg.queue        end
                if msg.playing      ~= nil then playing      = msg.playing      end
                if msg.looping      ~= nil then looping      = msg.looping      end
                if msg.volume       ~= nil then volume       = msg.volume       end
                if msg.is_loading   ~= nil then is_loading   = msg.is_loading   end
                if msg.is_error     ~= nil then is_error     = msg.is_error     end
                os.queueEvent("redraw_screen")
            end
        end
    end
end

parallel.waitForAny(uiLoop, httpLoop, netLoop)
