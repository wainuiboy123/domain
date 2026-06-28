--====================================================--v2
--   MUSIC SERVER WRAPPER
--   Runs on computers with a Speaker + Ender Modem.
--   Downloads the iPod script (Rc1PCzLH) automatically,
--   patches its state variables from `local` to shared
--   globals, then listens for remote commands from the
--   pocket computer remote and mutates that state directly.
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

--========== PATCH SOURCE: local -> shared globals ==========--
-- The iPod script declares its playback state with `local`, which means
-- it lives in the script's own closures and is INVISIBLE to anything
-- outside it - including this wrapper's remoteListener. Writing to
-- env.now_playing, env.playing, etc. from outside does nothing, because
-- the running script's functions (audioLoop, uiLoop...) never read from
-- env for these - they read their own locals.
--
-- To let the remote control these, we rewrite the specific `local NAME = X`
-- declarations into plain `NAME = X` (no "local") before loading the
-- script. With env as _ENV, a bare assignment becomes env.NAME, which is
-- now genuinely the SAME variable the iPod script's functions use,
-- because Lua resolves an unscoped identifier as _ENV.NAME when no local
-- of that name is in scope. This makes the state two-way shared.
--
-- IMPORTANT: this only works because we strip the `local` keyword from
-- the declaration BEFORE the chunk is loaded/compiled. Once compiled with
-- `local`, no outside trick can reach the variable - hence patching the
-- source text, not the loaded function.

local SHARED_VARS = {
    "playing",
    "queue",
    "now_playing",
    "looping",
    "volume",
    "playing_id",
    "last_download_url",
    "playing_status",
    "is_loading",
    "is_error",
    "speakers",
}

local function patchSource(src)
    for _, name in ipairs(SHARED_VARS) do
        -- Matches e.g. "local playing = false" / "local is_error = false;"
        -- at the start of a line (allowing leading whitespace), turning it
        -- into "playing = false". Only matches the declaration, not other
        -- uses of the word elsewhere in the script.
        local pattern = "(\n%s*)local%s+(" .. name .. "%s*=)"
        src = src:gsub(pattern, "%1%2")
    end
    -- Handle the very first line too (no leading \n before it)
    for _, name in ipairs(SHARED_VARS) do
        local pattern = "^(%s*)local%s+(" .. name .. "%s*=)"
        src = src:gsub(pattern, "%1%2")
    end
    return src
end

local f = fs.open(IPOD_FILE, "r")
local ipodSource = f.readAll()
f.close()

ipodSource = patchSource(ipodSource)

-- Load the patched script into a shared environment so we can read and
-- write its (now-global) state: queue, now_playing, playing, etc.
local env = setmetatable({}, { __index = _ENV })

local ipodFn, loadErr = load(ipodSource, "ipod_player", "t", env)
if not ipodFn then
    error("Failed to load iPod script: " .. tostring(loadErr), 0)
end

--========== REMOTE LISTENER ==========--
-- Runs in parallel with the iPod's uiLoop/audioLoop/httpLoop.
-- Receives commands from the pocket remote and mutates the
-- iPod's (now-shared) state directly, then fires the events
-- the iPod script already listens for, so its own loops pick
-- up the change exactly as if a local button had been clicked.

local function broadcastStatus()
    rednet.broadcast({
        action      = "status",
        id          = MY_ID,
        playing     = env.playing or false,
        now_playing = env.now_playing,
        queue       = env.queue or {},
        looping     = env.looping or 0,
        volume      = env.volume or 1.5,
        is_loading  = env.is_loading or false,
        is_error    = env.is_error or false,
    }, PROTOCOL)
end

local function stopSpeakers()
    if env.speakers then
        for _, spk in ipairs(env.speakers) do
            pcall(function() spk.stop() end)
        end
        os.queueEvent("playback_stopped")
    end
