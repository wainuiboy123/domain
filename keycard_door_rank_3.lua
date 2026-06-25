--====================================================--
--   RANK-GATED REDSTONE TOGGLE
--   For CC: Tweaked + Advanced Peripherals
--
--   Requires:
--     - a player_detector peripheral attached to this computer
--     - an Ender Modem (for Discord HTTP — or just HTTP enabled)
--
--   When a player right-clicks the detector:
--     - Their rank is fetched from Discord
--     - If they meet REQUIRED_RANK, the redstone on all sides toggles
--     - If they don't, nothing happens
--
--   Save as /startup.lua to auto-run on boot.
--====================================================--

--========== CONFIG (CUSTOMIZE ME) ==========--

-- Minimum rank level required to toggle the redstone output.
-- (-1 Blacklisted, 0/1 Visitor, 2 Recruit, 3 Member,
--   4 Officer, 5 Senior Officer, 6 Command)
local REQUIRED_RANK = 3

-- Discord webhook + rank message ID (same as elevator script)
local WEBHOOK_URL  = "https://discord.com/api/webhooks/1519150777174724640/5RcOy3OPeehsFBw1wgHhxgszeLRkIKDufW4sg64QCe1kLHqYuR5nOv4JRTO8xZPd8mhF"
local MESSAGE_ID   = "1519151496346730529"

-- How long (seconds) the rank cache stays fresh before re-fetching
local RANK_CACHE_SEC = 15

-- HTTP timeout: if we don't get a response within this many seconds, restart
local HTTP_TIMEOUT_SEC = 3

--========== RANK DEFINITIONS ==========--

local RANKS = {
    [-1] = "Blacklisted",
    [0]  = "Visitor",
    [1]  = "Visitor",
    [2]  = "Recruit",
    [3]  = "Member",
    [4]  = "Officer",
    [5]  = "Senior Officer",
    [6]  = "Command",
}
local MIN_RANK = -1
local MAX_RANK = 6

-- All redstone sides to pulse
local REDSTONE_SIDES = { "top", "bottom", "left", "right", "front", "back" }

--========== PERIPHERAL SETUP ==========--

local detector = peripheral.find("player_detector")
if not detector then
    error("No player_detector found! Attach one to this computer.")
end

print("=== Rank-Gated Redstone Toggle ===")
print("Computer ID   : " .. os.getComputerID())
print("Required rank : " .. (RANKS[REQUIRED_RANK] or tostring(REQUIRED_RANK))
      .. " (level " .. REQUIRED_RANK .. "+)")
print("Waiting for players...")

--========== STATE ==========--

local redstoneOn    = false   -- current toggle state
local rankCache     = {}      -- { [username] = level }
local rankCacheTime = -math.huge  -- force fetch on first use

--========== REDSTONE ==========--

local function setRedstone(state)
    redstoneOn = state
    for _, side in ipairs(REDSTONE_SIDES) do
        redstone.setOutput(side, state)
    end
    print("[Redstone] " .. (state and "ON" or "OFF"))
end

--========== RANK FETCHING ==========--

local function parseRanks(description)
    local data = {}
    if not description then return data end
    local block = description:match("```[^\n]*\n(.-)\n?```")
    if not block then return data end
    for line in block:gmatch("[^\n]+") do
        local name, lvl = line:match("^(.-):(-?%d+)$")
        if name and lvl then
            lvl = tonumber(lvl)
            if lvl and lvl >= MIN_RANK and lvl <= MAX_RANK and lvl ~= 0 then
                data[name] = lvl
            end
        end
    end
    return data
end

-- Fetches ranks from Discord with a hard timeout.
-- Returns true on success, false on failure/timeout.
-- On timeout/failure, the caller restarts the script.
local function fetchRanks()
    local url = WEBHOOK_URL .. "/messages/" .. MESSAGE_ID
    print("[Ranks] Fetching from Discord...")

    local ok, err = pcall(http.request, { url = url, method = "GET" })
    if not ok then
        print("[Ranks] Failed to send request: " .. tostring(err))
        return false
    end

    local deadline = os.startTimer(HTTP_TIMEOUT_SEC)
    while true do
        local event, p1, p2 = os.pullEventRaw()

        if event == "terminate" then
            error("Terminated", 0)

        elseif event == "http_success" and p1 == url then
            local handle = p2
            local body   = handle.readAll()
            local status = handle.getResponseCode()
            handle.close()

            if status ~= 200 then
                print("[Ranks] Bad HTTP status: " .. status)
                return false
            end

            local parsed = textutils.unserialiseJSON(body)
            if not (parsed and parsed.embeds and parsed.embeds[1]) then
                print("[Ranks] No embed found in message")
                return false
            end

            local newCache = parseRanks(parsed.embeds[1].description)
            local count = 0
            for k, v in pairs(newCache) do
                count = count + 1
                print("[Ranks]   " .. k .. " = " .. tostring(v))
            end

            if count == 0 then
                print("[Ranks] WARNING: 0 ranks parsed — check embed format")
                print("[Ranks] Desc: " .. tostring(parsed.embeds[1].description or "nil"):sub(1, 200))
            else
                print("[Ranks] Loaded " .. count .. " entries.")
            end

            rankCache     = newCache
            rankCacheTime = os.clock()
            return true

        elseif event == "http_failure" and p1 == url then
            print("[Ranks] HTTP request failed")
            return false

        elseif event == "timer" and p1 == deadline then
            print("[Ranks] Timed out after " .. HTTP_TIMEOUT_SEC .. "s — restarting...")
            return false

        end
        -- all other events ignored while waiting for HTTP
    end
end

-- Returns player rank, refreshing cache if stale. Returns false if fetch fails.
local function getRank(username)
    if os.clock() - rankCacheTime > RANK_CACHE_SEC then
        local ok = fetchRanks()
        if not ok then
            return nil  -- signal to caller that we need to restart
        end
    end
    return rankCache[username] or 0
end

--========== MAIN ==========--

local function main()
    -- Always do a fresh fetch on startup; restart if it fails
    local ok = fetchRanks()
    if not ok then
        return false  -- tell watchdog to restart
    end

    print("Ready — right-click the detector to toggle.")

    while true do
        local event, p1 = os.pullEvent("playerClick")
        -- p1 = username
        local username = p1

        local rank = getRank(username)
        if rank == nil then
            -- Rank fetch failed mid-session — restart
            print("[Error] Rank fetch failed, restarting...")
            return false
        end

        local rankName = RANKS[rank] or ("Level " .. tostring(rank))
        print("[Click] " .. username .. " — rank: " .. rankName .. " (" .. rank .. ")")

        if rank >= REQUIRED_RANK then
            -- Toggle
            setRedstone(not redstoneOn)
            print("[Access] " .. username .. " toggled redstone " .. (redstoneOn and "ON" or "OFF"))
        else
            print("[Denied] " .. username .. " needs rank "
                  .. (RANKS[REQUIRED_RANK] or tostring(REQUIRED_RANK))
                  .. " (has " .. rankName .. ")")
        end
    end
end

--========== WATCHDOG ==========--

-- Make sure redstone starts off
setRedstone(false)

while true do
    local ok, err = pcall(main)
    if ok then
        -- main() returned false cleanly (fetch failed) — just restart
        print("Restarting in 2 seconds...")
        sleep(2)
    else
        if tostring(err):find("Terminated") then
            -- Ctrl+T — exit cleanly
            setRedstone(false)
            break
        end
        print("Crashed: " .. tostring(err))
        print("Restarting in 2 seconds...")
        sleep(2)
    end
end
