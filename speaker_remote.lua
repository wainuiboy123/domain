--====================================================--v3
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

local have_status  = false   -- have we heard from any speaker server yet?
local linked_id     = nil    -- the ONE server ID we listen to after a scan
local found_servers  = {}    -- id -> last pong, collected during a scan

--========== NETWORKING ==========--
-- Commands always go out to all configured/broadcast targets (so Play/Stop/
-- etc. reach whichever server(s) you intend to control). But once `linked_id`
-- is set (via Scan), incoming STATUS/PONG messages from any OTHER id are
-- ignored - this is what stops multiple speaker servers on the network from
-- fighting over the remote's screen and flooding it with redraws.

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
    if linked_id then
        term.write(" Linked: #" .. linked_id .. " (tap to rescan) ")
    else
        term.write(" Scan for speakers ")
    end

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

--========== SERVER PICKER ==========--
-- Shown after a scan finds 2+ speaker servers, so the user picks exactly
-- ONE to link to. Returns the chosen id, or nil if cancelled.

local function chooseServer(ids, servers)
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(2, 2)
    term.setTextColor(colors.white)
    term.write("Multiple speakers found:")

    for i, id in ipairs(ids) do
        local s = servers[id]
        local label = "#" .. id
        if s.now_playing and s.now_playing.name then
            label = label .. " - " .. s.now_playing.name
        elseif s.playing == false then
            label = label .. " - idle"
        end
        local y = 4 + (i - 1) * 2
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.setCursorPos(2, y)
        term.clearLine()
        term.setCursorPos(2, y)
        term.write(label:sub(1, width - 2))
    end

    local cancelY = 4 + #ids * 2 + 1
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.setCursorPos(2, cancelY)
    term.clearLine()
    term.setCursorPos(2, cancelY)
    term.write("Cancel")

    while true do
        local event, button, x, y = os.pullEvent("mouse_click")
        for i, id in ipairs(ids) do
            local oy = 4 + (i - 1) * 2
            if y == oy then
                return id
            end
        end
        if y == cancelY then
            return nil
        end
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
                                -- Scan button: broadcast a ping, collect
                                -- pongs for a short window, then either
                                -- auto-link (1 server) or show a picker
                                -- (2+ servers) so we settle on exactly ONE
                                -- linked_id. This is what prevents multiple
                                -- speaker servers from all blasting status
                                -- updates at the remote forever.
                                term.setBackgroundColor(colors.gray)
                                term.setTextColor(colors.white)
                                term.setCursorPos(2, 9)
                                term.clearLine()
                                term.setCursorPos(2, 9)
                                term.write(" Scanning... ")

                                found_servers = {}
                                rednet.broadcast({ action = "ping" }, PROTOCOL)
                                local scanTimer = os.startTimer(1.5)
                                local scanning = true
                                while scanning do
                                    local ev, a, b, c = os.pullEvent()
                                    if ev == "rednet_message" then
                                        local senderId, msg, proto = a, b, c
                                        if proto == PROTOCOL and type(msg) == "table" and msg.action == "pong" then
                                            found_servers[senderId] = msg
                                        end
                                    elseif ev == "timer" and a == scanTimer then
                                        scanning = false
                                    end
                                end

                                local ids = {}
                                for id in pairs(found_servers) do table.insert(ids, id) end
                                table.sort(ids)

                                if #ids == 0 then
                                    linked_id = nil
                                elseif #ids == 1 then
                                    linked_id = ids[1]
                                    local s = found_servers[linked_id]
                                    have_status = true
                                    if s.now_playing ~= nil then now_playing = s.now_playing end
                                    if s.queue       ~= nil then queue       = s.queue       end
                                    if s.playing     ~= nil then playing     = s.playing     end
                                    if s.looping     ~= nil then looping     = s.looping     end
                                    if s.volume      ~= nil then volume      = s.volume      end
                                else
                                    linked_id = chooseServer(ids, found_servers)
                                    if linked_id then
                                        local s = found_servers[linked_id]
                                        have_status = true
                                        if s.now_playing ~= nil then now_playing = s.now_playing end
                                        if s.queue       ~= nil then queue       = s.queue       end
                                        if s.playing     ~= nil then playing     = s.playing     end
                                        if s.looping     ~= nil then looping     = s.looping     end
                                        if s.volume      ~= nil then volume      = s.volume      end
                                    end
                                end
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
    -- Listens for "status"/"pong" broadcasts from speaker servers and
    -- mirrors state into our own (now_playing, queue, playing, looping,
    -- volume) - the same fields drawNowPlaying() reads from.
    --
    -- Two things keep this from flashing/locking up the UI when multiple
    -- speaker servers are on the network:
    --   1. Once linked_id is set (via Scan), messages from any OTHER
    --      server id are ignored outright - only one server's status can
    --      drive the screen at a time.
    --   2. redraw_screen events are throttled: if one already came in
    --      very recently, we skip queuing another. Status updates arrive
    --      at most every ~4s per server anyway, but this also protects
    --      against bursts (e.g. several acks in a row after a command).
    local last_redraw_at = 0
    local MIN_REDRAW_GAP = 0.3   -- seconds

    while true do
        local senderId, msg, proto = rednet.receive(PROTOCOL)
        if type(msg) == "table" and (msg.action == "status" or msg.action == "pong") then
            if linked_id == nil or senderId == linked_id then
                have_status = true
                if msg.now_playing ~= nil then now_playing = msg.now_playing end
                if msg.queue        ~= nil then queue        = msg.queue        end
                if msg.playing      ~= nil then playing      = msg.playing      end
                if msg.looping      ~= nil then looping      = msg.looping      end
                if msg.volume       ~= nil then volume       = msg.volume       end
                if msg.is_loading   ~= nil then is_loading   = msg.is_loading   end
                if msg.is_error     ~= nil then is_error     = msg.is_error     end

                local now = os.clock()
                if now - last_redraw_at >= MIN_REDRAW_GAP then
                    last_redraw_at = now
                    os.queueEvent("redraw_screen")
                end
                -- If throttled, the state is still updated above; it will
                -- simply be picked up by the next redraw that does fire
                -- (e.g. the next status tick, or any user click), so
                -- nothing is lost - we just don't repaint for every single
                -- message when several arrive close together.
            end
            -- else: message from a server we're not linked to - ignored.
        end
    end
end

parallel.waitForAny(uiLoop, httpLoop, netLoop)
