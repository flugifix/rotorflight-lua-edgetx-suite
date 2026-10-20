-- Checks the radio-wide dashboard shortcut resolver and its integration with Views.key, offline,
-- with desktop Lua 5.3, from the repository root:
--
--   lua5.3 bin/dashboard/verify_fullscreen_keys.lua
--   lua5.3 bin/dashboard/verify_fullscreen_keys.lua --verbose
--   lua5.3 bin/dashboard/verify_fullscreen_keys.lua --self-test
--
-- The resolver and Views cases load the real widgets/dashboard/keys.lua and
-- widgets/dashboard/views.lua from the tree; only firmware key constants, logging and
-- lcd.exitFullScreen are stubbed there. The Runtime exit case uses accounting firmware
-- and flight-controller stubs around the real widgets/dashboard/runtime.lua.

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]dashboard$") or (dir .. "/../..") end
end

local verbose, selfTest = false, false
for i = 1, #arg do
  if arg[i] == "--verbose" then
    verbose = true
  elseif arg[i] == "--self-test" then
    selfTest = true
  else
    io.stderr:write("usage: lua5.3 bin/dashboard/verify_fullscreen_keys.lua [--verbose] [--self-test]\n")
    os.exit(2)
  end
end

local SRC = ROOT .. "/src/rfsuite/"
local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

local keysSource = readFile(SRC .. "widgets/dashboard/keys.lua")
local viewsSource = readFile(SRC .. "widgets/dashboard/views.lua")
local runtimeSource = readFile(SRC .. "widgets/dashboard/runtime.lua")
if keysSource == nil or viewsSource == nil or runtimeSource == nil then
  io.stderr:write("cannot read dashboard key modules\n")
  os.exit(2)
end

local function loadModule(source, name)
  local chunk, err = load(source, "@" .. name)
  if not chunk then return nil, err end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then return nil, result end
  return result
end

local function loadPair(source)
  local Keys, err = loadModule(source, "widgets/dashboard/keys.lua")
  if Keys == nil then return nil, nil, err end
  _G.rfsuite = {
    require = function(path)
      if path == "widgets/dashboard/keys.lua" then return Keys end
      if path == "lib/log.lua" then return { emit = function() end } end
      return nil
    end,
  }
  local Views, viewErr = loadModule(viewsSource, "widgets/dashboard/views.lua")
  if Views == nil then return nil, nil, viewErr end
  return Keys, Views
end

_G.EVT_VIRTUAL_NEXT_PAGE = 101
_G.EVT_VIRTUAL_PREV_PAGE = 102
_G.EVT_VIRTUAL_EXIT = 103
_G.EVT_MODEL_BREAK = 104
_G.EVT_SYS_BREAK = 105
_G.EVT_TELEM_BREAK = 106
_G.lcd = { exitFullScreen = function() end }

local function newWidget(Views, base)
  local widget = {
    zone = { w = 800, h = 480 }, state = {}, preferences = { dashboard = {} },
    built = true, renderKey = "test",
  }
  if base ~= false then widget._viewBase = {} end
  widget._viewCtx = Views.bind(widget)
  return widget
end

