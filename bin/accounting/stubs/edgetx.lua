-- The minimal EdgeTX surface the measured sources touch. Deterministic by construction:
-- the clock advances a fixed step per call, every sensor/model/telemetry answer comes from
-- a scripted table, and lvgl records node trees instead of drawing. Stubs answer; they
-- never compute -- anything clever here is a measurement error waiting to be found.
--
-- A missing surface must fail the run loudly: the suite's own sources wrap everything in
-- pcall, and in a measurement a swallowed load error is a zero that reads as "cheap".

local Stubs = {}

local SRC_PREFIX = "/SCRIPTS/TOOLS/rfsuite-core/"
local WIDGET_PREFIX = "/SCRIPTS/TOOLS/"

-- Repo-relative remap targets; measure.lua chdir-independence comes from passing the
-- repo root in.
local repoRoot = "."

-- Fixed-step clock: 10 ms of getTime() ticks per call (getTime is in 10 ms units on the
-- radio). Never the wall clock -- determinism is what makes two runs comparable.
local clockTicks = 0
local CLOCK_STEP_TICKS = 1

-- Scripted answers, settable per scenario by measure.lua.
Stubs.sensors = {}          -- name -> number (getValue / lib/sensors path)
Stubs.modelInfo = { name = "Bench", bitmap = "" }
Stubs.telemetryFrames = {}  -- queue of { command, data } served to crossfireTelemetryPop
Stubs.published = {}        -- what setTelemetryValue was called with, recorded
Stubs.prefsStat = nil       -- what fstat answers for the preference files, or nil for absent

-- The far side of the link. stubs/fc.lua replaces this with a scripted flight controller;
-- on its own the link accepts every frame and answers nothing, which is a radio with no
-- board attached.
Stubs.onPush = function() return true end

