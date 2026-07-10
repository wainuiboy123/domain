--[[
    HOTSPOT HEATMAP
    -----------------------------------------------------------
    Tracks tracked players' positions using the Player Detector peripheral
    (type "playerDetector"), polling as fast as practically possible while
    they're online, and displays a live, connected trail/heatmap on a
    monitor (found by type, not name) using sub-pixel rendering.

    SELF-CONTAINED: pixelbox_lite (by 9551-Dev, MIT License) is embedded
    directly below. You only need this one file.

    SESSIONS & HISTORY:
      - Every time a tracked player logs in, a brand new "session" starts
        (a fresh heatmap with its own bounding box). Previous sessions are
        never modified again - they're frozen in place as history.
      - The active session autosaves every SESSION_SAVE_INTERVAL seconds,
        and gets a final save the moment the player logs out.
      - Everything (tracked players + every session's full history) is
        stored as a single blob in the "nbt_storage" peripheral. There's
        no separate file per session anymore - one block holds it all.
      - Anyone who joins and isn't already tracked gets added and started
        automatically - you don't need to "add" people by hand.

    ON-MONITOR NAVIGATION (type "watch" with no arguments):
      1. Tap a tracked player's name to see their session list.
      2. Each session shows either "LIVE" (red, still updating) or how
         long ago it was last updated plus an NZT timestamp.
      3. Tap a session to view its heatmap. Tap "< Back" (top row) to
         go up a level. Tapping anywhere else on a heatmap prints the
         approximate coordinates of the hottest pixel under your tap.

    COMMANDS:
      add <username>   - start tracking a player right now (usually
                          unnecessary - anyone who joins is auto-tracked)
      add *            - start tracking every currently online player
      remove <username>- stop tracking a player (keeps saved history)
      remove *         - stop tracking everyone
      list             - show tracked players
      watch [username] - open the on-monitor picker (or jump to a player's
                          session list directly)
      back             - go up one level in the on-monitor UI
      status           - show who's online right now
      reset <username> - wipe the CURRENT session's data (history untouched)
      exit             - quit
]]

-- ===================== EMBEDDED LIBRARY: pixelbox_lite =====================
--[[
    Vendored copy of pixelbox_lite by 9551-Dev (MIT License).
    Source: https://github.com/9551-Dev/pixelbox_lite

    MIT License

    Copyright (c) 2024 9551Dev

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]
local pixelbox = (function()

local pixelbox = {initialized=false,shared_data={},internal={}}

pixelbox.url     = "https://pixels.devvie.cc"
pixelbox.license = "MIT License - Copyright (c) 2024 9551Dev - see file header"

local box_object = {}

local t_cat  = table.concat

local sampling_lookup = {
    {2,3,4,5,6},
    {4,1,6,3,5},
    {1,4,5,2,6},
    {2,6,3,5,1},
    {3,6,1,4,2},
    {4,5,2,3,1}
}

local texel_character_lookup  = load("return {"..string.rep("false,",599).."[0]=false}","=pb_preload","t")()
local texel_foreground_lookup = load("return {"..string.rep("false,",599).."[0]=false}","=pb_preload","t")()
local texel_background_lookup = load("return {"..string.rep("false,",599).."[0]=false}","=pb_preload","t")()
local to_blit = {}

pixelbox.internal.texel_character_lookup  = texel_character_lookup
pixelbox.internal.texel_foreground_lookup = texel_foreground_lookup
pixelbox.internal.texel_background_lookup = texel_background_lookup

pixelbox.internal.to_blit_lookup  = to_blit
pixelbox.internal.sampling_lookup = sampling_lookup

local function generate_identifier(s1,s2,s3,s4,s5,s6)
    return  s2 * 1 +
            s3 * 3 +
            s4 * 4 +
            s5 * 20 +
            s6 * 100
end

local function calculate_texel(v1,v2,v3,v4,v5,v6)
    local texel_data = {v1,v2,v3,v4,v5,v6}

    local state_lookup = {}
    for i=1,6 do
        local subpixel_state = texel_data[i]
        local current_count = state_lookup[subpixel_state]

        state_lookup[subpixel_state] = current_count and current_count + 1 or 1
    end

    local sortable_states = {}
    for k,v in pairs(state_lookup) do
        sortable_states[#sortable_states+1] = {
            value = k,
            count = v
        }
    end

    table.sort(sortable_states,function(a,b)
        return a.count > b.count
    end)

    local texel_stream = {}
    for i=1,6 do
        local subpixel_state = texel_data[i]

        if subpixel_state == sortable_states[1].value then
            texel_stream[i] = 1
        elseif subpixel_state == sortable_states[2].value then
            texel_stream[i] = 0
        else
            local sample_points = sampling_lookup[i]
            for sample_index=1,5 do
                local sample_subpixel_index = sample_points[sample_index]
                local sample_state          = texel_data   [sample_subpixel_index]

                local common_state_1 = sample_state == sortable_states[1].value
                local common_state_2 = sample_state == sortable_states[2].value

                if common_state_1 or common_state_2 then
                    texel_stream[i] = common_state_1 and 1 or 0

                    break
                end
            end
        end
    end

    local char_num = 128
    local stream_6 = texel_stream[6]
    if texel_stream[1] ~= stream_6 then char_num = char_num + 1  end
    if texel_stream[2] ~= stream_6 then char_num = char_num + 2  end
    if texel_stream[3] ~= stream_6 then char_num = char_num + 4  end
    if texel_stream[4] ~= stream_6 then char_num = char_num + 8  end
    if texel_stream[5] ~= stream_6 then char_num = char_num + 16 end

    local state_1,state_2
    if #sortable_states > 1 then
        state_1 = sortable_states[  stream_6+1].value
        state_2 = sortable_states[2-stream_6  ].value
    else
        state_1 = sortable_states[1].value
        state_2 = sortable_states[1].value
    end

    return char_num,state_1,state_2
end

local function base_n_rshift(n,base,shift)
    return math.floor(n/(base^shift))
end

local real_entries = 0
local function generate_lookups()
    for i = 0, 15 do
        to_blit[2^i] = ("%x"):format(i)
    end

    for encoded_pattern=0,6^6 do
        local subtexel_1 = base_n_rshift(encoded_pattern,6,0) % 6
        local subtexel_2 = base_n_rshift(encoded_pattern,6,1) % 6
        local subtexel_3 = base_n_rshift(encoded_pattern,6,2) % 6
        local subtexel_4 = base_n_rshift(encoded_pattern,6,3) % 6
        local subtexel_5 = base_n_rshift(encoded_pattern,6,4) % 6
        local subtexel_6 = base_n_rshift(encoded_pattern,6,5) % 6

        local pattern_lookup = {}
        pattern_lookup[subtexel_6] = 5
        pattern_lookup[subtexel_5] = 4
        pattern_lookup[subtexel_4] = 3
        pattern_lookup[subtexel_3] = 2
        pattern_lookup[subtexel_2] = 1
        pattern_lookup[subtexel_1] = 0

        local pattern_identifier = generate_identifier(
            pattern_lookup[subtexel_1],pattern_lookup[subtexel_2],
            pattern_lookup[subtexel_3],pattern_lookup[subtexel_4],
            pattern_lookup[subtexel_5],pattern_lookup[subtexel_6]
        )

        if not texel_character_lookup[pattern_identifier] then
            real_entries = real_entries + 1
            local character,sub_state_1,sub_state_2 = calculate_texel(
                subtexel_1,subtexel_2,
                subtexel_3,subtexel_4,
                subtexel_5,subtexel_6
            )

            local color_1_location = pattern_lookup[sub_state_1] + 1
            local color_2_location = pattern_lookup[sub_state_2] + 1

            texel_foreground_lookup[pattern_identifier] = color_1_location
            texel_background_lookup[pattern_identifier] = color_2_location

            texel_character_lookup[pattern_identifier] = string.char(character)
        end
    end
end

pixelbox.internal.generate_lookups = generate_lookups
pixelbox.internal.calculate_texel  = calculate_texel
pixelbox.internal.make_pattern_id  = generate_identifier
pixelbox.internal.base_n_rshift    = base_n_rshift

function pixelbox.make_canvas_scanline(y_coord)
    return setmetatable({},{__newindex=function(self,key,value)
        if type(key) == "number" and key%1 ~= 0 then
            error(("Tried to write a float pixel. x:%s y:%s"):format(key,y_coord),2)
        else rawset(self,key,value) end
    end})
end

function pixelbox.make_canvas(source_table)
    local dummy_OOB = pixelbox.make_canvas_scanline("NONE")
    local dummy_mt  = getmetatable(dummy_OOB)

    function dummy_mt.tostring() return "pixelbox_dummy_oob" end

    return setmetatable(source_table or {},{__index=function(_,key)
        if type(key) == "number" and key%1 ~= 0 then
            error(("Tried to write float scanline. y:%s"):format(key),2)
        end

        return dummy_OOB
    end})
end

function pixelbox.setup_canvas(box,canvas_blank,color,keep_content)
    for y=1,box.height do

        local scanline
        if not rawget(canvas_blank,y) then
            scanline = pixelbox.make_canvas_scanline(y)

            rawset(canvas_blank,y,scanline)
        else
            scanline = canvas_blank[y]
        end

        for x=1,box.width do
            if not (scanline[x] and keep_content) then
                scanline[x] = color
            end
        end
    end

    return canvas_blank
end

function pixelbox.restore(box,color,keep_existing,keep_content)
    if not keep_existing then
        local new_canvas = pixelbox.setup_canvas(box,pixelbox.make_canvas(),color)

        box.canvas = new_canvas
        box.CANVAS = new_canvas
    else
        pixelbox.setup_canvas(box,box.canvas,color,keep_content)
    end
end

local color_lookup  = {}
local texel_body    = {0,0,0,0,0,0}
function box_object:render()
    local term = self.term
    local blit_line,set_cursor = term.blit,term.setCursorPos

    local canv = self.canvas

    local char_line,fg_line,bg_line = {},{},{}

    local x_offset,y_offset = self.x_offset,self.y_offset
    local width,height      = self.width,   self.height

    local sy = 0
    for y=1,height,3 do
        sy = sy + 1
        local layer_1 = canv[y]
        local layer_2 = canv[y+1]
        local layer_3 = canv[y+2]

        local n = 0
        for x=1,width,2 do
            local xp1 = x+1
            local b1,b2,b3,b4,b5,b6 =
                layer_1[x],layer_1[xp1],
                layer_2[x],layer_2[xp1],
                layer_3[x],layer_3[xp1]

            local char,fg,bg = " ",1,b1

            local single_color = b2 == b1
                            and  b3 == b1
                            and  b4 == b1
                            and  b5 == b1
                            and  b6 == b1

            if not single_color then
                color_lookup[b6] = 5
                color_lookup[b5] = 4
                color_lookup[b4] = 3
                color_lookup[b3] = 2
                color_lookup[b2] = 1
                color_lookup[b1] = 0

                local pattern_identifier =
                    color_lookup[b2]       +
                    color_lookup[b3] * 3   +
                    color_lookup[b4] * 4   +
                    color_lookup[b5] * 20  +
                    color_lookup[b6] * 100

                local fg_location = texel_foreground_lookup[pattern_identifier]
                local bg_location = texel_background_lookup[pattern_identifier]

                texel_body[1] = b1
                texel_body[2] = b2
                texel_body[3] = b3
                texel_body[4] = b4
                texel_body[5] = b5
                texel_body[6] = b6

                fg = texel_body[fg_location]
                bg = texel_body[bg_location]

                char = texel_character_lookup[pattern_identifier]
            end

            n = n + 1
            char_line[n] = char
            fg_line  [n] = to_blit[fg]
            bg_line  [n] = to_blit[bg]
        end

        set_cursor(1+x_offset,sy+y_offset)
        blit_line(
            t_cat(char_line,""),
            t_cat(fg_line,  ""),
            t_cat(bg_line,  "")
        )
    end
end

function box_object:clear(color)
    pixelbox.restore(self,to_blit[color or ""] and color or self.background,true,false)
end

function box_object:set_pixel(x,y,color)
    self.canvas[y][x] = color
end

function box_object:set_canvas(canvas)
    self.canvas = canvas
    self.CANVAS = canvas
end

function box_object:resize(w,h,color)
    self.term_width  = math.floor(w+0.5)
    self.term_height = math.floor(h+0.5)
    self.width       = math.floor(w+0.5)*2
    self.height      = math.floor(h+0.5)*3

    pixelbox.restore(self,color or self.background,true,true)
end

function pixelbox.module_error(module,str,level,supress_error)
    level = level or 1

    if module.__contact and not supress_error then
        local _,err_msg = pcall(error,str,level+2)
        printError(err_msg)
        error((module.__report_msg or "\nReport module issue at:\n-> __contact"):gsub("[%w_]+",module),0)
    elseif not supress_error then
        error(str,level+1)
    end
end

function box_object:load_module(modules)
    for k,module in ipairs(modules or {}) do
        local module_data = {
            __author     = module.author,
            __name       = module.name,
            __contact    = module.contact,
            __report_msg = module.report_msg
        }

        local module_fields,magic_methods = module.init(self,module_data,pixelbox,pixelbox.shared_data,pixelbox.initialized,modules)

        magic_methods    = magic_methods or {}
        module_data.__fn = module_fields


        if self.modules[module.id] and not modules.force then
            pixelbox.module_error(module_data,("Module ID conflict: %q"):format(module.id),2,modules.supress)
        else
            self.modules[module.id] = module_data
            if magic_methods.verified_load then
                magic_methods.verified_load()
            end
        end

        for fn_name in pairs(module_fields) do
            if self.modules.module_functions[fn_name] and not modules.force then
                pixelbox.module_error(module_data,("Module %q tried to register already existing element: %q"):format(module.id,fn_name),2,modules.supress)
            else
                self.modules.module_functions[fn_name] = {
                    id   = module.id,
                    name = fn_name
                }
            end
        end
    end
end

function pixelbox.new(terminal,bg,modules)
    local box = {
        modules = {module_functions={}}
    }

    box.background = bg or terminal.getBackgroundColor()

    local w,h = terminal.getSize()
    box.term  = terminal

    setmetatable(box,{__index = function(_,key)
        local module_fn = rawget(box.modules.module_functions,key)
        if module_fn then
            return box.modules[module_fn.id].__fn[module_fn.name]
        end

        return rawget(box_object,key)
    end})

    box.__pixelbox_lite = true

    box.term_width  = w
    box.term_height = h
    box.width       = w*2
    box.height      = h*3

    box.x_offset = 0
    box.y_offset = 0

    pixelbox.restore(box,box.background)

    if type(modules) == "table" then
        box:load_module(modules)
    end

    if not pixelbox.initialized then
        generate_lookups()

        pixelbox.initialized = true
    end

    return box
end

return pixelbox

end)()
-- ===================== END EMBEDDED LIBRARY =====================

-- ===================== CONFIG =====================
local POLL_INTERVAL          = 0.05  -- seconds between position checks (~1 tick)
local RENDER_INTERVAL        = 0.15  -- seconds between monitor blits while watching a live session
local FULL_RECOLOR_INTERVAL  = 1.0   -- seconds between full-canvas repaints (cell colors
                                      -- depend on the current max count, which drifts)
local SESSION_SAVE_INTERVAL  = 10    -- seconds between autosaves of the active session to disk
local MAX_SAMPLES            = 20000 -- cap on stored raw points per player session (used only
                                      -- for rare bounding-box rebuilds, not per-render)
local LINE_MAX_GAP           = 200   -- don't draw a connecting line across jumps bigger than
                                      -- this (login, teleport, dimension change, etc.)

local GRADIENT = {
    colors.blue, colors.cyan, colors.lightBlue, colors.green,
    colors.lime, colors.yellow, colors.orange, colors.red
}
local EMPTY_COLOR = colors.black
local GRADIENT_GAMMA = 0.45
    -- Fix for hotspots not visibly going red: with a straight linear
    -- scale, one single sub-pixel a player stood AFK on for ages became
    -- the only "max", crushing every genuinely well-trodden area down
    -- near the blue end. Raising intensity to a fractional power (<1)
    -- pulls mid-range visit counts up the gradient much sooner, so a
    -- real hangout spot actually reads as orange/red instead of needing
    -- to match the single hottest pixel almost exactly.

-- ===================== PERIPHERALS =====================
-- Found by TYPE, not name - matches any peripheral reporting that type,
-- regardless of what it's actually named.
local pd = peripheral.find("player_detector")
if not pd then
    error("No player_detector found. Check it's connected to this computer.")
end

local mon = peripheral.find("monitor")
if not mon then
    error("No monitor found. Check it's connected to this computer (directly or via wired modem).")
end

-- Named "nbt_storage" specifically, per setup. All persistence (tracked
-- players + every session's full history) lives in this ONE block as a
-- single NBT blob - there's no per-file storage anymore.
local nbtStorage = peripheral.find("nbt_storage") or peripheral.find("nbtStorage")
if not nbtStorage then
    error("No NBT Storage peripheral named 'nbt_storage' found. Check it's connected to this computer.")
end

mon.setTextScale(0.5) -- smallest scale = max character resolution

-- The bottom row of the monitor is permanently reserved for a header /
-- back button in heatmap mode (easier to reach than the top on a
-- wall-mounted monitor). The heatmap itself renders into a window
-- covering everything above that row.
local MON_W, MON_H = mon.getSize()
local heatmapWindow = window.create(mon, 1, 1, MON_W, MON_H - 1)
local box = pixelbox.new(heatmapWindow)
local GRID_W, GRID_H = box.width, box.height

-- ===================== STATE =====================
-- Everything persists as ONE blob in the nbt_storage block:
--   root.players           = { [name] = true, ... }
--   root.data[name].index  = { {id=,startTime=,lastUpdate=,live=}, ... }
--   root.data[name].sessions[tostring(id)] = full session snapshot
local root = { players = {}, data = {} }
local players = root.players -- same table reference; mutating one mutates both
local sessions = {}  -- sessions[name] = the CURRENT (active or last-known) in-memory session
local uiState = { mode = "none", clickable = {} }
    -- mode: "none" | "picker" | "sessions" | "heatmap"

-- ===================== NBT STORAGE PERSISTENCE =====================
-- NOTE: writeTable() replaces the ENTIRE contents of the block every call,
-- there's no partial/keyed update - so every save writes the full history
-- of every tracked player, not just what changed. Fine for normal use, but
-- worth knowing if you end up with many players and long session histories:
-- saves will get bigger and slower over time. Pruning old sessions (not
-- implemented here) would be the fix if that ever becomes a problem.
local function loadAll()
    local ok, data = pcall(function() return nbtStorage.read() end)
    if ok and type(data) == "table" then
        root = data
        root.players = root.players or {}
        root.data = root.data or {}
    else
        root = { players = {}, data = {} }
    end
    players = root.players
end

local function saveAll()
    local ok, err = pcall(function() return nbtStorage.writeTable(root) end)
    if not ok then
        print("WARNING: failed to save to nbt_storage: " .. tostring(err))
    end
end

local function ensurePlayerData(name)
    root.data[name] = root.data[name] or { index = {}, sessions = {} }
    return root.data[name]
end

-- ===================== TIME / NZ TIMEZONE HELPERS =====================
local function epochMs()
    return os.epoch("utc")
end

-- Zeller's congruence -> 0=Sunday .. 6=Saturday
local function dayOfWeek(y, m, d)
    if m < 3 then m = m + 12; y = y - 1 end
    local K = y % 100
    local J = math.floor(y / 100)
    local h = (d + math.floor((13 * (m + 1)) / 5) + K + math.floor(K / 4) + math.floor(J / 4) + 5 * J) % 7
    return (h + 6) % 7
end

local function lastSundayOfMonth(y, m, lastDay)
    return lastDay - dayOfWeek(y, m, lastDay)
end

local function firstSundayOfMonth(y, m)
    local dow = dayOfWeek(y, m, 1)
    return 1 + ((7 - dow) % 7)
end

-- NZ daylight saving: starts last Sunday of Sept (2am), ends first Sunday
-- of April (3am). This is the current (post-2007) rule.
local function isNZDST(y, m, d, hour)
    if m == 9 then
        local lastSun = lastSundayOfMonth(y, 9, 30)
        return d > lastSun or (d == lastSun and hour >= 2)
    elseif m == 4 then
        local firstSun = firstSundayOfMonth(y, 4)
        return d < firstSun or (d == firstSun and hour < 3)
    elseif m == 10 or m == 11 or m == 12 or m == 1 or m == 2 or m == 3 then
        return true
    else
        return false -- May - Aug
    end
end

local MONTH_NAMES = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}

local function nzBreakdown(epochMillis)
    local utcSeconds = math.floor(epochMillis / 1000)
    local utc = os.date("!*t", utcSeconds)
    local dst = isNZDST(utc.year, utc.month, utc.day, utc.hour)
    local nz = os.date("!*t", utcSeconds + (dst and 13 or 12) * 3600)
    nz.isDST = dst
    return nz
end

-- e.g. "08 Jul 2026, 3:45 PM NZST"
local function nzFormat(epochMillis)
    local nz = nzBreakdown(epochMillis)
    local hour12 = nz.hour % 12
    if hour12 == 0 then hour12 = 12 end
    local ampm = nz.hour < 12 and "AM" or "PM"
    local label = nz.isDST and "NZDT" or "NZST"
    return string.format("%02d %s %04d, %d:%02d %s %s",
        nz.day, MONTH_NAMES[nz.month], nz.year, hour12, nz.min, ampm, label)
end

local function timeAgo(epochMillis)
    local diffSec = math.floor((epochMs() - epochMillis) / 1000)
    if diffSec < 5 then return "just now" end
    if diffSec < 60 then return diffSec .. "s ago" end
    local mins = math.floor(diffSec / 60)
    if mins < 60 then return mins .. "m ago" end
    local hours = math.floor(mins / 60)
    if hours < 24 then return hours .. "h ago" end
    return math.floor(hours / 24) .. "d ago"
end

-- ===================== SESSION PERSISTENCE (within the NBT blob) =====================
-- The in-memory grid is sparse and keyed by numeric col/row, which NBT's
-- list-vs-compound conversion can mangle. To keep it safe, it's flattened
-- to a single string-keyed map ("col_row" -> count) before it ever touches
-- writeTable(), and rebuilt back into nested col->row form on load.
local function loadIndex(name)
    return ensurePlayerData(name).index
end

local function upsertIndexEntry(name, entry)
    local pdata = ensurePlayerData(name)
    local found = false
    for i, e in ipairs(pdata.index) do
        if e.id == entry.id then pdata.index[i] = entry; found = true; break end
    end
    if not found then table.insert(pdata.index, entry) end
end

-- Updates the in-memory root table only. Does NOT write to the peripheral -
-- call saveAll() afterward (once, even if several sessions changed).
local function persistSession(name, s)
    local flatGrid = {}
    for col, column in pairs(s.grid) do
        for row, count in pairs(column) do
            flatGrid[col .. "_" .. row] = count
        end
    end

    local pdata = ensurePlayerData(name)
    pdata.sessions[tostring(s.id)] = {
        id = s.id, startTime = s.startTime, lastUpdate = s.lastUpdate, live = s.active,
        minX = s.minX, maxX = s.maxX, minZ = s.minZ, maxZ = s.maxZ,
        maxCount = s.maxCount, grid = flatGrid,
    }
    upsertIndexEntry(name, { id = s.id, startTime = s.startTime, lastUpdate = s.lastUpdate, live = s.active })
end

-- Finds the (at most one, in normal operation) session still flagged
-- "live" in a player's index - i.e. the session that was active at the
-- moment the script last stopped without a clean logout.
local function findLiveIndexEntry(name)
    local idx = loadIndex(name)
    for _, e in ipairs(idx) do
        if e.live then return e end
    end
    return nil
end

-- If a player is offline right now but their index still shows a live
-- session (script crashed/restarted while they were online, and they've
-- since logged out for real before we came back up), that session was
-- never properly finalized. Flip it closed so it doesn't sit there
-- showing "LIVE" in the UI forever.
local function closeDanglingLiveSessions(name)
    local pdata = ensurePlayerData(name)
    local closedAny = false
    for _, e in ipairs(pdata.index) do
        if e.live then
            e.live = false
            local raw = pdata.sessions[tostring(e.id)]
            if raw then raw.live = false end
            closedAny = true
        end
    end
    return closedAny
end

local function loadSessionData(name, id)
    local pdata = ensurePlayerData(name)
    local raw = pdata.sessions[tostring(id)]
    if not raw then return nil end

    local grid = {}
    for key, count in pairs(raw.grid or {}) do
        local colStr, rowStr = key:match("^(%-?%d+)_(%-?%d+)$")
        if colStr then
            local col, row = tonumber(colStr), tonumber(rowStr)
            grid[col] = grid[col] or {}
            grid[col][row] = count
        end
    end

    return {
        id = raw.id, startTime = raw.startTime, lastUpdate = raw.lastUpdate, live = raw.live,
        minX = raw.minX, maxX = raw.maxX, minZ = raw.minZ, maxZ = raw.maxZ,
        maxCount = raw.maxCount, grid = grid,
    }
end



-- ===================== PLAYER DETECTOR HELPERS =====================
local function tryGetPos(name)
    local ok, result = pcall(function() return pd.getPlayerPos(name) end)
    if not ok or not result then return nil end
    if type(result) == "table" and result.x then
        return result.x, result.y, result.z, result.dimension or "unknown"
    end
    return nil
end

local function getOnlinePlayerNames()
    local ok, result = pcall(function() return pd.getOnlinePlayers() end)
    if not ok or not result then return {} end
    -- Some AP versions return a list of names, others a list of tables.
    local names = {}
    for _, entry in ipairs(result) do
        if type(entry) == "string" then
            table.insert(names, entry)
        elseif type(entry) == "table" and entry.name then
            table.insert(names, entry.name)
        end
    end
    return names
end

-- ===================== SESSION (GRID) LOGIC =====================
local function newSession()
    return {
        id = nil, startTime = nil, lastUpdate = nil,
        active = false,
        minX = nil, maxX = nil, minZ = nil, maxZ = nil,
        hasPoint = false,
        samples = {},
        grid = {},
        maxCount = 0,
        dirty = {}, dirtyCount = 0,
        needsRescale = false,
        needsFullRecolor = false,
        lastX = nil, lastZ = nil, lastY = nil,
        lastCol = nil, lastRow = nil,
        legacyGridLocked = false,
            -- true only for sessions RESUMED from nbt_storage after a
            -- restart (see the startup block). Their raw sample history
            -- isn't persisted, only the aggregated grid - so for these we
            -- refuse to expand the bounding box (which would trigger a
            -- rescale that rebuilds purely from samples, wiping the
            -- resumed grid). Points outside the old box just clamp to the
            -- nearest edge instead. Fresh sessions never set this and
            -- behave exactly as before.
    }
end

local function ensureSession(name)
    if not sessions[name] then sessions[name] = newSession() end
    return sessions[name]
end

local function worldToCell(s, x, z)
    local col, row
    if s.maxX == s.minX then
        col = math.ceil(GRID_W / 2)
    else
        col = 1 + math.floor((x - s.minX) / (s.maxX - s.minX) * (GRID_W - 1) + 0.5)
    end
    if s.maxZ == s.minZ then
        row = math.ceil(GRID_H / 2)
    else
        row = 1 + math.floor((s.maxZ - z) / (s.maxZ - s.minZ) * (GRID_H - 1) + 0.5)
    end
    if col < 1 then col = 1 elseif col > GRID_W then col = GRID_W end
    if row < 1 then row = 1 elseif row > GRID_H then row = GRID_H end
    return col, row
end

local function incrementCell(s, col, row, trackDirty)
    local column = s.grid[col]
    if not column then column = {}; s.grid[col] = column end
    local newCount = (column[row] or 0) + 1
    column[row] = newCount
    if newCount > s.maxCount then s.maxCount = newCount end
    if trackDirty then
        local n = s.dirtyCount + 1
        s.dirty[n] = { col = col, row = row }
        s.dirtyCount = n
    end
end

local function bresenhamLine(s, col0, row0, col1, row1, trackDirty)
    local dx = math.abs(col1 - col0)
    local dy = -math.abs(row1 - row0)
    local sx = (col0 < col1) and 1 or -1
    local sy = (row0 < row1) and 1 or -1
    local err = dx + dy
    local col, row = col0, row0
    while true do
        incrementCell(s, col, row, trackDirty)
        if col == col1 and row == row1 then break end
        local e2 = 2 * err
        if e2 >= dy then err = err + dy; col = col + sx end
        if e2 <= dx then err = err + dx; row = row + sy end
    end
end

local function colorFor(count, maxCount)
    if count == 0 or maxCount == 0 then return EMPTY_COLOR end
    local intensity = (count / maxCount) ^ GRADIENT_GAMMA
    local idx = math.ceil(intensity * #GRADIENT)
    if idx < 1 then idx = 1 elseif idx > #GRADIENT then idx = #GRADIENT end
    return GRADIENT[idx]
end

local function rescaleSession(s)
    s.grid = {}
    s.maxCount = 0
    s.dirty = {}
    s.dirtyCount = 0
    s.lastCol, s.lastRow = nil, nil

    local samples = s.samples
    local prevCol, prevRow, prevX, prevZ

    for i = 1, #samples do
        local p = samples[i]
        local col, row = worldToCell(s, p.x, p.z)
        if prevCol then
            local dx, dz = p.x - prevX, p.z - prevZ
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist > 0 and dist <= LINE_MAX_GAP then
                bresenhamLine(s, prevCol, prevRow, col, row, false)
            else
                incrementCell(s, col, row, false)
            end
        else
            incrementCell(s, col, row, false)
        end
        prevCol, prevRow, prevX, prevZ = col, row, p.x, p.z
    end

    s.lastCol, s.lastRow = prevCol, prevRow
    s.needsRescale = false
    s.needsFullRecolor = true
end

local function recordSample(name, x, z)
    local s = ensureSession(name)
    local firstPoint = not s.hasPoint
    local expanded = false

    if firstPoint then
        s.minX, s.maxX, s.minZ, s.maxZ = x, x, z, z
    elseif not s.legacyGridLocked then
        if x < s.minX then s.minX = x; expanded = true end
        if x > s.maxX then s.maxX = x; expanded = true end
        if z < s.minZ then s.minZ = z; expanded = true end
        if z > s.maxZ then s.maxZ = z; expanded = true end
    end
    -- (a locked session just keeps its existing bounds; worldToCell()
    -- already clamps out-of-range points to the nearest edge cell, so
    -- points outside the old box still get recorded, just pinned to the
    -- boundary rather than plotted at their true position)

    table.insert(s.samples, { x = x, z = z })
    if #s.samples > MAX_SAMPLES then
        table.remove(s.samples, 1)
    end

    if expanded then
        s.needsRescale = true
    elseif not s.needsRescale then
        local col, row = worldToCell(s, x, z)
        if s.lastCol then
            local dx, dz = x - s.lastX, z - s.lastZ
            local dist = math.sqrt(dx * dx + dz * dz)
            if dist > 0 and dist <= LINE_MAX_GAP then
                bresenhamLine(s, s.lastCol, s.lastRow, col, row, true)
            else
                incrementCell(s, col, row, true)
            end
        else
            incrementCell(s, col, row, true)
        end
        s.lastCol, s.lastRow = col, row
    end

    s.hasPoint = true
    s.lastX, s.lastZ = x, z
end

-- ===================== RENDERING =====================
local function fullRecolor(s)
    if not s or not s.hasPoint then
        box:clear(EMPTY_COLOR)
        box:render()
        return
    end
    for col = 1, GRID_W do
        local column = s.grid[col]
        for row = 1, GRID_H do
            local count = column and column[row] or 0
            box.canvas[row][col] = colorFor(count, s.maxCount)
        end
    end
    s.dirty = {}
    s.dirtyCount = 0
    s.needsFullRecolor = false
    box:render()
end

local function flushDirty(s)
    if not s or s.dirtyCount == 0 then return false end
    for i = 1, s.dirtyCount do
        local d = s.dirty[i]
        local column = s.grid[d.col]
        local count = column and column[d.row] or 0
        box.canvas[d.row][d.col] = colorFor(count, s.maxCount)
    end
    s.dirty = {}
    s.dirtyCount = 0
    return true
end

local function renderStatic(data)
    if not data or not data.grid then
        box:clear(EMPTY_COLOR)
        box:render()
        return
    end
    for col = 1, GRID_W do
        local column = data.grid[col]
        for row = 1, GRID_H do
            local count = column and column[row] or 0
            box.canvas[row][col] = colorFor(count, data.maxCount)
        end
    end
    box:render()
end

local function cellToWorld(s, col, row)
    local x, z
    if s.maxX == s.minX then
        x = s.minX
    else
        x = s.minX + (col - 1) / (GRID_W - 1) * (s.maxX - s.minX)
    end
    if s.maxZ == s.minZ then
        z = s.minZ
    else
        z = s.maxZ - (row - 1) / (GRID_H - 1) * (s.maxZ - s.minZ)
    end
    return math.floor(x + 0.5), math.floor(z + 0.5)
end

-- A touch only gives a character cell (2x3 sub-pixels). Report whichever
-- of those six was visited most, falling back to the cell's center.
local function touchToCoords(s, charX, charY)
    local colStart = (charX - 1) * 2 + 1
    local rowStart = (charY - 1) * 3 + 1
    local bestCol, bestRow, bestCount = colStart, rowStart, -1
    for dc = 0, 1 do
        for dr = 0, 2 do
            local col, row = colStart + dc, rowStart + dr
            if col >= 1 and col <= GRID_W and row >= 1 and row <= GRID_H then
                local column = s.grid[col]
                local count = column and column[row] or 0
                if count > bestCount then
                    bestCount = count
                    bestCol, bestRow = col, row
                end
            end
        end
    end
    return cellToWorld(s, bestCol, bestRow)
end

-- ===================== SESSION LIFECYCLE =====================
local function createSession(name)
    local s = newSession()
    s.id = epochMs()
    s.startTime = s.id
    s.lastUpdate = s.id
    s.active = true
    sessions[name] = s
    persistSession(name, s) -- so it shows up in the session list immediately
    saveAll()
    return s
end

local function finalizeSession(name)
    local s = sessions[name]
    if s and s.active then
        if s.needsRescale then rescaleSession(s) end
        s.active = false
        s.lastUpdate = epochMs()
        persistSession(name, s)
        saveAll()
    end
end

-- ===================== ON-MONITOR UI =====================
local function clearHeader()
    mon.setBackgroundColor(colors.black)
end

local function renderPlayerPicker()
    mon.setBackgroundColor(colors.black)
    mon.clear()
    mon.setTextColor(colors.white)
    mon.setCursorPos(1, 1)
    mon.write("Tracked players (tap to view):")

    local clickable = {}
    local names = {}
    for n in pairs(players) do table.insert(names, n) end
    table.sort(names)

    -- Anchored to the bottom and growing upward, so the buttons sit
    -- within easy reach of a monitor mounted up high.
    local row = MON_H
    for _, n in ipairs(names) do
        local s = sessions[n]
        mon.setCursorPos(2, row)
        if s and s.active then
            mon.setTextColor(colors.red)
            mon.write(n .. "  LIVE")
        else
            mon.setTextColor(colors.white)
            mon.write(n)
        end
        clickable[row] = { action = "player", name = n }
        row = row - 1
    end

    if #names == 0 then
        mon.setCursorPos(2, row)
        mon.setTextColor(colors.gray)
        mon.write("(none - use 'add <name>' first)")
    end

    uiState = { mode = "picker", clickable = clickable }
end

local function renderSessionPicker(name)
    mon.setBackgroundColor(colors.black)
    mon.clear()
    mon.setTextColor(colors.white)
    mon.setCursorPos(1, 1)
    mon.write("Sessions: " .. name)

    local clickable = {}

    -- Back button anchored at the very bottom row - the single easiest
    -- spot to reach on a wall-mounted monitor.
    mon.setCursorPos(2, MON_H)
    mon.setTextColor(colors.orange)
    mon.write("< Back")
    clickable[MON_H] = { action = "back_to_picker" }

    local idx = loadIndex(name)
    table.sort(idx, function(a, b) return a.lastUpdate > b.lastUpdate end)

    local row = MON_H - 1
    for _, entry in ipairs(idx) do
        mon.setCursorPos(2, row)
        local isLive = entry.live and sessions[name] and sessions[name].id == entry.id and sessions[name].active
        if isLive then
            mon.setTextColor(colors.red)
            mon.write("LIVE *  " .. nzFormat(sessions[name].lastUpdate))
        else
            mon.setTextColor(colors.lightGray)
            mon.write(timeAgo(entry.lastUpdate) .. "  -  " .. nzFormat(entry.lastUpdate))
        end
        clickable[row] = { action = "session", name = name, entry = entry }
        row = row - 1
    end

    if #idx == 0 then
        mon.setCursorPos(2, row)
        mon.setTextColor(colors.gray)
        mon.write("(no sessions recorded yet)")
    end

    uiState = { mode = "sessions", player = name, clickable = clickable }
end

local function enterHeatmapView(name, id, entry)
    local live = sessions[name]
    local isLive = live and live.id == id and live.active

    if isLive then
        if live.needsRescale then rescaleSession(live) end
        fullRecolor(live)
    else
        local data = loadSessionData(name, id)
        if not data then
            renderSessionPicker(name)
            return
        end
        renderStatic(data)
    end

    -- Header/back button lives on the BOTTOM row (MON_H), reachable
    -- without reaching up, while the heatmap fills rows 1..MON_H-1 above it.
    mon.setBackgroundColor(colors.black)
    mon.setCursorPos(1, MON_H)
    mon.clearLine()
    if isLive then
        mon.setTextColor(colors.red)
        mon.write("< Back   " .. name .. "   LIVE * " .. nzFormat(live.lastUpdate))
    else
        mon.setTextColor(colors.lightGray)
        local when = entry and entry.lastUpdate or epochMs()
        mon.write("< Back   " .. name .. "   " .. nzFormat(when))
    end

    uiState = {
        mode = "heatmap", player = name, sessionId = id, isLive = isLive,
        clickable = { [MON_H] = { action = "back_to_sessions" } },
    }
end

-- ===================== POLLING =====================
local function pollOnce()
    for name in pairs(players) do
        local s = ensureSession(name)
        local x, y, z = tryGetPos(name)
        if x then
            if not s.active then
                -- was tracked but had no live session (e.g. added while
                -- offline, or script restarted while they were offline
                -- and they've since joined) - start one now.
                createSession(name)
                s = sessions[name]
            end
            s.lastY = y
            recordSample(name, x, z)
        else
            s.active = false
        end
    end
end

-- ===================== JOIN/LEAVE EVENTS =====================
local function joinLeaveLoop()
    while true do
        local event, username = os.pullEvent()
        if event == "playerJoin" then
            if not players[username] then
                players[username] = true
                print(username .. " joined and wasn't tracked yet - now tracking them too.")
                if uiState.mode == "picker" then renderPlayerPicker() end
            end
            createSession(username)
            print(username .. " logged in - starting new heatmap session.")
            if uiState.mode == "sessions" and uiState.player == username then
                renderSessionPicker(username)
            elseif uiState.mode == "picker" then
                renderPlayerPicker()
            end
        elseif event == "playerLeave" and players[username] then
            finalizeSession(username)
            print(username .. " logged out - session saved.")
            if uiState.mode == "heatmap" and uiState.player == username and uiState.isLive then
                uiState.isLive = false -- freeze current view; data is already final
            elseif uiState.mode == "sessions" and uiState.player == username then
                renderSessionPicker(username)
            elseif uiState.mode == "picker" then
                renderPlayerPicker()
            end
        elseif event == "hotspot_exit" then
            return
        end
    end
end

-- ===================== AUTOSAVE =====================
local function autosaveLoop()
    while true do
        local timerId = os.startTimer(SESSION_SAVE_INTERVAL)
        while true do
            local event, id = os.pullEvent()
            if event == "timer" and id == timerId then break
            elseif event == "hotspot_exit" then return end
        end
        local anyActive = false
        for name, s in pairs(sessions) do
            if s.active then
                if s.needsRescale then rescaleSession(s) end
                s.lastUpdate = epochMs()
                persistSession(name, s)
                anyActive = true
            end
        end
        if anyActive then saveAll() end -- one write covering everyone this tick,
                                         -- not one write per active player
    end
end

-- ===================== COMMANDS =====================
local function printStatus()
    for name in pairs(players) do
        local x, y, z = tryGetPos(name)
        if x then
            print(name .. ": ONLINE at (" .. x .. ", " .. y .. ", " .. z .. ")")
        else
            print(name .. ": offline")
        end
    end
end

local function addPlayer(name)
    players[name] = true
    local x = tryGetPos(name)
    if x and (not sessions[name] or not sessions[name].active) then
        createSession(name)
    end
end

local function removePlayer(name)
    finalizeSession(name)
    players[name] = nil
    sessions[name] = nil
    if uiState.player == name then
        uiState = { mode = "none", clickable = {} }
        mon.setBackgroundColor(colors.black)
        mon.clear()
    end
end

local function handleCommand(line)
    local args = {}
    for word in line:gmatch("%S+") do table.insert(args, word) end
    local cmd = args[1]

    if cmd == "add" and args[2] then
        if args[2] == "*" then
            local online = getOnlinePlayerNames()
            local added = 0
            for _, uname in ipairs(online) do
                if not players[uname] then added = added + 1 end
                addPlayer(uname)
            end
            saveAll()
            print("Tracking " .. added .. " newly added player(s); " .. #online .. " online total.")
        else
            addPlayer(args[2])
            saveAll()
            print("Now tracking " .. args[2])
        end

    elseif cmd == "remove" and args[2] then
        if args[2] == "*" then
            local names = {}
            for n in pairs(players) do table.insert(names, n) end
            for _, n in ipairs(names) do removePlayer(n) end
            saveAll()
            print("Stopped tracking all players (" .. #names .. ").")
        else
            removePlayer(args[2])
            saveAll()
            print("Stopped tracking " .. args[2])
        end

    elseif cmd == "list" then
        local any = false
        for name in pairs(players) do
            any = true
            local s = sessions[name]
            print(" - " .. name .. ((s and s.active) and "  [LIVE]" or ""))
        end
        if not any then print("No players tracked yet.") end

    elseif cmd == "watch" then
        if args[2] then
            if not players[args[2]] then
                print(args[2] .. " isn't tracked. Use 'add' first.")
            else
                renderSessionPicker(args[2])
            end
        else
            renderPlayerPicker()
        end

    elseif cmd == "back" then
        if uiState.mode == "heatmap" then
            renderSessionPicker(uiState.player)
        elseif uiState.mode == "sessions" then
            renderPlayerPicker()
        else
            print("Nothing to go back to.")
        end

    elseif cmd == "status" then
        printStatus()

    elseif cmd == "reset" and args[2] then
        local old = sessions[args[2]]
        if old then
            local s = newSession()
            s.id, s.startTime, s.active = old.id, old.startTime, old.active
            s.lastUpdate = epochMs()
            sessions[args[2]] = s
            persistSession(args[2], s)
            saveAll()
            if uiState.mode == "heatmap" and uiState.player == args[2] and uiState.isLive then
                fullRecolor(s)
            end
            print("Cleared current session data for " .. args[2])
        else
            print(args[2] .. " has no session loaded.")
        end

    elseif cmd == "exit" or cmd == "quit" then
        saveAll()
        print("Saving and exiting...")
        return false

    elseif cmd == "help" then
        print("Commands: add <n>|* | remove <n>|* | list | watch [n] | back | status | reset <n> | exit")

    else
        print("Unknown command. Type 'help' for a list of commands.")
    end

    return true
end

-- ===================== LOOPS =====================
local function commandLoop()
    print("Hotspot Heatmap running. Type 'help' for commands.")
    while true do
        write("> ")
        local line = read()
        if handleCommand(line) == false then
            os.queueEvent("hotspot_exit")
            return
        end
    end
end

local function pollLoop()
    while true do
        local timerId = os.startTimer(POLL_INTERVAL)
        while true do
            local event, id = os.pullEvent()
            if event == "timer" and id == timerId then break
            elseif event == "hotspot_exit" then return end
        end
        pollOnce()
    end
end

local function renderLoop()
    local sinceFullRecolor = 0
    while true do
        local timerId = os.startTimer(RENDER_INTERVAL)
        while true do
            local event, id = os.pullEvent()
            if event == "timer" and id == timerId then break
            elseif event == "hotspot_exit" then return end
        end

        if uiState.mode == "heatmap" and uiState.isLive then
            local s = sessions[uiState.player]
            if s and s.active then
                if s.needsRescale then rescaleSession(s) end
                sinceFullRecolor = sinceFullRecolor + RENDER_INTERVAL
                if s.needsFullRecolor or sinceFullRecolor >= FULL_RECOLOR_INTERVAL then
                    fullRecolor(s)
                    sinceFullRecolor = 0
                elseif flushDirty(s) then
                    box:render()
                end
            end
        end
    end
end

local function touchLoop()
    while true do
        local event, side, tx, ty = os.pullEvent("monitor_touch")

        if uiState.mode == "picker" then
            local action = uiState.clickable[ty]
            if action and action.action == "player" then
                renderSessionPicker(action.name)
            end

        elseif uiState.mode == "sessions" then
            local action = uiState.clickable[ty]
            if action then
                if action.action == "back_to_picker" then
                    renderPlayerPicker()
                elseif action.action == "session" then
                    enterHeatmapView(action.name, action.entry.id, action.entry)
                end
            end

        elseif uiState.mode == "heatmap" then
            if ty == MON_H then
                renderSessionPicker(uiState.player)
            else
                local s
                if uiState.isLive then
                    s = sessions[uiState.player]
                else
                    s = loadSessionData(uiState.player, uiState.sessionId)
                end
                if s then
                    local charY = ty
                    local x, z = touchToCoords(s, tx, charY)
                    print(string.format("Clicked -> approx X=%d Z=%d (%s)", x, z, uiState.player))
                end
            end
        end
    end
end

-- ===================== MAIN =====================
loadAll()

-- On a clean run this loop does almost nothing (no live sessions to
-- find). It only matters after a crash/restart while players were online:
--   - if a tracked player is online RIGHT NOW and their index still shows
--     a live session, that's almost certainly the same play session
--     interrupted by the restart - resume it (keep its grid, its bounding
--     box locked so old data can't be wiped, mark it active again) rather
--     than starting a new one and losing everything since the last
--     autosave.
--   - if a tracked player is offline but their index still shows a live
--     session, the script died mid-session and they've since logged off
--     for real - close that stale "LIVE" flag out so the UI doesn't show
--     it as live forever.
--   - anyone with no live session at all (first run, or they simply
--     aren't online) is left alone here; pollOnce()/joinLeaveLoop() will
--     start a fresh session for them the normal way if/when they're seen.
for name in pairs(players) do
    local x = tryGetPos(name)

    if x then
        local liveEntry = findLiveIndexEntry(name)
        if liveEntry then
            local data = loadSessionData(name, liveEntry.id)
            if data then
                data.active = true
                data.samples = {}
                data.dirty, data.dirtyCount = {}, 0
                data.needsRescale = false
                data.needsFullRecolor = true
                data.hasPoint = (data.minX ~= nil)
                data.lastX, data.lastZ, data.lastY = nil, nil, nil
                data.lastCol, data.lastRow = nil, nil
                data.legacyGridLocked = true -- see note above newSession()
                sessions[name] = data
                print(name .. " already online - resuming their existing live session.")
            else
                ensureSession(name)
                createSession(name)
            end
        else
            ensureSession(name)
            createSession(name)
        end
    else
        ensureSession(name)
        if closeDanglingLiveSessions(name) then
            print(name .. " has a stale live session from a previous crash - marked closed.")
        end
    end
end
saveAll() -- persist any dangling-session cleanup from the loop above

mon.setBackgroundColor(colors.black)
mon.clear()
mon.setTextColor(colors.white)
mon.setCursorPos(1, 1)
mon.write("Type 'watch' to open the player picker.")

parallel.waitForAny(commandLoop, pollLoop, renderLoop, touchLoop, joinLeaveLoop, autosaveLoop)