local function runtimeCancellationCase(source)
  local Stubs = assert(loadfile(ROOT .. "/bin/accounting/stubs/edgetx.lua"))()
  local FC = assert(loadfile(ROOT .. "/bin/accounting/stubs/fc.lua"))()
  Stubs.install(ROOT)
  FC.install(Stubs)
  Stubs.reset()
  FC.reset()
  local Runtime, loadErr = loadModule(source, "widgets/dashboard/runtime.lua")
  if Runtime == nil then return "runtime did not load: " .. tostring(loadErr) end
  for _, pendingSpec in ipairs({
    { kind = "fs_theme", flag = "fullscreen" },
    { kind = "splash", flag = "fullscreenSplash" },
  }) do
    local w = Runtime.new({ x = 0, y = 0, w = 800, h = 480 }, {})
    local ran = 0
    w.connectionReady = true
    w.inflightFullscreen = true
    w._viewStack = { { id = "menu" } }
    w._cachedFullscreenKey = "old"
    local pending = { kind = pendingSpec.kind, step = function() ran = ran + 1 end }
    pending[pendingSpec.flag] = true
    w._job = pending
    w.built = true
    w.renderKey = "fullscreen"
    w:refresh(nil)
    if ran ~= 0 then return "the pending " .. pendingSpec.kind .. " job ran after exit" end
    if w._job == pending then return "the pending " .. pendingSpec.kind .. " job was retained" end
    if w.inflightFullscreen ~= nil or w._viewStack ~= nil or w._cachedFullscreenKey ~= nil then
      return "fullscreen visit state survived the " .. pendingSpec.kind .. " exit"
    end
    if w.built ~= false or w.renderKey ~= nil then return "the cancelled " .. pendingSpec.kind .. " surface stayed built" end
  end
  Stubs.releaseCard()
end

local CASES = {
  {
    id = "invalid choices fall back to Theme",
    fn = function(Keys)
      if Keys.choice("unknown") ~= "theme" or Keys.choice({}) ~= "theme" then
        return "an invalid stored choice did not resolve to Theme"
      end
    end,
  },
  {
    id = "Theme resolves context before declarations",
    fn = function(Keys)
      local themeKeys = { sys = "none" }
      local declaredKeys = { sys = "openView:menu" }
      local action, global = Keys.resolve({}, "sys", themeKeys, declaredKeys)
      if action ~= "none" or global then return "context binding did not win" end
      action, global = Keys.resolve({}, "sys", {}, { sys = "openView:menu" })
      if action ~= "openView:menu" or global then return "declared binding did not fill the gap" end
      if themeKeys.sys ~= "none" or declaredKeys.sys ~= "openView:menu" then
        return "resolution mutated a theme binding table"
      end
    end,
  },
  {
    id = "page keys retain the host menu fallback",
    fn = function(_, Views)
      local w = newWidget(Views)
      local handled = Views.key(w, _G.EVT_VIRTUAL_NEXT_PAGE)
      if handled ~= true or Views.top(w) ~= "menu" then return "PAGE > did not open the menu" end
    end,
  },
  {
    id = "declared keys act before the first build",
    fn = function(_, Views)
      local w = newWidget(Views)
      w._declaredKeys = { sys = "openView:menu" }
      local handled = Views.key(w, _G.EVT_SYS_BREAK)
      if handled ~= true or Views.top(w) ~= "menu" then return "declared SYS did not open the menu" end
    end,
  },
  {
    id = "Theme keys yield while another view is on top",
    fn = function(_, Views)
      local w = newWidget(Views)
      w._viewCtx.keys.sys = "none"
      Views.navigate(w, "openView:menu")
      local handled = Views.key(w, _G.EVT_SYS_BREAK)
      if handled ~= false or Views.top(w) ~= "menu" then return "Theme SYS consumed the top view" end
    end,
  },
  {
    id = "explicit Nothing is consumed on top",
    fn = function(_, Views)
      local w = newWidget(Views)
      w.preferences.dashboard.key_sys = "none"
      Views.navigate(w, "openView:menu")
      local handled = Views.key(w, _G.EVT_SYS_BREAK)
      if handled ~= true or Views.top(w) ~= "menu" then return "explicit Nothing was not consumed" end
    end,
  },
  {
    id = "explicit menu toggles the menu",
    fn = function(_, Views)
      local w = newWidget(Views)
      w.preferences.dashboard.key_sys = "menu"
      Views.navigate(w, "openView:menu")
      local handled = Views.key(w, _G.EVT_SYS_BREAK)
      if handled ~= true or Views.top(w) ~= nil then return "explicit menu did not close the menu" end
    end,
  },
  {
    id = "only explicit choices act without a theme base",
    fn = function(_, Views)
      local theme = newWidget(Views, false)
      if theme._viewBase ~= nil then return "the no-base fixture has a base" end
      if Views.key(theme, _G.EVT_MODEL_BREAK) ~= false then return "Theme acted without a base" end
      local global = newWidget(Views, false)
      global.preferences.dashboard.key_mdl = "none"
      if Views.key(global, _G.EVT_MODEL_BREAK) ~= true then return "explicit Nothing did not act without a base" end
    end,
  },
  {
    id = "short RTN closes a view without leaving fullscreen",
    fn = function(_, Views)
      local w = newWidget(Views)
      Views.navigate(w, "openView:menu")
      local handled, exited = Views.key(w, _G.EVT_VIRTUAL_EXIT)
      if handled ~= true or exited == true or Views.top(w) ~= nil then
        return "short RTN did not keep Back/Close ownership"
      end
    end,
  },
  {
    id = "unknown events are left to the host",
    fn = function(_, Views)
      if Views.key(newWidget(Views), 999) ~= false then return "an unknown event was consumed" end
    end,
  },
  {
    id = "fullscreen exit cancels a pending fullscreen job",
    fn = function()
      return runtimeCancellationCase(runtimeSource)
    end,
  },
}

