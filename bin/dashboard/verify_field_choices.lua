-- Checks what a box theme's tiles show when the pilot chooses it: the catalogue against every
-- shipped box theme, the override the runtime applies, the key bindings, and the shared settings
-- pages through the Default theme's real configure module and the real dashboard library.
-- Desktop Lua 5.3, from the repository root:
--   lua5.3 bin/dashboard/verify_field_choices.lua
-- UI controls and the model store are stubbed; the catalogue, the override, the bindings, the
-- theme's configure module and the library's load and save are real.

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]dashboard$") or (dir .. "/../..") end
end

local SRC = ROOT .. "/src/rfsuite/"
local CORE = "/SCRIPTS/TOOLS/rfsuite-core/"
local THEMES = SRC .. "widgets/dashboard/themes/"

local assertions, failures = 0, 0
local function check(condition, name)
  assertions = assertions + 1
  if not condition then
    failures = failures + 1
    print("FAIL " .. name)
  end
end

-- Theme modules read a few radio globals at load time.
for _, name in ipairs({ "WHITE", "BLACK", "RED", "GREEN", "YELLOW", "ORANGE", "GREY", "DARKGREY",
  "LIGHTGREY", "BLUE", "DARKGREEN", "COLOR_THEME_DISABLED", "COLOR_THEME_SECONDARY1",
  "COLOR_THEME_SECONDARY2", "COLOR_THEME_SECONDARY3", "COLOR_THEME_PRIMARY1", "COLOR_THEME_PRIMARY2",
  "COLOR_THEME_FOCUS", "SMLSIZE", "MIDSIZE", "DBLSIZE", "XXLSIZE", "BOLD", "FONT_STD", "FONT_L",
  "FONT_XL", "FONT_XS", "FONT_S" }) do
  _G[name] = _G[name] or 0
end
_G.lcd = _G.lcd or { RGB = function() return 0 end }
_G.rfsuite = _G.rfsuite or { session = {} }

