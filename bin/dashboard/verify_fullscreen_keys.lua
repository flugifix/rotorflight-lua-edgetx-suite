-- Checks the radio-wide dashboard shortcut resolver and its integration with Views.key, offline,
-- with desktop Lua 5.3, from the repository root:
--
--   lua5.3 bin/dashboard/verify_fullscreen_keys.lua
--   lua5.3 bin/dashboard/verify_fullscreen_keys.lua --verbose
--   lua5.3 bin/dashboard/verify_fullscreen_keys.lua --self-test
--
-- The resolver and Views cases load the real widgets/dashboard/keys.lua and
-- widgets/dashboard/views.lua from the tree; only firmware key constants, logging and
-- lcd.exitFullScreen are stubbed there. The Keys page case loads the real page and
-- app/pages/settings/common.lua, with the choice control recorded instead of drawn. The Runtime
-- exit case uses accounting firmware and flight-controller stubs around the real
-- widgets/dashboard/runtime.lua.

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
local pageSource = readFile(SRC .. "app/pages/settings/dashboard/keys/page.lua")
local commonSource = readFile(SRC .. "app/pages/settings/common.lua")
if keysSource == nil or viewsSource == nil or runtimeSource == nil or pageSource == nil or commonSource == nil then
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

local function runtimeCancellationCaseIn(source)
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

