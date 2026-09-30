-- Checks a dashboard theme that takes fullscreen (`fullscreen = "theme"` in its init.lua) for the
-- duties docs/developer/dashboard-themes.md gives it, offline, with desktop Lua 5.3.
--
--   lua5.3 bin/themes/validate.lua <theme folder> [--size 800x480|480x272]
--
-- Every phase module the theme declares is built at the fullscreen size with a recording `ctx`,
-- and every press in the tree it returns is fired. The theme is red where
--
--   * no press opens the quick menu (`openView:menu`, or the menu built through `ctx.menu`);
--   * nothing leaves fullscreen: no press with `exitFullscreen`, no `ctx.keys.exit =
--     "exitFullscreen"` -- RTN is on every radio, so that binding is a way out -- and no
--     `fullscreenExit = "longRtn"` in init.lua, the author relying on a long press on RTN;
--   * a `rectangle` lies over a node that has a press: built in fullscreen it takes the press
--     and hands it to its parent, so it swallows every press that lands on it;
--   * a press or a `ctx.keys` entry names an action that is not one of `openView:<id>`,
--     `closeView`, `done`, `exitFullscreen` and `none`, or a view the widget does not have;
--   * a build raises, or returns something that is not a node list.
--
-- A tree that binds no press at all is green: the widget draws its own menu control and X over
-- it. So is a declarative theme, which cannot bind a press. A theme without the key is not
-- checked. Exit status 0 green, 1 red, 2 when the theme cannot be read.
--
-- The firmware and the widget are stubbed here, in this file: a theme is only ever called with
-- a zone, a state and a ctx, and a stub answers rather than computes. The state is a fixture of
-- typical readings, so a theme that reads something else sees nil, as it may on a radio before
-- the first telemetry.

local USAGE = "usage: lua5.3 bin/themes/validate.lua <theme folder> [--size 800x480|480x272]"

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]themes$") or (dir .. "/../..") end
end

local folder, width, height = nil, 800, 480
do
  local i = 1
  while arg[i] do
    if arg[i] == "--size" then
      local w, h = string.match(arg[i + 1] or "", "^(%d+)x(%d+)$")
      if not w then io.stderr:write(USAGE .. "\n") os.exit(2) end
      width, height = tonumber(w), tonumber(h)
      i = i + 2
    elseif folder == nil then
      folder = string.gsub(arg[i], "[/\\]+$", "")
      i = i + 1
    else
      io.stderr:write(USAGE .. "\n")
      os.exit(2)
    end
  end
end
if folder == nil then io.stderr:write(USAGE .. "\n") os.exit(2) end
local folderName = string.match(folder, "([^/\\]+)$")

-- ---------------------------------------------------------------------------
-- Stubs
-- ---------------------------------------------------------------------------

local exits = 0

local consts = {
  WHITE = 0xFFFF, BLACK = 0x0000, RED = 0xF800, GREEN = 0x07E0, YELLOW = 0xFFE0, BLUE = 0x001F,
  MAGENTA = 0xF81F, CYAN = 0x07FF, GREY = 0x8410, DARKGREY = 0x4208, LIGHTGREY = 0xC618,
  ORANGE = 0xFD20, BROWN = 0x8200, DARKGREEN = 0x0400, DARKRED = 0x8000, DARKBLUE = 0x0010,
  COLOR_THEME_PRIMARY1 = 1, COLOR_THEME_PRIMARY2 = 2, COLOR_THEME_PRIMARY3 = 3,
  COLOR_THEME_SECONDARY1 = 4, COLOR_THEME_SECONDARY2 = 5, COLOR_THEME_SECONDARY3 = 6,
  COLOR_THEME_WARNING = 7, COLOR_THEME_DISABLED = 8, COLOR_THEME_FOCUS = 9,
  COLOR_THEME_ACTIVE = 10, COLOR_THEME_EDIT = 11,
  XXLSIZE = 0x800, XLSIZE = 0x700, DBLSIZE = 0x400, MIDSIZE = 0x300, STDSIZE = 0, SMLSIZE = 0x100,
  TINSIZE = 0x200, BOLD = 0x4000, INVERS = 0x8000,
  CENTER = 0x10, LEFT = 0x20, RIGHT = 0x40, TOP = 0x01, BOTTOM = 0x02, VCENTER = 0x04,
  LCD_W = width, LCD_H = height,
}
for k, v in pairs(consts) do _G[k] = v end

