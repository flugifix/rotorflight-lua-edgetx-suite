-- EdgeTX exposes string functions without a string-method metatable.
debug.getmetatable("").__index = nil
-- Exercise the real settings controls and model store seam without MSP or radio writes.
local cache, saved, checked = {}, {}, 0
local function check(ok, message) checked = checked + 1; assert(ok, message) end
loadScript = function(path)
  local relative = string.gsub(path, "^/SCRIPTS/TOOLS/rfsuite%-core/", "")
  return assert(loadfile("src/rfsuite/" .. relative))
end
rfsuite = { session = { mcu_id = "board", isConnected = true,
  modelPreferences = { inflight = { flight_list = "18,250" } } }, require = function(path)
  assert(not string.find(path, "tasks/msp/", 1, true), "picker must not reach MSP")
  if path == "lib/env.lua" then return { isWidget = function() return true end } end
  if path == "lib/model_preferences.lua" then return { saveByMcuId = function(id, prefs)
    saved[#saved + 1] = { id = id, stored = prefs.inflight.flight_list }; return true end } end
  if not cache[path] then cache[path] = loadScript(path)() end
  return cache[path]
end }
local realLoad = loadScript
loadScript = function(path)
  if string.find(path, "lib/model_preferences.lua", 1, true) or string.find(path, "lib/env.lua", 1, true) then
    return function() return rfsuite.require(string.gsub(path, "^/SCRIPTS/TOOLS/rfsuite%-core/", "")) end
  end
  return realLoad(path)
end
SMLSIZE, MIDSIZE, CENTER = 1, 2, 0
COLOR_THEME_PRIMARY1, COLOR_THEME_SECONDARY1, COLOR_THEME_SECONDARY2 = 1, 2, 3
lvgl = { UI_ELEMENT_HEIGHT = 32 }
local F = rfsuite.require("widgets/dashboard/inflight/functions.lua")
local L = rfsuite.require("widgets/dashboard/inflight/flightlist.lua")
local Setup = rfsuite.require("widgets/dashboard/inflight/setup.lua")
-- Every standard cell carries its function's full range: the firmware clamps each step into the
-- slot's adjMin..adjMax, so a narrower band turns a first press into a jump to its edge.
local function clampStep(record, value, step)
  return math.max(record.adjMin, math.min(record.adjMax, value + step))
end
for bank = 1, F.BANK_COUNT do
  for row = 1, F.ROW_COUNT do
    local record = assert(F.standardRecord(bank, row, 5, 6))
    local fn = assert(F.byId(record.adjFunction))
    check(record.adjMin == fn.min and record.adjMax == fn.max,
      "standard cell " .. bank .. "/" .. row .. " carries the function's own range")
  end
end
local hover = assert(F.standardRecord(3, 6, 5, 6))
check(hover.adjFunction == 40 and clampStep(hover, 600, -5) == 595, "rescue hover collective steps once from 600")
check(clampStep({ adjMin = 10, adjMax = 200 }, 600, -5) == 200, "control: the documented band jumps 600 to 200")
check(clampStep(assert(F.standardRecord(3, 3, 5, 6)), 0, 5) == 5, "a D gain of 0 steps to 5, not to 10")
-- Under its group's title a name does not repeat the title; a name that does not start with it stays whole.
check(F.shortName(49) == "P-gain" and F.nameOf(49) == "Governor P-gain", "the group title is not repeated")
check(F.shortName(58) == "B-gain", "Yaw B-gain under Yaw")
check(F.shortName(39) == F.nameOf(39), "control: a name without the title as prefix is unchanged")
local layout = { set = { { 83, 18, 19 } }, bankValues = { 10 } }
local list = L.new("83,18,250", layout)
check(list.groups[1].entries[1].id == 83 and #list.groups == 3, "Cyclic precedes Roll; missing unknown in Other")
check(list.groups[3].entries[1].missing and L.checked(list, list.groups[3].entries[1]), "missing id stays listed and checked")
check(not list.groups[1].entries[1].missing, "available id is not missing")
check(L.toggle(list, 250, false) and list.stored == "18,83", "remove missing id without losing selected ids")
local target = {}
Setup.storeModelSettings(target, { flight_list = list.stored })
check(Setup.loadModelSettings({ inflight = target }).flight_list == "18,83", "parse/store round trip")
check(F.flightList(L.serialize(F.flightList("83,18,83,garbage")))[83], "normalised unique id round trip")
L.all(list); check(list.stored == "" and L.checked(list, list.groups[2].entries[2]), "all sentinel selects available rows")
check(not L.checked(list, list.groups[3].entries[1]), "all sentinel does not reselect missing ids")
check(L.toggle(list, 19, false) and list.stored == "18,83", "deselecting from all materialises the subset")
check(L.toggle(list, 19, true) and list.stored == "", "selecting all canonicalises to empty")
list = L.new("18", layout)
check(not L.toggle(list, 18, false) and list.stored == "18", "last selection cannot become all accidentally")
local fallback = L.new("", nil)
local present = {}
for _, group in ipairs(fallback.groups) do for _, entry in ipairs(group.entries) do
  check(not F.SELECTORS[entry.id] and not entry.missing, "offline fallback contains tunable functions only")
  present[entry.id] = true
end end
check(present[83] and present[84], "offline fallback includes master gains")
check(#L.new("", { set = {}, bankValues = {} }).groups == 0, "known empty FC is not the offline fallback")

local Page = rfsuite.require("app/pages/settings/dashboard/inflight/page.lua")
local function upvalue(fn, key)
  for i = 1, 100 do local name, value = debug.getupvalue(fn, i); if name == key then return value end end
  error("missing upvalue " .. key)
end
Page.getHeaderActions()
local ui = upvalue(Page.build, "ui")
local rebuilds, reports = 0, {}
local ctx = { preferences = {}, x = 0, y = 0, w = 456,
  requestRebuild = function() rebuilds = rebuilds + 1 end,
  savePreferences = function() return true end,
  reportSave = function(report) reports[#reports + 1] = report end }
Page.onReload(ctx)
ui.sections.general, ui.sections.flight = false, true
local function build()
  ctx.children = {}; Page.build(ctx)
  return ctx.children
end
build()
for _ = 1, 8 do Page.wakeup(ctx) end
local nodes = build()
check(ui.flightPicker and ui.flightFallback, "page prepares fallback lazily")
local missing
for index, group in ipairs(ui.flightPicker.groups) do
  for _, entry in ipairs(group.entries) do if entry.id == 250 then missing = index end end
end
check(missing ~= nil, "page retains stored unknown id")
ui.flightGroup = missing
nodes = build()
local marked, toggle = false, nil
for _, node in ipairs(nodes) do
  if node.type == "label" and type(node.text) == "string" and string.find(node.text, "(missing)", 1, true) then marked = true end
  if node.type == "toggle" then toggle = node end
end
check(marked, "real page labels missing id")
check(toggle and toggle.get(), "real page missing checkbox is checked")
toggle.set(false)
check(ui.flightDirty and ui.flightPicker.stored == "18", "real toggle edits only model working copy")
check(rfsuite.session.modelPreferences.inflight.flight_list == "18,250", "edit does not save early")
Page.onSave(ctx)
check(#saved == 1 and saved[1].id == "board" and saved[1].stored == "18" and not ui.dirty, "Save uses MCU model store")
ui.flightDirty = true; rfsuite.session.mcu_id = "another"
Page.onSave(ctx)
check(#saved == 1 and reports[#reports].ok ~= true, "MCU change refuses save")
Page.onClose()
check(ui.flightPicker == nil and ui.flightWork == nil, "close releases picker state")

-- Reuse a complete slot snapshot with real derivation, including a newer cyclic slot.
rfsuite.session.mcu_id = "board"
local records = { F.standardRecord(1, 1, 5, 6), F.standardRecord(1, 2, 5, 6) }
records[1].adjFunction = 83
rfsuite.session.inflightSlots = { mcu = "board", records = records, map = {}, bank = 11, value = 12 }
Page.getHeaderActions(); Page.onReload(ctx)
ui.sections.general, ui.sections.flight = false, true
build()
for _ = 1, 100 do Page.wakeup(ctx); if ui.flightPicker then break end end
check(ui.flightPicker and not ui.flightFallback, "page derives the connected FC snapshot without MSP")
check(#ui.flightPicker.groups == 2 and ui.flightPicker.groups[1].entries[1].id == 83,
  "connected offer uses actual slots and Cyclic order")
Page.onClose()

-- The sheet builds wrapped labels inside the actual scrollable help page at 480x320.
LCD_W, LCD_H = 480, 320
local HelpView = rfsuite.require("ui/help_view.lua")

-- Both actual help sheets obey the same character limits in both locales.
for _, lang in ipairs({ "en", "de" }) do
  local locale = assert(loadfile("src/rfsuite/i18n/" .. lang .. ".lua"))()
  local function translate(key)
    local value = locale
    for part in string.gmatch(key, "[^.]+") do value = value[part] end
    return value
  end
  for _, path in ipairs({ "setup/controls/inflight", "settings/dashboard/inflight" }) do
    local help = loadScript("/SCRIPTS/TOOLS/rfsuite-core/app/pages/" .. path .. "/help.lua")()({ i18n = { t = translate } }).message
    local length = utf8.len(help)
    check(length <= 600, lang .. " " .. path .. " sheet length " .. length)
    for line in string.gmatch(help, "[^\n]+") do check(utf8.len(line) <= 200, "help line <= 200") end
    local scene = HelpView.build({ contentW = 480, message = help, title = "Help" })
    check(scene[1].type == "page" and scene[1].backButton, "help remains scrollable on 480x320")
    for _, node in ipairs(scene[1].children) do
      check(node.w == 464 and node.x == nil, "help label/marker stays within 480px body")
    end
    print(lang .. " " .. path .. " help: " .. length .. " characters")
  end
end
print(checked .. " flight-list/page/help checks passed; model save and refusal controls included")