local Controls
local DashboardLib
local loaded = {}
_G.loadScript = function(path)
  if string.sub(path, 1, #CORE) ~= CORE then return loadfile(path) end
  local rel = string.sub(path, #CORE + 1)
  if rel == "ui/controls.lua" then return function() return Controls end end
  if rel == "app/pages/settings/dashboard/lib.lua" then return function() return DashboardLib end end
  if rel == "lib/log.lua" or rel == "lib/require.lua" then return nil end
  if rel == "lib/model_preferences.lua" then
    return function() return { saveByMcuId = function() return true end } end
  end
  if loaded[rel] == nil then loaded[rel] = assert(loadfile(SRC .. rel)) end
  return loaded[rel]
end

local Fields = assert(loadfile(SRC .. "widgets/dashboard/fields.lua"))()
local Keys = assert(loadfile(SRC .. "widgets/dashboard/keys.lua"))()

local function phaseBoxes(folder, file)
  local chunk = loadfile(THEMES .. folder .. "/" .. file)
  if not chunk then return nil end
  local ok, module = pcall(chunk)
  if not ok or type(module) ~= "table" then return nil end
  local boxes = module.boxes
  if type(boxes) == "function" then
    local built
    ok, built = pcall(boxes, nil, { themeConfig = {} })
    boxes = ok and built or nil
  end
  return boxes
end

-- 1. Every shipped box theme: every reassignable box is named uniquely within its phase, and
--    the value it shows by default is in the catalogue, so its choice never starts on nothing.
local BOX_THEMES = { "default", "rfstatus", "@aerc", "@aerc-n", "@rt-rc", "@rt-rc-n", "@srb-rc" }
local PHASES = { "preflight", "inflight", "postflight" }
local reassignable = 0
for _, folder in ipairs(BOX_THEMES) do
  for _, phase in ipairs(PHASES) do
    local boxes = phaseBoxes(folder, phase .. ".lua")
    check(type(boxes) == "table", folder .. "/" .. phase .. " declares boxes")
    local seen = {}
    for _, row in ipairs(Fields.rows(boxes, phase)) do
      reassignable = reassignable + 1
      check(not seen[row.key], folder .. "/" .. phase .. " names " .. row.key .. " once")
      seen[row.key] = true
      check(row.default ~= nil, folder .. "/" .. phase .. " " .. row.key .. " shows a catalogue value")
    end
  end
end
check(reassignable > 40, "the shipped box themes have reassignable tiles (" .. reassignable .. ")")

-- 2. The override: a copy of the chosen box, the theme's tables untouched, geometry kept.
local pre = phaseBoxes("default", "preflight.lua")
local rows = Fields.rows(pre, "preflight")
local first = rows[1]
local target
for i, box in ipairs(pre) do
  if Fields.settingKey("preflight", Fields.boxId(box)) == first.key then target = i end
end
check(target ~= nil, "the first row names a box of the phase")
local original = pre[target]
local before = {}
for k, v in pairs(original) do before[k] = v end
local chosen = (first.default == "altitude") and "current" or "altitude"
local out = Fields.apply(pre, "preflight", { [first.key] = chosen })
local entry = Fields.entry(chosen)
check(out ~= pre, "a choice yields a new list")
check(out[target] ~= original, "the chosen box is a copy")
check(out[target].source == entry.source, "the copy reads the chosen source")
check(out[target].unit == entry.unit, "the copy carries the chosen unit")
check(out[target].col == original.col and out[target].row == original.row
  and out[target].colspan == original.colspan and out[target].rowspan == original.rowspan,
  "the copy keeps the box's place")
check((original.title ~= nil) == (out[target].title ~= nil), "a caption stays where there was one, and only there")
for k, v in pairs(before) do check(original[k] == v, "the theme's box keeps " .. tostring(k)) end
for i, box in ipairs(pre) do
  if i ~= target then check(out[i] == box, "an unchosen box is the theme's own (" .. i .. ")") end
end
check(Fields.apply(pre, "preflight", { [first.key] = first.default }) == pre, "a choice of the theme's own value changes nothing")
check(Fields.apply(pre, "preflight", { [first.key] = "no_such_value" }) == pre, "an unknown choice changes nothing")
check(Fields.apply(pre, "inflight", { [first.key] = chosen }) == pre, "a choice of another phase changes nothing")
check(Fields.apply(pre, "preflight", { [first.key] = "max_current" }) == pre, "a statistic is not offered to a live tile")

local post = phaseBoxes("default", "postflight.lua")
local statRow = Fields.rows(post, "postflight")[1]
check(statRow ~= nil and statRow.list == Fields.STATS, "a statistics tile chooses from the statistics")
local statChoice = (statRow.default == "max_altitude") and "min_voltage" or "max_altitude"
local statOut = Fields.apply(post, "postflight", { [statRow.key] = statChoice })
local statBox
for _, box in ipairs(statOut) do
  if Fields.settingKey("postflight", Fields.boxId(box)) == statRow.key then statBox = box end
end
check(statBox and statBox.stattype == Fields.entry(statChoice).stattype, "a statistic carries its stattype")
check(statBox and statBox.thresholds == nil, "a chosen value drops the theme's thresholds")

-- 3. The keys a box theme's page binds, laid over its manifest's.
local declared = { exit = "exitFullscreen" }
local bound = Keys.themeBindings({ theme_key_mdl = "suite_tool", theme_key_sys = "none" }, declared)
check(bound ~= declared and bound.mdl == "openTool", "a chosen key binds the host's action")
check(bound.sys == nil, "Nothing binds nothing")
check(bound.exit == "exitFullscreen", "the manifest's bindings remain")
check(declared.mdl == nil, "the manifest's table is not written to")
check(Keys.themeBindings({}, declared) == declared, "no choice leaves the manifest's table")
local action = Keys.resolve({ key_mdl = "theme" }, "mdl", nil, bound)
check(action == "openTool", "a key on Theme resolves to the theme page's binding")

-- 4. The shared pages, through the Default theme's own configure module.
local combos
Controls = {
  SECTION_H = 30,
  appendSectionHeader = function() end,
  appendNumberField = function() return 40 end,
  appendRadioSwitch = function() return 40 end,
  appendComboSelect = function(children, x, y, w, label, options, selected, onSelect, opts)
    combos[#combos + 1] = { label = label, options = options, selected = selected, onSelect = onSelect, opts = opts }
    return 40
  end,
}
DashboardLib = assert(loadfile(SRC .. "app/pages/settings/dashboard/lib.lua"))()
local PREFIX = "cfg_system_default_"

local function openPage(pageId, prefs)
  local factory = assert(loadfile(THEMES .. "default/configure.lua"))()
  local theme = { path = "system/default", configurePath = CORE .. "widgets/dashboard/themes/default/configure.lua" }
  local module = factory({ theme = theme, page = { id = pageId } })
  combos = {}
  module.build({ children = {}, x = 0, y = 0, w = 800, preferences = prefs, page = { id = pageId } })
  return module
end

local function save(module, prefs)
  module.onSave({ preferences = prefs, savePreferences = function() return true end, reportSave = function() end })
end

DashboardLib.setEditScope(nil)
local prefs = { dashboard = {} }
local page = openPage("postflight", prefs)
local postRows = Fields.rows(post, "postflight")
check(#combos == #postRows, "the Statistics page lists every statistics tile (" .. #combos .. ")")
for i, combo in ipairs(combos) do
  check(combo.selected == postRows[i].default, "a choice starts on the theme's own value (" .. i .. ")")
  check(type(combo.opts) == "table" and type(combo.opts.helpText) == "string", "a row carries its help (" .. i .. ")")
end
combos[1].onSelect(statChoice)
save(page, prefs)
check(prefs.dashboard[PREFIX .. postRows[1].key] == statChoice, "the radio's standard stores the choice")
check(prefs.dashboard[PREFIX .. "v_min"] == nil, "a phase page saves nothing of Look")

local look = openPage("look", prefs)
check(#combos == 0, "Look shows no tile")
save(look, prefs)
check(prefs.dashboard[PREFIX .. postRows[1].key] == statChoice, "saving Look keeps the tile choices")

-- The choice reaches the runtime's configuration, as reloadActiveTheme reads it.
local cfg = DashboardLib.getThemeConfig(prefs, "system/default", {}, nil)
check(cfg[postRows[1].key] == statChoice, "the theme configuration carries the choice")

-- A model's own choice: one equal to the standard is not stored, one that deviates is.
local modelPrefs = { dashboard = {} }
_G.rfsuite.session = { mcu_id = "0123456789ABCDEF01234567", modelPreferences = modelPrefs }
DashboardLib.setEditScope("model")
local modelPage = openPage("postflight", prefs)
check(combos[1].selected == statChoice, "the model page starts on the radio's standard")
save(modelPage, prefs)
check(modelPrefs.dashboard[PREFIX .. postRows[1].key] == nil, "a model choice equal to the standard is not stored")
check(modelPrefs.dashboard[PREFIX .. postRows[2].key] == nil, "an untouched tile is not stored for the model")
modelPage = openPage("postflight", prefs)
combos[2].onSelect("max_watts")
save(modelPage, prefs)
check(modelPrefs.dashboard[PREFIX .. postRows[2].key] == "max_watts", "a model choice that deviates is stored")
DashboardLib.setEditScope(nil)
_G.rfsuite.session = {}

local keysPage = openPage("keys", prefs)
check(#combos == #Keys.THEME_KEYS, "the Keys page lists every key")
local mdlRow
for i, entry in ipairs(Keys.THEME_KEYS) do
  if entry.id == "mdl" then mdlRow = combos[i] end
  if entry.id == "sys" then
    check(combos[i].opts.active == false, "a key the radio-wide page holds is greyed")
  end
end
check(mdlRow and mdlRow.opts.active ~= false, "a key on Theme can be chosen")
mdlRow.onSelect("flight_log")
save(keysPage, prefs)
check(prefs.dashboard[PREFIX .. "theme_key_mdl"] == "flight_log", "the Keys page stores the binding")
cfg = DashboardLib.getThemeConfig(prefs, "system/default", {}, nil)
check(Keys.themeBindings(cfg, nil).mdl == "openTool:tools_flight_log_page", "the stored binding binds its action")

print(string.format("%d assertions, %d failures", assertions, failures))
os.exit(failures == 0 and 0 or 1)
