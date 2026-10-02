-- Checks what the settings page of every shipped dashboard theme reports when it saves, offline,
-- with desktop Lua 5.3, from the repository root:
--
--   lua5.3 bin/themes/verify_save_scope.lua              the checks; exit 1 on any failure
--   lua5.3 bin/themes/verify_save_scope.lua --verbose    and one line per case
--   lua5.3 bin/themes/verify_save_scope.lua --self-test  proves the checks can go red
--
-- A theme's settings are saved into one of two stores, chosen by the page the theme was opened
-- from (docs/developer/dashboard-themes.md, `configure.lua`): a theme tile edits the radio's
-- standard values, which ctx.savePreferences() writes, and Per-Model Settings edits the connected
-- model's own values, which model_preferences.saveByMcuId writes. The save may report success only
-- when the store that carries the values was written, and a failure has to reach the pilot as a
-- translated sentence, never as a module name or an untranslated key.
--
-- Each theme's configure.lua is loaded with the real app/pages/settings/dashboard/lib.lua, the
-- edit scope is set as the settings page sets it (DashboardLib.setEditScope), and the module is
-- driven the way the page drives it: the factory, onReload, build, onSave. What is stubbed is
-- what the page and the card would answer: ui/controls.lua (every append* records and answers a
-- row height), lib/model_preferences.lua (its save succeeds, fails, or the module will not load)
-- and ctx.savePreferences (succeeds or fails). Every theme runs every case in both scopes and in
-- both locales the suite ships (en, de), and each case has one expected answer: whether
-- the page is told the save succeeded, the exact title and message it is told, how often the
-- model's file was written, and whether the values stand in the radio's preferences.
--
-- ctx.i18n answers from the real bundle of the locale under test. A key that bundle does not
-- carry is answered with the key itself -- not with the English text the suite would fall back
-- to -- so a message missing from one locale is reported rather than shown in English.
--
-- The self-test runs the same checks against two deliberately broken copies of every theme's
-- module, made in memory from its source, and fails unless each breakage turns every theme red
-- in the case it breaks:
--   * the model scope answering true after its file was refused (the scope rule undone);
--   * the reason for a module that will not load being the module's file name again.
-- A breakage whose anchor is not found in a theme's source is a self-test failure too, because a
-- copy that was not actually broken would pass for a check that cannot see the defect.
--
-- Exit status: 0 green, 1 red, 2 when the tree cannot be read.

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]themes$") or (dir .. "/../..") end
end

local verbose, selfTest = false, false
for i = 1, #arg do
  if arg[i] == "--verbose" then
    verbose = true
  elseif arg[i] == "--self-test" then
    selfTest = true
  else
    io.stderr:write("usage: lua5.3 bin/themes/verify_save_scope.lua [--verbose] [--self-test]\n")
    os.exit(2)
  end
end

local SRC = ROOT .. "/src/rfsuite/"
local CORE = "/SCRIPTS/TOOLS/rfsuite-core/"

-- The shipped themes that have a settings page. Named rather than listed from the directory, so
-- a theme that goes missing is a failure and not a smaller matrix.
local THEMES = { "default", "rfstatus", "@rt-rc", "@rt-rc-n", "@srb-rc", "@aerc", "@aerc-n", "urban" }
local LOCALES = { "en", "de" }
local SCOPES = { "standard", "model" }

local K = "app.pages.settings_dashboard_settings."
local MP_ERR = "card refused the model's file"
local GLOBAL_ERR = "card refused the radio's file"

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  return text
end

-- ---------------------------------------------------------------------------
-- Stubs
-- ---------------------------------------------------------------------------