local function runChecks(source, quiet)
  local Keys, Views, err = loadPair(source)
  if Keys == nil then return { { case = "load modules", detail = tostring(err) } }, 0 end
  local failures, passes = {}, 0
  for i = 1, #CASES do
    local case = CASES[i]
    local ok, result = pcall(case.fn, Keys, Views)
    local bad
    if not ok then bad = "raised: " .. tostring(result) else bad = result end
    if bad == nil then passes = passes + 1 else failures[#failures + 1] = { case = case.id, detail = bad } end
    if verbose and not quiet then
      print(string.format("%s %-48s %s", bad == nil and "PASS" or "FAIL", case.id, bad or ""))
    end
  end
  return failures, passes
end

if selfTest then
  local real = runChecks(keysSource, true)
  if #real > 0 then
    print("SELF-TEST FAILED: the checks are red on the unbroken tree")
    os.exit(1)
  end
  local mutant, count = string.gsub(keysSource, "return ACTIONS%[choice%], true", "return ACTIONS[choice], false", 1)
  if count ~= 1 then
    print("SELF-TEST FAILED: the explicit-choice branch was found " .. count .. " times, expected once")
    os.exit(1)
  end
  local failures = runChecks(mutant, true)
  if #failures == 0 then
    print("SELF-TEST FAILED: treating explicit choices as Theme stayed green")
    os.exit(1)
  end
  print("(self-test) explicit-choice mutant went red: " .. failures[1].case .. ": " .. failures[1].detail)
  local exitGuard = "    if event == nil then"
  local runtimeMutant, runtimeCount = string.gsub(runtimeSource, exitGuard, "    if false and event == nil then", 1)
  if runtimeCount ~= 1 then
    print("SELF-TEST FAILED: the fullscreen-exit guard was found " .. runtimeCount .. " times, expected once")
    os.exit(1)
  end
  local runtimeBad = runtimeCancellationCase(runtimeMutant)
  if runtimeBad == nil then
    print("SELF-TEST FAILED: disabling early fullscreen-exit cleanup stayed green")
    os.exit(1)
  end
  print("(self-test) fullscreen-exit mutant went red: " .. runtimeBad)
  print("SELF-TEST PASSED: resolver and early-exit regressions are detected")
  os.exit(0)
end

print(string.format("%d cases on fullscreen key bindings", #CASES))
local failures, passes = runChecks(keysSource, false)
if #failures > 0 then
  for _, failure in ipairs(failures) do print("FAIL: " .. failure.case .. ": " .. failure.detail) end
  print(string.format("%d case(s) failed, %d passed", #failures, passes))
  os.exit(1)
end
print(string.format("%d cases, 0 failures", passes))
