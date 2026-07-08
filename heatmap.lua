--[[
    HOTSPOT HEATMAP (combined, optimized single-file version)
    -----------------------------------------------------------
    Tracks tracked players' positions using the Player Detector peripheral
    (type "playerDetector"), polling as fast as practically possible while
    they're online, and displays a live, connected trail/heatmap on a
    monitor (found by type, not name) using sub-pixel rendering (~6x more
    pixels than the monitor's character grid).

    SELF-CONTAINED: pixelbox_lite (by 9551-Dev, MIT License, see the
    embedded copy below) is now embedded directly in this file. You no
    longer need a separate pixelbox_lite.lua alongside this script.

    Grid layout:
      - Bottom-left pixel  = the player's most -X/-Z position seen this login
      - Top-right pixel    = the player's most +X/+Z position seen this login
      - Color goes from blue (rarely visited) to red (frequently visited)
      - The bounding box (and the whole map) rescales live as the player
        wanders further out, so it always fits their full travelled area
      - Tracking resets fresh every time the player logs back in
      - Every step is connected to the previous one with an exact line
        (Bresenham, drawn directly in the sub-pixel grid), so fast
        movement between polls still reads as a continuous trail, not
        scattered dots

    Click (right-click / "use") any spot on the monitor to print the
    approximate real-world coordinates of the hottest pixel under that
    click to this computer's terminal. (Minecraft only reports which
    character cell was touched, not the exact sub-pixel - so we report
    whichever of that cell's sub-pixels was visited most.)

    COMMANDS:
      add <username>        - start tracking a player
      remove <username>     - stop tracking a player
      list                  - show tracked players
      watch <username>      - show this player's heatmap on the monitor
      status                - show who's online right now
      reset <username>      - wipe this player's current session data
      exit                  - quit

    ------------------------------------------------------------------
    PERFORMANCE NOTES (why this version is much cheaper than the old one)
    ------------------------------------------------------------------
    OLD DESIGN: every single poll tick (~20/sec) rebuilt the ENTIRE grid
    from every stored sample (up to MAX_SAMPLES of them), then repainted
    the ENTIRE monitor canvas (every sub-pixel), then blitted. Cost grew
    with total history and ran at full poll rate regardless of whether
    anything visually significant had happened.

    NEW DESIGN:
      1. Each new position is drawn straight onto the grid with a
         Bresenham line from the previous point - O(line length), not
         O(all history). This happens every poll, and is what actually
         produces the connected trail.
      2. The grid is only fully rebuilt from raw samples when the
         player's bounding box genuinely expands (new territory seen).
         This is comparatively rare, and even then it's deferred to the
         next render pass rather than done inline on every poll, so a
         burst of expansion in one tick doesn't cause repeated rebuilds.
      3. Polling (position updates -> grid updates) is decoupled from
         rendering (grid -> monitor canvas -> blit). Rendering happens
         on its own, slower timer, since blitting to a monitor is far
         more expensive than updating a Lua table.
      4. Most render passes only repaint the handful of "dirty" cells
         that changed since the last frame, not the whole screen. A
         full recolor of every cell (needed occasionally because a
         cell's color depends on the *current* max count, which drifts
         as hotter spots emerge) runs on its own slower interval.

    Trade-off worth knowing: MAX_SAMPLES still caps how many raw points
    are kept for bounding-box rebuilds. Dropping an old sample no longer
    immediately erases its contribution from the grid (that would require
    tracking exact line paths for eviction, which isn't worth the cost
    for a heatmap) - it just won't be replayed the next time a rebuild
    happens. In practice this is invisible; it only matters for extremely
    long sessions.
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
local POLL_INTERVAL = 0.05   -- seconds between position checks (~1 game tick,
                              -- the fastest a CC:Tweaked timer can fire).
                              -- Cheap now: a poll only does a Bresenham line
                              -- into a Lua table, no monitor writes.
local RENDER_INTERVAL = 0.15 -- seconds between monitor blits (~7/sec). Far
                              -- more than a heatmap needs to look "live",
                              -- and blitting is the expensive part, so this
                              -- runs much slower than polling on purpose.
local FULL_RECOLOR_INTERVAL = 1.0
                              -- seconds between full-canvas repaints. Cell
                              -- color depends on the CURRENT max visit
                              -- count, which drifts as new hotspots emerge,
                              -- so we periodically recolor everything to
                              -- stay accurate. Between these, only cells
                              -- that actually changed get repainted.
local MAX_SAMPLES   = 20000  -- cap on stored raw points per player session
                              -- (used only for rare bounding-box rebuilds
                              -- now, not per-render, so this can be larger
                              -- than before without a performance cost).
local LINE_MAX_GAP   = 200   -- don't connect jumps bigger than this (login,
                              -- teleport, dimension change, etc.) - the
                              -- point is still recorded, just not linked
                              -- to the previous one with a line.

local PLAYERS_FILE  = "tracked_players.txt"

local GRADIENT = {
    colors.blue, colors.cyan, colors.lightBlue, colors.green,
    colors.lime, colors.yellow, colors.orange, colors.red
}
local EMPTY_COLOR = colors.black

-- ===================== PERIPHERALS =====================
-- Found by TYPE, not name - this is what actually works reliably, since
-- peripheral.wrap() needs the exact network name (which is only "monitor"
-- if you happened to name it that), while peripheral.find() matches any
-- peripheral reporting that type, regardless of its name.
local pd = peripheral.find("playerDetector")
if not pd then
    error("No player_detector found. Check it's connected to this computer.")
end

local mon = peripheral.find("monitor")
if not mon then
    error("No monitor found. Check it's connected to this computer (directly or via wired modem).")
end

mon.setTextScale(0.5) -- smallest scale = max character resolution, which
                       -- also maximizes the sub-pixel resolution below

local box = pixelbox.new(mon)
local GRID_W, GRID_H = box.width, box.height -- sub-pixel canvas size (~6x
                                              -- the character grid)

-- ===================== STATE =====================
local players = {}         -- { [name] = true }
local sessions = {}        -- sessions[name] = session table, see newSession()
local watchedPlayer = nil

-- ===================== PERSISTENCE =====================
local function loadPlayers()
    if not fs.exists(PLAYERS_FILE) then return {} end
    local f = fs.open(PLAYERS_FILE, "r")
    local contents = f.readAll()
    f.close()
    local ok, result = pcall(textutils.unserialize, contents)
    if ok and result then return result end
    return {}
end

local function savePlayers()
    local f = fs.open(PLAYERS_FILE, "w")
    f.write(textutils.serialize(players))
    f.close()
end

-- ===================== HELPERS =====================
local function tryGetPos(name)
    local ok, result = pcall(function() return pd.getPlayerPos(name) end)
    if not ok or not result then return nil end
    if type(result) == "table" and result.x then
        return result.x, result.y, result.z, result.dimension or "unknown"
    end
    return nil
end

-- A session holds everything needed to track + render one player's heatmap.
--   grid[col][row]  = visit count at that sub-pixel (sparse)
--   maxCount        = highest count currently in the grid (for color scale)
--   dirty           = list of {col=,row=} cells changed since last flush
--   samples         = capped raw (x,z) history, only replayed on rescale
--   needsRescale    = true if the bounding box grew and a full grid
--                     rebuild is owed (deferred to next render pass)
--   needsFullRecolor= true if the on-screen canvas needs a full repaint
--                     (after a rescale, or on the periodic timer)
local function newSession()
    return {
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
    }
end

local function ensureSession(name)
    if not sessions[name] then sessions[name] = newSession() end
    return sessions[name]
end

-- Map a world coordinate to a sub-pixel cell using a session's CURRENT bounds.
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
        -- flip Z so max Z (top-right requirement) ends up at the top row
        row = 1 + math.floor((s.maxZ - z) / (s.maxZ - s.minZ) * (GRID_H - 1) + 0.5)
    end
    if col < 1 then col = 1 elseif col > GRID_W then col = GRID_W end
    if row < 1 then row = 1 elseif row > GRID_H then row = GRID_H end
    return col, row
end

-- Bump one grid cell's visit count. trackDirty=false is used during a full
-- rescale rebuild, since the whole canvas gets repainted afterward anyway -
-- no point building a dirty list nobody will read.
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

-- Exact connected line between two grid cells (Bresenham). This is what
-- makes fast movement between polls still read as a continuous trail,
-- and it's drawn directly in grid-space so its cost is proportional to
-- how far the point moved on screen, not to how much history exists.
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
    local intensity = count / maxCount
    local idx = math.ceil(intensity * #GRADIENT)
    if idx < 1 then idx = 1 elseif idx > #GRADIENT then idx = #GRADIENT end
    return GRADIENT[idx]
end

-- Full rebuild of a session's grid from its raw sample history, using the
-- session's CURRENT (possibly just-expanded) bounds. Only called when the
-- bounding box actually grew - this is the "expensive" path, but it's rare
-- and deferred to render time so a burst of expansion in one poll doesn't
-- trigger repeated rebuilds.
local function rescaleSession(s)
    s.grid = {}
    s.maxCount = 0
    s.dirty = {}
    s.dirtyCount = 0
    s.lastCol, s.lastRow = nil, nil

    local samples = s.samples
    local n = #samples
    local prevCol, prevRow, prevX, prevZ

    for i = 1, n do
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

-- Record one new position for a player. Cheap in the common case (bounds
-- unchanged): just draws a line from the last point to this one. Only
-- flags a rescale (deferred, batched) when the player has wandered outside
-- the previously-seen area.
local function recordSample(name, x, z)
    local s = ensureSession(name)
    local firstPoint = not s.hasPoint
    local expanded = false

    if firstPoint then
        s.minX, s.maxX, s.minZ, s.maxZ = x, x, z, z
    else
        if x < s.minX then s.minX = x; expanded = true end
        if x > s.maxX then s.maxX = x; expanded = true end
        if z < s.minZ then s.minZ = z; expanded = true end
        if z > s.maxZ then s.maxZ = z; expanded = true end
    end

    table.insert(s.samples, { x = x, z = z })
    if #s.samples > MAX_SAMPLES then
        table.remove(s.samples, 1)
    end

    if expanded then
        s.needsRescale = true -- replay everything (including this point)
                               -- on the next render pass
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
    -- if a rescale is already pending, skip the incremental draw entirely -
    -- the rescale will replay every sample (including this one) at once

    s.hasPoint = true
    s.lastX, s.lastZ = x, z
end

-- ===================== RENDERING =====================
local function fullRecolor(name)
    local s = sessions[name]
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

-- Repaint only the cells that changed since the last frame. Returns true
-- if anything was actually repainted (so the caller knows to blit).
local function flushDirty(name)
    local s = sessions[name]
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

-- Convert a sub-pixel cell back into approximate world coordinates.
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

-- A monitor_touch event only gives us a character cell, which covers a
-- 2 (wide) x 3 (tall) block of sub-pixels. Report whichever of those
-- six was visited most, falling back to the cell's center if empty.
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

-- ===================== POLLING =====================
local function pollOnce()
    for name in pairs(players) do
        local s = ensureSession(name)
        local x, y, z = tryGetPos(name)

        if x then
            s.active = true
            s.lastY = y
            recordSample(name, x, z)
        else
            s.active = false
        end
    end
end

-- ===================== JOIN/LEAVE EVENTS =====================
-- player_detector fires these directly once connected, no wrap/find
-- needed for the events themselves. This gives us an exact, instant
-- moment to reset a session, rather than inferring it from a poll.
local function joinLeaveLoop()
    while true do
        local event, username = os.pullEvent()
        if event == "playerJoin" and players[username] then
            sessions[username] = newSession()
            sessions[username].active = true
            print(username .. " logged in - starting new heatmap session.")
            if watchedPlayer == username then
                fullRecolor(username)
            end
        elseif event == "playerLeave" and players[username] then
            local s = sessions[username]
            if s then s.active = false end
            print(username .. " logged out - freezing heatmap.")
        elseif event == "hotspot_exit" then
            return
        end
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

local function watchPlayer(name)
    watchedPlayer = name
    local s = sessions[name]
    if s and s.needsRescale then
        rescaleSession(s)
    end
    fullRecolor(name)
end

local function handleCommand(line)
    local args = {}
    for word in line:gmatch("%S+") do table.insert(args, word) end
    local cmd = args[1]

    if cmd == "add" and args[2] then
        players[args[2]] = true
        ensureSession(args[2])
        savePlayers()
        print("Now tracking " .. args[2])

    elseif cmd == "remove" and args[2] then
        players[args[2]] = nil
        sessions[args[2]] = nil
        if watchedPlayer == args[2] then
            watchedPlayer = nil
            box:clear(EMPTY_COLOR)
            box:render()
        end
        savePlayers()
        print("Stopped tracking " .. args[2])

    elseif cmd == "list" then
        local any = false
        for name in pairs(players) do
            any = true
            print(" - " .. name .. (watchedPlayer == name and "  [watched]" or ""))
        end
        if not any then print("No players tracked yet.") end

    elseif cmd == "watch" and args[2] then
        if not players[args[2]] then
            print(args[2] .. " isn't tracked. Use 'add' first.")
        else
            watchPlayer(args[2])
            print("Watching " .. args[2] .. " on the monitor.")
        end

    elseif cmd == "status" then
        printStatus()

    elseif cmd == "reset" and args[2] then
        sessions[args[2]] = newSession()
        if watchedPlayer == args[2] then fullRecolor(args[2]) end
        print("Cleared session data for " .. args[2])

    elseif cmd == "exit" or cmd == "quit" then
        savePlayers()
        print("Saving and exiting...")
        return false

    elseif cmd == "help" then
        print("Commands: add <n> | remove <n> | list | watch <n> | status | reset <n> | exit")

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

-- Fast loop: just updates position data + grid. No monitor writes here.
local function pollLoop()
    while true do
        local timerId = os.startTimer(POLL_INTERVAL)
        while true do
            local event, id = os.pullEvent()
            if event == "timer" and id == timerId then
                break
            elseif event == "hotspot_exit" then
                return
            end
        end
        pollOnce()
    end
end

-- Slower loop: the only place that touches the monitor. Applies any
-- pending rescale, then either does a full recolor (periodically, or if
-- one was just triggered by a rescale) or a cheap dirty-cell-only repaint.
local function renderLoop()
    local sinceFullRecolor = 0
    while true do
        local timerId = os.startTimer(RENDER_INTERVAL)
        while true do
            local event, id = os.pullEvent()
            if event == "timer" and id == timerId then
                break
            elseif event == "hotspot_exit" then
                return
            end
        end

        if watchedPlayer then
            local s = sessions[watchedPlayer]
            if s then
                if s.needsRescale then
                    rescaleSession(s)
                end

                sinceFullRecolor = sinceFullRecolor + RENDER_INTERVAL
                if s.needsFullRecolor or sinceFullRecolor >= FULL_RECOLOR_INTERVAL then
                    fullRecolor(watchedPlayer)
                    sinceFullRecolor = 0
                elseif flushDirty(watchedPlayer) then
                    box:render()
                end
            end
        end
    end
end

local function touchLoop()
    while true do
        local event, side, tx, ty = os.pullEvent("monitor_touch")
        if watchedPlayer then
            local s = sessions[watchedPlayer]
            if s and s.hasPoint then
                local x, z = touchToCoords(s, tx, ty)
                print(string.format(
                    "Clicked (%d,%d) -> approx coords: X=%d Z=%d (%s)",
                    tx, ty, x, z, watchedPlayer
                ))
            end
        end
    end
end

-- ===================== MAIN =====================
players = loadPlayers()
for name in pairs(players) do ensureSession(name) end

box:clear(EMPTY_COLOR)
box:render()

parallel.waitForAny(commandLoop, pollLoop, renderLoop, touchLoop, joinLeaveLoop)
