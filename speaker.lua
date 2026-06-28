--====================================================--v1
--   MUSIC SERVER WRAPPER
--   Runs on computers with a Speaker + Ender Modem.
--   Downloads the iPod script (Rc1PCzLH) automatically,
--   then patches it to also listen for remote commands
--   from the pocket computer remote.
--
--   Save as /startup.lua on each speaker computer.
--====================================================--

local PROTOCOL   = "music_system_v1"
local IPOD_FILE  = "/ipod_player.lua"
local IPOD_PASTE = "Rc1PCzLH"

--========== PERIPHERAL SETUP ==========--

local modem = peripheral.find("modem")
if not modem then error("No Ender Modem found!", 0) end
rednet.open(peripheral.getName(modem))

local MY_ID = os.getComputerID()
print("=== Music Server ===")
print("Computer ID : " .. MY_ID)

-- Download the iPod script if not already present
if not fs.exists(IPOD_FILE) then
    print("Downloading iPod player from pastebin...")
    local ok = shell.run("pastebin", "get", IPOD_PASTE, IPOD_FILE)
    if not ok or not fs.exists(IPOD_FILE) then
        error("Failed to download iPod script!", 0)
    end
    print("Downloaded OK.")
end

-- Load the iPod script into a shared environment so we can
-- read and write its globals (queue, now_playing, playing, etc.)
local f = fs.open(IPOD_FILE, "r")
local ipodSource = f.readAll()
f.close()

local env = setmetatable({}, { __index = _ENV })

local ipodFn, loadErr = load(ipodSource, "ipod_player", "t", env)
if not ipodFn then
    error("Failed to load iPod script: " .. tostring(loadErr), 0)
end

--========== REMOTE LISTENER ==========--
-- Runs in parallel with the iPod's uiLoop/audioLoop/httpLoop.
-- Receives commands from the pocket remote and mutates the
-- iPod's state directly, then fires the events it already listens for.

local function remoteListener()
    print("[Remote] Listener ready on #" .. MY_ID)
    while true do
        local senderId, message, protocol = rednet.receive(PROTOCOL)
        if type(message) ~= "table" then
            -- ignore

        elseif message.action == "ping" then
            rednet.send(senderId, {
                action      = "pong",
                id          = MY_ID,
                playing     = env.playing or false,
                now_playing = env.now_playing,
                queue_size  = env.queue and #env.queue or 0,
            }, PROTOCOL)

        elseif message.action == "play_now" then
            local song = message.song
            if song and song.id then
                if env.speakers then
                    for _, spk in ipairs(env.speakers) do
                        pcall(function() spk.stop() end)
                        os.queueEvent("playback_stopped")
                    end
                end
                env.playing     = true
                env.now_playing = song
                env.queue       = {}
                env.playing_id  = nil
                env.is_error    = false
                env.is_loading  = false
                os.queueEvent("audio_update")
                os.queueEvent("redraw_screen")
                rednet.send(senderId, { action = "ack", msg = "Playing: " .. song.name }, PROTOCOL)
                print("[Remote] Play now: " .. song.name)
            end

        elseif message.action == "play_next" then
            local song = message.song
            if song and song.id then
                if not env.queue then env.queue = {} end
                table.insert(env.queue, 1, song)
                os.queueEvent("audio_update")
                os.queueEvent("redraw_screen")
                rednet.send(senderId, { action = "ack", msg = "Queued next: " .. song.name }, PROTOCOL)
                print("[Remote] Play next: " .. song.name)
            end

        elseif message.action == "add_queue" then
            local song = message.song
            if song and song.id then
                if not env.queue then env.queue = {} end
                table.insert(env.queue, song)
                os.queueEvent("audio_update")
                os.queueEvent("redraw_screen")
                rednet.send(senderId, { action = "ack", msg = "Queued: " .. song.name }, PROTOCOL)
                print("[Remote] Queue: " .. song.name)
            end

        elseif message.action == "stop" then
            if env.speakers then
                for _, spk in ipairs(env.speakers) do
                    pcall(function() spk.stop() end)
                    os.queueEvent("playback_stopped")
                end
            end
            env.playing    = false
            env.playing_id = nil
            env.is_loading = false
            env.is_error   = false
            os.queueEvent("audio_update")
            os.queueEvent("redraw_screen")
            rednet.send(senderId, { action = "ack", msg = "Stopped" }, PROTOCOL)
            print("[Remote] Stop")

        elseif message.action == "skip" then
            if env.speakers then
                for _, spk in ipairs(env.speakers) do
                    pcall(function() spk.stop() end)
                    os.queueEvent("playback_stopped")
                end
            end
            if env.queue and #env.queue > 0 then
                env.now_playing = env.queue[1]
                table.remove(env.queue, 1)
                env.playing_id  = nil
                env.playing     = true
            else
                env.now_playing = nil
                env.playing     = false
                env.playing_id  = nil
            end
            os.queueEvent("audio_update")
            os.queueEvent("redraw_screen")
            rednet.send(senderId, { action = "ack", msg = "Skipped" }, PROTOCOL)
            print("[Remote] Skip")

        elseif message.action == "volume" then
            if type(message.volume) == "number" then
                env.volume = math.max(0, math.min(3, message.volume))
                os.queueEvent("redraw_screen")
                rednet.send(senderId, { action = "ack", msg = "Volume: " .. env.volume }, PROTOCOL)
                print("[Remote] Volume -> " .. env.volume)
            end

        elseif message.action == "status" then
            rednet.send(senderId, {
                action      = "status",
                playing     = env.playing or false,
                now_playing = env.now_playing,
                queue_size  = env.queue and #env.queue or 0,
                volume      = env.volume or 1.5,
            }, PROTOCOL)
        end
    end
end

--========== PATCH + LAUNCH ==========--
-- The iPod script ends with:  parallel.waitForAny(uiLoop, audioLoop, httpLoop)
-- We patch env.parallel so that call also includes our remoteListener,
-- making it run as a fourth concurrent loop without touching the iPod script.

local originalParallel = parallel
env.parallel = setmetatable({}, { __index = parallel })
env.parallel.waitForAny = function(...)
    local fns = { ... }
    table.insert(fns, remoteListener)
    return originalParallel.waitForAny(table.unpack(fns))
end

print("Launching iPod player with remote control...")
print("")

while true do
    local ok, err = pcall(ipodFn)
    if not ok and not tostring(err):find("Terminated") then
        print("Crashed: " .. tostring(err))
        print("Restarting in 3s...")
        sleep(3)
        -- Reload and re-run
        ipodFn = load(fs.open(IPOD_FILE,"r"):readAll(), "ipod_player", "t", env)
    else
        break
    end
end