--- Queue one frame for crossfireTelemetryPop, in arrival order.
function Stubs.pushFrame(command, data)
  Stubs.telemetryFrames[#Stubs.telemetryFrames + 1] = { command = command, data = data }
end

-- lvgl recorder: `build` keeps the node list and collects every function field as a
-- reactive ref, so the sweep can be replayed by the runner in a plain loop.
Stubs.lvgl = {
  trees = {},
  refs = {},
}

local function collectRefs(node, refs)
  for _, v in pairs(node) do
    if type(v) == "function" then
      refs[#refs + 1] = v
    elseif type(v) == "table" then
      collectRefs(v, refs)
    end
  end
end

function Stubs.reset()
  clockTicks = 0
  Stubs.sensors = {}
  Stubs.telemetryFrames = {}
  Stubs.published = {}
  Stubs.prefsStat = nil
  Stubs.lvgl.trees = {}
  Stubs.lvgl.refs = {}
end

function Stubs.install(root)
  repoRoot = root or "."

  _G.LCD_W = 800
  _G.LCD_H = 480

  -- Colors, fonts, alignment: numeric constants, values irrelevant to the count.
  local consts = {
    WHITE = 0xFFFF, BLACK = 0x0000, RED = 0xF800, GREEN = 0x07E0, YELLOW = 0xFFE0,
    BLUE = 0x001F, MAGENTA = 0xF81F, CYAN = 0x07FF,
    COLOR_THEME_PRIMARY1 = 1, COLOR_THEME_PRIMARY2 = 2, COLOR_THEME_PRIMARY3 = 3,
    COLOR_THEME_SECONDARY1 = 4, COLOR_THEME_SECONDARY2 = 5, COLOR_THEME_SECONDARY3 = 6,
    COLOR_THEME_WARNING = 7, COLOR_THEME_DISABLED = 8, COLOR_THEME_FOCUS = 9,
    COLOR_THEME_ACTIVE = 10, COLOR_THEME_EDIT = 11,
    DBLSIZE = 0x400, MIDSIZE = 0x300, SMLSIZE = 0x100, XXLSIZE = 0x800,
    CENTER = 0x10, LEFT = 0x20, RIGHT = 0x40, TOP = 0x01, BOTTOM = 0x02,
  }
  for k, v in pairs(consts) do _G[k] = v end

  -- Lua 5.3 dropped bit32; the firmware's build provides it. Only what the sources use.
  if not _G.bit32 then
    _G.bit32 = {
      band = function(a, b) return a & b end,
      bor = function(a, b) return a | b end,
      bxor = function(a, b) return a ~ b end,
      lshift = function(a, n) return (a << n) & 0xFFFFFFFF end,
      rshift = function(a, n) return a >> n end,
      extract = function(n, f, w) return (n >> f) & ((1 << (w or 1)) - 1) end,
    }
  end

  _G.getTime = function()
    clockTicks = clockTicks + CLOCK_STEP_TICKS
    return clockTicks
  end

  _G.getVersion = function()
    return "bench", "EdgeTX-accounting-stub", 2, 12, 0
  end

  _G.getUsage = function() return 0 end

  _G.model = {
    getInfo = function()
      return { name = Stubs.modelInfo.name, bitmap = Stubs.modelInfo.bitmap }
    end,
  }

  _G.getValue = function(name)
    return Stubs.sensors[name]
  end

  _G.getFieldInfo = function(name)
    if Stubs.sensors[name] ~= nil then
      return { id = name, name = name }
    end
    return nil
  end

  _G.getSensor = function(name)
    local v = Stubs.sensors[name]
    if v == nil then return nil end
    return { value = v }
  end

  _G.setTelemetryValue = function(id, sub, instance, value, unit, prec, name)
    Stubs.published[#Stubs.published + 1] = { id = id, value = value, name = name }
    return true
  end

  _G.crossfireTelemetryPop = function()
    local frame = table.remove(Stubs.telemetryFrames, 1)
    if frame == nil then return nil end
    -- The firmware returns (command, data); the suite's crsf lib re-assembles from both.
    return frame.command, frame.data
  end

  _G.crossfireTelemetryPush = function(command, data)
    return Stubs.onPush(command, data)
  end

  -- The radio's own file stat. Answers for the preference files only: the widget entry
  -- point and the dashboard runtime both watch them, and a stat that changes between two
  -- passes would enqueue a reload nobody asked for.
  _G.fstat = function(_path)
    return Stubs.prefsStat
  end

  _G.system = {
    getVersion = function()
      return { version = "2.12.0", simulation = false }
    end,
  }

  _G.playFile = function() end
  _G.playTone = function() end
  _G.playNumber = function() end
  _G.killEvents = function() end

  _G.lcd = {
    RGB = function(r, g, b)
      return ((r // 8) << 11) | ((g // 4) << 5) | (b // 8)
    end,
  }

  _G.lvgl = {
    clear = function()
      Stubs.lvgl.trees = {}
      Stubs.lvgl.refs = {}
    end,
    build = function(children)
      Stubs.lvgl.trees[#Stubs.lvgl.trees + 1] = children
      local refs = Stubs.lvgl.refs
      collectRefs(children, refs)
      return true
    end,
    onEvent = function() end,
  }

  -- loadScript remap: the deploy prefix -> src/rfsuite, widget entry prefix -> src/widgets.
  -- Loads fail LOUDLY through the returned nil only when the file truly does not exist;
  -- a syntax error raises, exactly as measure.lua wants it to.
  _G.loadScript = function(path, mode)
    local rel
    if string.sub(path, 1, #SRC_PREFIX) == SRC_PREFIX then
      rel = repoRoot .. "/src/rfsuite/" .. string.sub(path, #SRC_PREFIX + 1)
    elseif string.sub(path, 1, #WIDGET_PREFIX) == WIDGET_PREFIX then
      rel = repoRoot .. "/src/" .. string.sub(path, #WIDGET_PREFIX + 1)
    else
      rel = repoRoot .. "/" .. path
    end
    local f = io.open(rel, "r")
    if not f then return nil end
    f:close()
    local chunk, err = loadfile(rel)
    if not chunk then
      error("stub loadScript: " .. tostring(err))
    end
    return chunk
  end

  -- lib/require.lua is the suite's OWN memoizer and it is used as it ships: a hand-written
  -- one here would answer differently from the radio's -- it returns nil for a module that
  -- is not there, and several objects probe for optional submodules exactly that way.
  --
  -- It reports both failure modes through print(), outside its own pcall, so the wrapper
  -- below records them and measure.lua prints them: a stub surface that is missing shows up
  -- as a module that would not execute, instead of as a pass that came out cheap.
  local realPrint = print
  Stubs.requireFailures = {}
  _G.print = function(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do parts[i] = tostring((select(i, ...))) end
    local line = table.concat(parts, "	")
    if string.sub(line, 1, 10) == "[require] " then
      Stubs.requireFailures[#Stubs.requireFailures + 1] = line
    end
    realPrint(line)
  end

  _G.rfsuite = { session = {}, preferences = {} }
  local requireChunk = loadfile(repoRoot .. "/src/rfsuite/lib/require.lua")
  if not requireChunk then
    error("accounting: lib/require.lua not found under " .. tostring(repoRoot))
  end
  requireChunk()
end

return Stubs