end

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
                queue       = env.queue or {},
                looping     = env.looping or 0,
                volume      = env.volume or 1.5,
            }, PROTOCOL)

        elseif message.action == "play" then
            -- Resume: play current now_playing, or pop from queue
            if not env.playing then
                if env.now_playing then
                    env.playing_id = nil
                    env.is_error   = false
                    env.playing    = true
                elseif env.queue and #env.queue > 0 then
                    env.now_playing = env.queue[1]
                    table.remove(env.queue, 1)
                    env.playing_id  = nil
                    env.is_error    = false
                    env.playing     = true
                end
                os.queueEvent("audio_update")
                os.queueEvent("redraw_screen")
            end
            broadcastStatus()
            print("[Remote] Play")

        elseif message.action == "play_now" then
            local song = message.song
            if song and song.id then
                stopSpeakers()
                env.playing     = true
                env.now_playing = song
                env.queue       = {}
                env.playing_id  = nil
                env.is_error    = false
                env.is_loading  = false
                os.queueEvent("audio_update")
                os.queueEvent("redraw_screen")
                broadcastStatus()
                print("[Remote] Play now: " .. song.name)
            end

        elseif message.action == "play_next" then
            local song = message.song
            if song and song.id then
                if not env.queue then env.queue = {} end
                table.insert(env.queue, 1, song)
                os.queueEvent("audio_update")
                os.queueEvent("redraw_screen")
                broadcastStatus()
                print("[Remote] Play next: " .. song.name)
            end

        elseif message.action == "add_queue" then
            local song = message.song
            if song and song.id then
                if not env.queue then env.queue = {} end
                table.insert(env.queue, song)
                os.queueEvent("audio_update")
                os.queueEvent("redraw_screen")
                broadcastStatus()
                print("[Remote] Queue: " .. song.name)
            end

        elseif message.action == "stop" then
            stopSpeakers()
            env.playing    = false
            env.playing_id = nil
            env.is_loading = false
            env.is_error   = false
            os.queueEvent("audio_update")
            os.queueEvent("redraw_screen")
            broadcastStatus()
            print("[Remote] Stop")

        elseif message.action == "skip" then
            stopSpeakers()
            if env.queue and #env.queue > 0 then
                if env.looping == 1 and env.now_playing then
                    table.insert(env.queue, env.now_playing)
                end
                env.now_playing = env.queue[1]
                table.remove(env.queue, 1)
                env.playing_id  = nil
                env.playing     = true
            else
                env.now_playing = nil
                env.playing     = false
                env.playing_id  = nil
                env.is_loading  = false
                env.is_error    = false
            end
            os.queueEvent("audio_update")
            os.queueEvent("redraw_screen")
            broadcastStatus()
            print("[Remote] Skip")

        elseif message.action == "loop" then
            if type(message.looping) == "number" then
                env.looping = message.looping
                os.queueEvent("redraw_screen")
                broadcastStatus()
                print("[Remote] Loop -> " .. env.looping)
            end

        elseif message.action == "volume" then
            if type(message.volume) == "number" then
                env.volume = math.max(0, math.min(3, message.volume))
                os.queueEvent("redraw_screen")
                broadcastStatus()
                print("[Remote] Volume -> " .. env.volume)
            end

        elseif message.action == "status" then
            broadcastStatus()
        end
    end
end

--========== PATCH + LAUNCH ==========--
-- The iPod script ends with:  parallel.waitForAny(uiLoop, audioLoop, httpLoop)
-- We patch env.parallel so that call also includes our remoteListener,
-- making it run as a fourth concurrent loop, and also periodically
-- broadcasts status so the remote stays in sync even without polling.

local originalParallel = parallel
env.parallel = setmetatable({}, { __index = parallel })
env.parallel.waitForAny = function(...)
    local fns = { ... }
    table.insert(fns, remoteListener)
    table.insert(fns, function()
        while true do
            sleep(2)
            broadcastStatus()
        end
    end)
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
        -- Reload and re-run (re-patch in case the file changed)
        local f2 = fs.open(IPOD_FILE, "r")
        local src2 = patchSource(f2.readAll())
        f2.close()
        ipodFn = load(src2, "ipod_player", "t", env)
    else
        break
    end
end