local Controls = setmetatable({ SECTION_H = 30, ROW_H = 40 }, {
  __index = function(_, k)
    if type(k) == "string" and string.sub(k, 1, 6) == "append" then
      return function(children)
        if type(children) == "table" then children[#children + 1] = k end
        return 41
      end
    end
    return nil
  end
})

local mpMode = "ok"     -- "ok" | "fail" | "absent"
local mpCalls = 0
local MP = {}
function MP.saveByMcuId()
  mpCalls = mpCalls + 1
  if mpMode == "fail" then return false, MP_ERR end
  return true
end

_G.loadScript = function(path)
  local rel = string.sub(path, 1, #CORE) == CORE and string.sub(path, #CORE + 1) or nil
  if rel == nil then return nil end
  if rel == "ui/controls.lua" then return function() return Controls end end
  if rel == "lib/model_preferences.lua" then
    if mpMode == "absent" then return nil end
    return function() return MP end
  end
  if rel == "lib/log.lua" then return nil end
  if readFile(SRC .. rel) == nil then return nil end
  return assert(loadfile(SRC .. rel))
end

local DashboardLib = assert(loadfile(SRC .. "app/pages/settings/dashboard/lib.lua"))()

-- ---------------------------------------------------------------------------
-- Bundles
-- ---------------------------------------------------------------------------

local function lookup(bundle, key)
  local node = bundle
  for part in string.gmatch(key, "[^.]+") do
    if type(node) ~= "table" then return nil end
    node = node[part]
  end
  return type(node) == "string" and node or nil
end

local bundles = {}
for _, lang in ipairs(LOCALES) do
  local chunk = loadfile(SRC .. "i18n/" .. lang .. ".lua")
  local ok, bundle = false, nil
  if chunk then ok, bundle = pcall(chunk) end
  if not ok or type(bundle) ~= "table" then
    io.stderr:write("cannot read the " .. lang .. " bundle under " .. SRC .. "i18n/\n")
    os.exit(2)
  end
  bundles[lang] = bundle
end

local function i18nFor(lang)
  return { t = function(key) return lookup(bundles[lang], key) or key end }
end

-- What the page must be told, from the bundle under test. A key the bundle lacks yields a text
-- no module can produce, so every case that needs it fails and says which key.
local function text(lang, name)
  return lookup(bundles[lang], K .. name) or ("<" .. lang .. " bundle has no " .. K .. name .. ">")
end

-- ---------------------------------------------------------------------------
-- The cases
-- ---------------------------------------------------------------------------

local CASES = {
  { id = "connected, both writes ok",       connected = true,  mp = "ok",     global = "ok" },
  { id = "connected, model write fails",    connected = true,  mp = "fail",   global = "ok" },
  { id = "connected, model module absent",  connected = true,  mp = "absent", global = "ok" },
  { id = "connected, radio write fails",    connected = true,  mp = "ok",     global = "fail" },
  { id = "connected, both writes fail",     connected = true,  mp = "fail",   global = "fail" },
  { id = "disconnected, radio write ok",    connected = false, mp = "ok",     global = "ok" },
  { id = "disconnected, radio write fails", connected = false, mp = "ok",     global = "fail" },
}

-- Per scope and case: ok, the reason after "Save failed: " (nil for a success, else a function of
-- the locale), how often the model's file is written, and whether the values stand in the radio's
-- preferences.
local function reason(err) return function() return err end end
local EXPECT = {
  standard = {
    -- The values are in the radio's file, so its write is the answer; the model's file is
    -- rewritten beside it but carries none of them.
    ["connected, both writes ok"]       = { ok = true,  mpCalls = 1, global = true },
    ["connected, model write fails"]    = { ok = true,  mpCalls = 1, global = true },
    ["connected, model module absent"]  = { ok = true,  mpCalls = 0, global = true },
    ["connected, radio write fails"]    = { ok = false, why = reason(GLOBAL_ERR), mpCalls = 1, global = true },
    ["connected, both writes fail"]     = { ok = false, why = reason(GLOBAL_ERR), mpCalls = 1, global = true },
    ["disconnected, radio write ok"]    = { ok = true,  mpCalls = 0, global = true },
    ["disconnected, radio write fails"] = { ok = false, why = reason(GLOBAL_ERR), mpCalls = 0, global = true },
  },
  model = {
    -- The values are in the model's file, so its write is the answer, and none reach the radio's.
    ["connected, both writes ok"]       = { ok = true,  mpCalls = 1, global = false },
    ["connected, model write fails"]    = { ok = false, why = reason(MP_ERR), mpCalls = 1, global = false },
    ["connected, model module absent"]  = { ok = false, why = function(lang) return text(lang, "model_store_unavailable") end,
                                            mpCalls = 0, global = false },
    ["connected, radio write fails"]    = { ok = false, why = reason(GLOBAL_ERR), mpCalls = 1, global = false },
    ["connected, both writes fail"]     = { ok = false, why = reason(GLOBAL_ERR), mpCalls = 1, global = false },
    -- The settings page refuses this save before onSave runs (settings/page.lua); the module,
    -- asked anyway, has no model store to write and leaves the answer to the radio's file.
    ["disconnected, radio write ok"]    = { ok = true,  mpCalls = 0, global = false },
    ["disconnected, radio write fails"] = { ok = false, why = reason(GLOBAL_ERR), mpCalls = 0, global = false },
  },
}

local function countCfg(t)
  local n = 0
  for k in pairs(t or {}) do
    if string.find(k, "^cfg_") then n = n + 1 end
  end
  return n
end

-- One theme's module, from its source text; `mutate`, when given, rewrites that text first.
local function loadTheme(theme, mutate)
  local path = SRC .. "widgets/dashboard/themes/" .. theme .. "/configure.lua"
  local source = readFile(path)
  if source == nil then return nil, "cannot read " .. path end
  if mutate then
    local changed, why = mutate(source)
    if not changed then return nil, why end
    source = changed
  end
  local chunk, err = load(source, "@" .. path)
  if not chunk then return nil, err end
  return chunk
end

local function runCase(chunk, theme, scope, case, lang)
  mpMode, mpCalls = case.mp, 0
  _G.rfsuite = { session = {} }
  if case.connected then
    _G.rfsuite.session.mcu_id = "0123456789ABCDEF01234567"
    _G.rfsuite.session.modelPreferences = { dashboard = {} }
  end

  local reports, globalSaves = {}, 0
  local prefs = { dashboard = {} }
  local ctx = {
    preferences = prefs,
    theme = { path = "system/" .. theme },
    i18n = i18nFor(lang),
    x = 0, y = 0, w = 800, h = 400, children = {},
    savePreferences = function()
      globalSaves = globalSaves + 1
      if case.global == "fail" then return false, GLOBAL_ERR end
      return true
    end,
    reportSave = function(r) reports[#reports + 1] = r end,
  }

  -- The scope lives on the session, so the module's own copy of the library reads what this one
  -- sets -- the same route the settings page takes.
  DashboardLib.setEditScope(scope)
  local factory = chunk()
  local M = (type(factory) == "function") and factory(ctx) or factory
  M.onReload(ctx)
  M.build(ctx)
  M.onSave(ctx)

  return reports, globalSaves, countCfg(prefs.dashboard)
end

local function check(reports, globalSaves, globalCfg, e, lang)
  local bad = {}
  local r = reports[1] or {}
  if #reports ~= 1 then bad[#bad + 1] = "reported " .. #reports .. " times" end
  if globalSaves ~= 1 then bad[#bad + 1] = "radio's file written " .. globalSaves .. " times" end
  if (r.ok == true) ~= e.ok then bad[#bad + 1] = e.ok and "reported a failure" or "reported a success" end
  local title, message
  if e.ok then
    title, message = text(lang, "saved_title"), text(lang, "saved_message")
  else
    title = text(lang, "save_error_title")
    message = text(lang, "save_error_message") .. ": " .. e.why(lang)
  end
  if r.title ~= title then bad[#bad + 1] = string.format("title %q, expected %q", tostring(r.title), title) end
  if r.message ~= message then bad[#bad + 1] = string.format("message %q, expected %q", tostring(r.message), message) end
  local shown = tostring(r.title) .. " " .. tostring(r.message)
  if string.find(shown, "model_preferences", 1, true) then bad[#bad + 1] = "names a module file" end
  if string.find(shown, "app.pages.", 1, true) then bad[#bad + 1] = "shows an untranslated key" end
  if mpCalls ~= e.mpCalls then bad[#bad + 1] = "model's file written " .. mpCalls .. " times, expected " .. e.mpCalls end
  if (globalCfg > 0) ~= e.global then
    bad[#bad + 1] = e.global and "values missing from the radio's preferences" or "values written into the radio's preferences"
  end
  return bad, message, r.message
end

-- Runs every case; answers the failures as { theme, scope, case, lang, detail } records.
local function runMatrix(mutate, quiet)
  local failures, passes = {}, 0
  for _, theme in ipairs(THEMES) do
    local themeFailures = 0
    local chunk, loadErr = loadTheme(theme, mutate)
    if not chunk then
      failures[#failures + 1] = { theme = theme, detail = loadErr }
      themeFailures = 1
    else
      for _, lang in ipairs(LOCALES) do
        for _, scope in ipairs(SCOPES) do
          for _, case in ipairs(CASES) do
            local okRun, reports, globalSaves, globalCfg = pcall(runCase, chunk, theme, scope, case, lang)
            local bad, shown
            if not okRun then
              bad, shown = { "raised: " .. tostring(reports) }, ""
            else
              local _
              bad, _, shown = check(reports, globalSaves, globalCfg, EXPECT[scope][case.id], lang)
            end
            if #bad == 0 then
              passes = passes + 1
            else
              themeFailures = themeFailures + 1
              failures[#failures + 1] = { theme = theme, scope = scope, case = case.id, lang = lang,
                                          detail = table.concat(bad, "; ") }
            end
            if verbose and not quiet then
              print(string.format("%s %-9s %-2s %-8s %-32s %q", #bad == 0 and "PASS" or "FAIL", theme, lang,
                scope, case.id, tostring(shown)))
            end
          end
        end
      end
    end
    if not quiet then
      print(string.format("  %-9s %s", theme, themeFailures == 0 and "ok" or (themeFailures .. " case(s) failed")))
    end
  end
  return failures, passes
end

local function printFailures(failures, prefix)
  for _, f in ipairs(failures) do
    if f.case then
      print(string.format("%s%s, %s, %s scope, %s: %s", prefix, f.theme, f.lang, f.scope, f.case, f.detail))
    else
      print(string.format("%s%s: %s", prefix, f.theme, f.detail))
    end
  end
end

-- ---------------------------------------------------------------------------
-- The self-test: two broken copies, each of which must turn every theme red where it breaks
-- ---------------------------------------------------------------------------

if selfTest then
  local function replaceOnce(source, pattern, repl, what)
    local changed, n = string.gsub(source, pattern, repl)
    if n ~= 1 then return nil, "the " .. what .. " was found " .. n .. " times, expected once" end
    return changed
  end
  local breakages = {
    {
      name = "the model scope answers true after its file was refused",
      mutate = function(source)
        return replaceOnce(source, "if modelScope then return saved, err end", "if false then return saved, err end",
          "model scope's answer")
      end,
      case = "connected, model write fails", scope = "model",
    },
    {
      name = "the reason for a module that will not load is its file name",
      mutate = function(source)
        return replaceOnce(source,
          'i18n and i18n%.t and i18n%.t%("app%.pages%.settings_dashboard_settings%.model_store_unavailable"%)%s*or%s*"[^"]*"',
          '"model_preferences"', "translated reason")
      end,
      case = "connected, model module absent", scope = "model",
    },
  }
  local allFired = true
  for _, b in ipairs(breakages) do
    local failures = runMatrix(b.mutate, true)
    local missed = {}
    for _, theme in ipairs(THEMES) do
      local fired, notBroken = false, nil
      for _, f in ipairs(failures) do
        if f.theme == theme and f.case == nil then notBroken = f.detail end
        if f.theme == theme and f.case == b.case and f.scope == b.scope then fired = true end
      end
      -- A copy that could not be broken proves nothing, whatever else it did.
      if notBroken then
        missed[#missed + 1] = theme .. " (not broken: " .. notBroken .. ")"
      elseif not fired then
        missed[#missed + 1] = theme
      end
    end
    if failures[1] then printFailures({ failures[1] }, "(self-test) e.g. ") end
    if #missed > 0 then
      allFired = false
      print(string.format("SELF-TEST: '%s' did not turn red: %s", b.name, table.concat(missed, ", ")))
    else
      print(string.format("(self-test) '%s': all %d themes red in '%s' (%d failures in all)",
        b.name, #THEMES, b.case, #failures))
    end
  end
  if not allFired then
    print("SELF-TEST FAILED: a broken copy passed for a working one")
    os.exit(1)
  end
  print("SELF-TEST PASSED: both broken copies turn every theme red")
  os.exit(0)
end

-- ---------------------------------------------------------------------------
-- The checks
-- ---------------------------------------------------------------------------

print(string.format("%d themes x %d locales x %d scopes x %d cases", #THEMES, #LOCALES, #SCOPES, #CASES))
local failures, passes = runMatrix(nil, false)
if #failures > 0 then
  printFailures(failures, "FAIL: ")
  print(string.format("%d case(s) failed, %d passed", #failures, passes))
  os.exit(1)
end
print(string.format("%d cases, 0 failures", passes))
os.exit(0)