-- The Keys page as the tool runs it: loadScript hands it the keys module under test, the real
-- settings helpers and a choice control that records its rows. Returns the page and the rows.
local function loadKeysPage(keysSrc, pageSrc)
  local rows = {}
  local modules = {
    ["widgets/dashboard/keys.lua"] = keysSrc,
    ["app/pages/settings/common.lua"] = commonSource,
  }
  local controls = {
    appendComboSelect = function(_, _, _, _, label, options, selected, onSelect)
      rows[#rows + 1] = { label = label, options = options, selected = selected, onSelect = onSelect }
      return 1
    end,
  }
  _G.loadScript = function(path)
    local rel = string.match(path, "rfsuite%-core/(.+)$")
    if rel == "ui/controls.lua" then return function() return controls end end
    local src = rel and modules[rel]
    if src == nil then return nil end
    return load(src, "@" .. rel)
  end
  local page, err = loadModule(pageSrc, "app/pages/settings/dashboard/keys/page.lua")
  return page, rows, err
end

local function keysPageCase(keysSrc, pageSrc)
  local page, rows, err = loadKeysPage(keysSrc, pageSrc)
  if page == nil then return "the Keys page did not load: " .. tostring(err) end
  local prefs = { dashboard = {} }
  local saved = 0
  local ctx = {
    preferences = prefs, x = 0, y = 0, w = 480, children = {},
    requestRebuild = function() end,
    savePreferences = function() saved = saved + 1; return true end,
  }
  page.onReload(ctx)
  page.build(ctx)
  if #rows ~= 5 then return "the page drew " .. #rows .. " key rows, expected 5" end
  local want = { "theme", "theme", "theme", "suite_tool", "menu" }
  for i = 1, 5 do
    if rows[i].selected ~= want[i] then
      return "row " .. i .. " shows " .. tostring(rows[i].selected) .. " with no preference, expected " .. want[i]
    end
  end
  -- SYS to Theme, PAGE > to Nothing; the rest stay on their defaults.
  rows[4].onSelect("theme")
  rows[1].onSelect("none")
  page.onSave(ctx)
  if saved ~= 1 then return "the page did not save" end
  local d = prefs.dashboard
  if d.key_sys ~= "theme" then return "SYS on Theme was stored as " .. tostring(d.key_sys) .. ", expected theme" end
  if d.key_page_down ~= "none" then return "PAGE > Nothing was not stored" end
  if d.key_tele ~= nil or d.key_page_up ~= nil or d.key_mdl ~= nil then
    return "a key left on its default was stored"
  end
  -- A stored default-equal value is dropped on the next save.
  prefs.dashboard.key_tele = "menu"
  page.onReload(ctx)
  page.onSave(ctx)
  if prefs.dashboard.key_tele ~= nil then return "TELE on its default stayed stored" end
  page.onClose()
end

-- The accounting stubs replace globals the other cases read (the event constants among them), so
-- the runtime case puts every global back as it found it; a later run starts from the same state.
local function runtimeCancellationCase(source)
  local saved = {}
  for k, v in pairs(_G) do saved[k] = v end
  local ok, result = pcall(runtimeCancellationCaseIn, source)
  for k in pairs(_G) do if saved[k] == nil then _G[k] = nil end end
  for k, v in pairs(saved) do _G[k] = v end
  if not ok then return "raised: " .. tostring(result) end
  return result
end

-- A mutant counts as caught only where the case written for it goes red.
local function redIn(failures, caseId)
  for i = 1, #failures do
    if failures[i].case == caseId then return failures[i] end
  end
  return nil
end

local CASES = {
  {
    id = "absent and invalid choices fall back to the key's default",
    fn = function(Keys)
      if Keys.choice("unknown", "mdl") ~= "theme" or Keys.choice({}, "pageDown") ~= "theme" then
        return "an invalid PAGE/MDL choice did not resolve to Theme"
      end
      if Keys.choice(nil, "sys") ~= "suite_tool" or Keys.choice("unknown", "tele") ~= "menu" then
        return "an absent SYS/TELE choice did not resolve to its default"
      end
      if Keys.choice("theme", "sys") ~= "theme" then return "a stored Theme on SYS was not kept" end
    end,
  },
  {
    id = "SYS and TELE default to Main menu and Quick menu over the theme",
    fn = function(Keys)
      local action, global = Keys.resolve({}, "sys", { sys = "openView:x" })
      if action ~= "openTool" or not global then return "SYS default did not open the tool" end
      action, global = Keys.resolve({}, "tele", {})
      if action ~= "openView:menu" or not global then return "TELE default did not open the menu" end
      action, global = Keys.resolve({}, "mdl", { mdl = "openView:x" })
      if action ~= "openView:x" or global then return "MDL is not the theme's by default" end
    end,
  },
  {
    id = "a key on Theme does only what the theme binds",
    fn = function(Keys)
      local dashboard = { key_sys = "theme" }
      local themeKeys = { sys = "none" }
      local action, global = Keys.resolve(dashboard, "sys", themeKeys)
      if action ~= "none" or global then return "the theme's SYS binding did not apply" end
      action, global = Keys.resolve(dashboard, "sys", {})
      if action ~= nil or global then return "an unbound SYS on Theme resolved to " .. tostring(action) end
      if themeKeys.sys ~= "none" then return "resolution mutated a theme binding table" end
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
    id = "default TELE acts before the first build and toggles the menu",
    fn = function(_, Views)
      local w = newWidget(Views)
      w._viewCtx = nil
      local handled = Views.key(w, _G.EVT_TELEM_BREAK)
      if handled ~= true or Views.top(w) ~= "menu" then return "default TELE did not open the menu" end
      handled = Views.key(w, _G.EVT_TELEM_BREAK)
      if handled ~= true or Views.top(w) ~= nil then return "default TELE did not close the menu" end
    end,
  },
  {
    id = "Theme keys yield while another view is on top",
    fn = function(_, Views)
      local w = newWidget(Views)
      w.preferences.dashboard.key_sys = "theme"
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
    id = "without a theme base only radio-wide choices act",
    fn = function(_, Views)
      local theme = newWidget(Views, false)
      if theme._viewBase ~= nil then return "the no-base fixture has a base" end
      if Views.key(theme, _G.EVT_MODEL_BREAK) ~= false then return "MDL on Theme acted without a base" end
      if Views.key(theme, _G.EVT_TELEM_BREAK) ~= true then return "default TELE did not act without a base" end
      local global = newWidget(Views, false)
      global.preferences.dashboard.key_mdl = "none"
      if Views.key(global, _G.EVT_MODEL_BREAK) ~= true then return "explicit Nothing did not act without a base" end
      global.preferences.dashboard.key_tele = "theme"
      if Views.key(global, _G.EVT_TELEM_BREAK) ~= false then return "TELE on Theme acted without a base" end
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
    id = "the Keys page shows defaults and stores only deviations",
    fn = function(Keys)
      return keysPageCase(Keys.__source, pageSource)
    end,
  },
  {
    id = "fullscreen exit cancels a pending fullscreen job",
    fn = function()
      return runtimeCancellationCase(runtimeSource)
    end,
  },
}

local function runChecks(source, quiet, pageSrc)
  local Keys, Views, err = loadPair(source)
  if Keys == nil then return { { case = "load modules", detail = tostring(err) } }, 0 end
  Keys.__source = source
  local realPage = pageSource
  if pageSrc then pageSource = pageSrc end
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
  pageSource = realPage
  return failures, passes
end

if selfTest then
  local real = runChecks(keysSource, true)
  local again = runChecks(keysSource, true)
  if #real > 0 or #again > 0 then
    print("SELF-TEST FAILED: the checks are red on the unbroken tree")
    os.exit(1)
  end
  local mutant, count = string.gsub(keysSource, "return ACTIONS%[choice%], true", "return ACTIONS[choice], false", 1)
  if count ~= 1 then
    print("SELF-TEST FAILED: the explicit-choice branch was found " .. count .. " times, expected once")
    os.exit(1)
  end
  local failures = runChecks(mutant, true)
  local hit = redIn(failures, "SYS and TELE default to Main menu and Quick menu over the theme")
  if hit == nil or #failures == 0 then
    print("SELF-TEST FAILED: treating explicit choices as Theme stayed green")
    os.exit(1)
  end
  print("(self-test) explicit-choice mutant went red: " .. hit.case .. ": " .. hit.detail)
  local noDefault, defaultCount = string.gsub(keysSource, 'default = "suite_tool"', 'default = "theme"', 1)
  if defaultCount ~= 1 then
    print("SELF-TEST FAILED: the SYS default was found " .. defaultCount .. " times, expected once")
    os.exit(1)
  end
  failures = runChecks(noDefault, true)
  hit = redIn(failures, "absent and invalid choices fall back to the key's default")
  if hit == nil then
    print("SELF-TEST FAILED: dropping the SYS default stayed green")
    os.exit(1)
  end
  print("(self-test) no-default mutant went red: " .. hit.case .. ": " .. hit.detail)
  local oldSave, saveCount = string.gsub(pageSource, "if value == entry.default then value = nil end",
    'if value == "theme" then value = nil end', 1)
  if saveCount ~= 1 then
    print("SELF-TEST FAILED: the page's default check was found " .. saveCount .. " times, expected once")
    os.exit(1)
  end
  failures = runChecks(keysSource, true, oldSave)
  hit = redIn(failures, "the Keys page shows defaults and stores only deviations")
  if hit == nil or #failures ~= 1 then
    print("SELF-TEST FAILED: storing Theme as absent stayed green, or turned other cases red")
    os.exit(1)
  end
  print("(self-test) Theme-as-absent page mutant went red: " .. hit.case .. ": " .. hit.detail)
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
  print("SELF-TEST PASSED: resolver, default, page-storage and early-exit regressions are detected")
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