local FONT = { [0x800] = { 24, 40 }, [0x700] = { 19, 32 }, [0x400] = { 14, 24 }, [0x300] = { 11, 18 },
               [0] = { 8, 14 }, [0x100] = { 6, 10 }, [0x200] = { 5, 8 } }

_G.lcd = {
  RGB = function(r, g, b) return ((r // 8) << 11) | ((g // 4) << 5) | (b // 8) end,
  sizeText = function(text, font)
    local m = FONT[(font or 0) & 0xF00] or FONT[0]
    return #tostring(text or "") * m[1], m[2]
  end,
  exitFullScreen = function() exits = exits + 1 end,
}
_G.lvgl = { clear = function() end, build = function() return true end }
_G.getTime = function() return 0 end
_G.getValue = function() return nil end
_G.getFieldInfo = function() return nil end
_G.getGeneralSettings = function() return { battMin = 6.6, battMax = 8.4, battWarn = 7.0 } end
_G.getDateTime = function() return { year = 2026, mon = 1, day = 1, hour = 12, min = 0, sec = 0 } end
_G.getVersion = function() return "2.12.0", "validator", 2, 12, 0 end
_G.model = {
  getInfo = function() return { name = "Model" } end,
  getGlobalVariable = function() return 0 end,
}

local SRC_PREFIX = "/SCRIPTS/TOOLS/rfsuite-core/"
local USER_PREFIX = "/SCRIPTS/TOOLS/rfsuite.user/dashboard/"

-- A theme reaches its own files by the path the card gives them, shipped or user: both are mapped
-- onto the folder being checked. Everything else under the suite's prefix is this repository's.
local function mapPath(path)
  local rel = string.sub(path, 1, #SRC_PREFIX) == SRC_PREFIX and string.sub(path, #SRC_PREFIX + 1) or nil
  local name, file
  if rel then
    name, file = string.match(rel, "^widgets/dashboard/themes/([^/]+)/(.+)$")
    if name ~= folderName then return ROOT .. "/src/rfsuite/" .. rel end
  elseif string.sub(path, 1, #USER_PREFIX) == USER_PREFIX then
    name, file = string.match(string.sub(path, #USER_PREFIX + 1), "^([^/]+)/(.+)$")
    if name ~= folderName then return nil end
  else
    return nil
  end
  return folder .. "/" .. file
end

_G.loadScript = function(path)
  local mapped = type(path) == "string" and mapPath(path) or nil
  if mapped == nil then return nil end
  local f = io.open(mapped, "r")
  if not f then return nil end
  f:close()
  return assert(loadfile(mapped, "t"))
end

local loaded = {}
_G.rfsuite = {
  loadMode = "t",
  session = {},
  require = function(path)
    if loaded[path] ~= nil then return loaded[path] or nil end
    local chunk = _G.loadScript(SRC_PREFIX .. path)
    local ok, mod = false, nil
    if chunk then ok, mod = pcall(chunk) end
    loaded[path] = (ok and mod) or false
    return loaded[path] or nil
  end,
}

-- ---------------------------------------------------------------------------
-- The fixture: the state a phase build is handed
-- ---------------------------------------------------------------------------

local function makeState(phase)
  local armed = phase == "armed" or phase == "inflight"
  return {
    zoneW = width, zoneH = height, zoneX = 0, zoneY = 0,
    flightMode = phase, themePhase = phase, armed = armed, rfConnected = phase ~= "offline",
    voltage = 24.6, fuel = 82, consumedMah = 312, rpm = 1850, current = 31.4, escTemp = 61,
    mcuTemp = 44, watts = 772, throttlePercent = 67, lq = 99, rss1 = -71, bec_voltage = 8.1,
    governor = 4, profile = 1, rateProfile = 2, batteryProfile = 1, flights = 137,
    totalFlightSeconds = 48231, flightSeconds = 245, altitude = 12.5, armDisableFlags = 0,
    batteryCellCount = 6,
    themeConfig = { v_min = 18.0, v_max = 25.2 },
    flight = { flights = 137, armed = armed, seconds = 245, lastSeconds = 301, current = {}, last = {} },
    batteryPick = { loaded = true, pending = false, candidates = {}, dismissed = false },
  }
end

-- ---------------------------------------------------------------------------
-- The recording ctx, and the actions it accepts
-- ---------------------------------------------------------------------------

local VIEWS = { menu = true, battery_pick = true }
local SIMPLE = { closeView = true, done = true, exitFullscreen = true, none = true }

-- nil when the action is one the widget knows, else why not.
local function actionProblem(after)
  if type(after) ~= "string" then return "an action that is not a string (" .. type(after) .. ")" end
  if SIMPLE[after] then return nil end
  local id = string.match(after, "^openView:(.+)$")
  if id == nil then return "unknown action '" .. after .. "'" end
  if not VIEWS[id] then return "'" .. after .. "' names a view the widget does not have" end
  return nil
end

local function newCtx(log)
  local ctx = { keys = {} }
  ctx.action = function(after) log.actions[#log.actions + 1] = after end
  ctx.condition = function() return false end
  ctx.entries = function() return {} end
  ctx.menu = function(children)
    log.menuBuilt = true
    return children
  end
  return ctx
end

-- ---------------------------------------------------------------------------
-- The tree
-- ---------------------------------------------------------------------------

-- Pre-order, in drawing order, with absolute boxes: a child's coordinates are its parent's plus
-- its own.
local function flatten(nodes, ox, oy, out)
  for i = 1, #nodes do
    local node = nodes[i]
    if type(node) == "table" then
      local x = ox + (tonumber(node.x) or 0)
      local y = oy + (tonumber(node.y) or 0)
      out[#out + 1] = { node = node, x = x, y = y, w = tonumber(node.w) or 0, h = tonumber(node.h) or 0 }
      if type(node.children) == "table" then flatten(node.children, x, y, out) end
    end
  end
  return out
end

local function overlaps(a, b)
  return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function where(item)
  return string.format("%s at %d,%d %dx%d", tostring(item.node.type), item.x, item.y, item.w, item.h)
end

-- ---------------------------------------------------------------------------
-- The check
-- ---------------------------------------------------------------------------

local findings, notes = {}, {}
local function red(msg) findings[#findings + 1] = msg end
local function note(msg) notes[#notes + 1] = msg end

local initChunk = loadfile(folder .. "/init.lua", "t")
if not initChunk then
  io.stderr:write("cannot read " .. folder .. "/init.lua\n")
  os.exit(2)
end
local okInit, init = pcall(initChunk)
if not okInit or type(init) ~= "table" then
  io.stderr:write(folder .. "/init.lua does not return a table\n")
  os.exit(2)
end

print(string.format("theme %s (%s), fullscreen %dx%d", folder, tostring(init.name), width, height))

if init.fullscreen ~= "theme" then
  print("does not take fullscreen (no fullscreen = \"theme\" in init.lua): nothing to check")
  print("GREEN")
  os.exit(0)
end

local relyOnLongRtn = init.fullscreenExit == "longRtn"
if init.fullscreenExit ~= nil and not relyOnLongRtn then
  red("init.lua: fullscreenExit = " .. tostring(init.fullscreenExit) .. " is not \"longRtn\"")
end

-- The phase modules, resolved the way the widget resolves them: a refinement phase falls back
-- to the phase it refines, and a phase with no module of its own to widget.lua.
local PHASES = { "preflight", "armed", "inflight", "postflight", "offline" }
local FALLBACK = { armed = "preflight", offline = "postflight" }
local modules, order = {}, {}
for _, phase in ipairs(PHASES) do
  local key = phase
  while type(init[key]) ~= "string" and FALLBACK[key] do key = FALLBACK[key] end
  local file = type(init[key]) == "string" and init[key] or "widget.lua"
  if modules[file] == nil then
    modules[file] = { phases = {} }
    order[#order + 1] = file
  end
  local list = modules[file].phases
  list[#list + 1] = phase
end

for _, file in ipairs(order) do
  local label = file .. " [" .. table.concat(modules[file].phases, ", ") .. "]"
  local chunk = loadfile(folder .. "/" .. file, "t")
  local okMod, theme = false, nil
  if chunk then okMod, theme = pcall(chunk) end
  if not okMod or type(theme) ~= "table" then
    red(label .. ": the module does not load (" .. tostring(theme) .. ")")
  elseif type(theme.build) ~= "function" then
    if type(theme.layout) == "table" or theme.boxes ~= nil then
      note(label .. ": declarative, binds nothing; the widget draws its own menu control and X")
    else
      red(label .. ": neither build() nor layout/boxes")
    end
  else
    local log = { actions = {}, menuBuilt = false }
    local ctx = newCtx(log)
    local zone = { x = 0, y = 0, w = width, h = height }
    local okBuild, tree = pcall(theme.build, zone, makeState(modules[file].phases[1]), ctx)
    if not okBuild then
      red(label .. ": build() raised: " .. tostring(tree))
    elseif type(tree) ~= "table" then
      red(label .. ": build() returned " .. type(tree) .. ", not a node list")
    else
      local flat = flatten(tree, 0, 0, {})
      local presses, opensMenu, leaves = 0, log.menuBuilt, false
      for i, item in ipairs(flat) do
        if item.node.press ~= nil then
          presses = presses + 1
          if type(item.node.press) ~= "function" then
            red(label .. ": the press of " .. where(item) .. " is not a function")
          else
            local before, exitsBefore = #log.actions, exits
            local okPress, err = pcall(item.node.press)
            if not okPress then red(label .. ": the press of " .. where(item) .. " raised: " .. tostring(err)) end
            if exits > exitsBefore then
              leaves = true
              note(label .. ": the press of " .. where(item) .. " calls lcd.exitFullScreen() itself; "
                .. "ctx.action(\"exitFullscreen\") is the documented way")
            end
            for k = before + 1, #log.actions do
              local after = log.actions[k]
              local problem = actionProblem(after)
              if problem then red(label .. ": the press of " .. where(item) .. ": " .. problem) end
              if after == "openView:menu" then opensMenu = true end
              if after == "exitFullscreen" then leaves = true end
            end
          end
          for j = i + 1, #flat do
            if flat[j].node.type == "rectangle" and overlaps(flat[j], item) then
              red(label .. ": " .. where(flat[j]) .. " is drawn over the press of " .. where(item)
                .. "; draw it before the pressable node, or as a line or a label")
            end
          end
        end
      end
      for name, after in pairs(ctx.keys) do
        if name ~= "exit" and name ~= "pageDown" and name ~= "pageUp" then
          red(label .. ": ctx.keys." .. tostring(name) .. " is not a key the widget answers")
        end
        local problem = actionProblem(after)
        if problem then red(label .. ": ctx.keys." .. tostring(name) .. ": " .. problem) end
      end
      -- Read after the build and the presses have run, which is when a theme has filled it.
      local keyExit = ctx.keys.exit == "exitFullscreen"
      if presses == 0 then
        note(label .. ": binds no press; the widget draws its own menu control and X")
      else
        if not opensMenu then
          red(label .. ": no press opens the quick menu (openView:menu, or ctx.menu)")
        end
        if not leaves and keyExit then
          note(label .. ": no press leaves fullscreen; RTN does, through ctx.keys.exit")
        elseif not leaves then
          if relyOnLongRtn then
            note(label .. ": no press leaves fullscreen; init.lua relies on a long press on RTN")
          else
            red(label .. ": nothing leaves fullscreen: bind exitFullscreen to a press or to "
              .. "ctx.keys.exit, or declare fullscreenExit = \"longRtn\" in init.lua to rely on a long press on RTN")
          end
        end
        note(string.format("%s: %d presses, %d actions", label, presses, #log.actions))
      end
    end
  end
end

for _, n in ipairs(notes) do print("  " .. n) end
for _, f in ipairs(findings) do print("RED: " .. f) end
if #findings > 0 then
  print(string.format("RED (%d finding%s)", #findings, #findings == 1 and "" or "s"))
  os.exit(1)
end
print("GREEN")
os.exit(0)
