-- Settings > Dashboard > In-flight tuning.
--
-- Everything on this page is per MODEL: which switch arms the overlay, which channels and global
-- variables this model's mixer devotes to the adjustment pair, and which trims stand in for its
-- rows. So it writes into the model store keyed by the flight controller's MCU id, exactly as the
-- theme page's model override does, and says so when no flight controller is connected.
--
-- The page writes nothing into the EdgeTX model. It reads the mixer lines, the two variables and
-- the trim modes and REPORTS what is missing, because a mixer line written behind a pilot's back
-- is a control surface moving for a reason nobody can find afterwards.

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = nil
local Controls = nil
local Drive = nil

local M = {}

-- The switch picker's filters, as the firmware numbers them. Named here rather than reached for
-- as globals, following app/pages/setup_wizard/proc_radio.lua: SW_SWITCH is the physical switch
-- block, SW_NONE the empty entry that lets a pilot clear the choice. Trims are a filter of their
-- own and are deliberately not offered -- a trim is a row, not the interlock.
local SW_SWITCH = 1
local SW_NONE = 1 << 20

-- How often the setup check may walk the model again while the page is open, in getTime ticks.
local CHECK_INTERVAL_TICKS = 100

local ui = {
  loaded = false,
  dirty = false,
  sections = {
    general = true,
    wiring = false,
    trims = false,
    undo = false
  },
  config = nil,
  trimNames = nil
}

ui.runtime = nil
local t = nil

local function ensureDeps()
  if not Common then
    Common = loadModule("app/pages/settings/common.lua")
  end
  if not Controls then
    Controls = loadModule("ui/controls.lua")
  end
  if not Drive then
    Drive = loadModule("widgets/dashboard/inflight/drive.lua")
  end
  if not ui.runtime then
    ui.runtime = Common.createFormRuntime(ui)
  end
  if not t then
    t = Common.pageT("settings_dashboard_inflight")
  end
end

local function session()
  if type(_G) ~= "table" or not _G.rfsuite then return nil end
  if type(_G.rfsuite.session) ~= "table" then return nil end
  return _G.rfsuite.session
end

-- Per-model settings can only be stored while a flight controller is connected: the store is
-- keyed by its MCU id and there is no key without it.
local function hasModelStore()
  local s = session()
  return s ~= nil and s.mcu_id ~= nil
end

local function ensureLoaded()
  if ui.loaded then return end
  local s = session()
  ui.config = Drive.loadSettings(s and s.modelPreferences or nil)
  ui.probe = nil
  ui.checkAt = nil
  ui.checkResult = nil
  ui.trimNames = nil
  ui.loaded = true
end

--- One drive built against the real radio, used for the check and for the trim names. It carries
-- the settings the page is editing rather than the stored ones, so the verdict follows the field
-- the pilot has just changed instead of the one that was saved.
local function probe()
  if ui.probe == nil then
    ui.probe = Drive.newDrive(nil, ui.config)
  end
  ui.probe.settings = ui.config
  return ui.probe
end

local function trimNames()
  if ui.trimNames == nil then
    ui.trimNames = Drive.resolveTrims(probe().radio) or false
  end
  if ui.trimNames == false then return nil end
  return ui.trimNames
end

local function checkResult()
  local drive = probe()
  local now = drive.radio.now()
  if ui.checkAt == nil or (now - ui.checkAt) >= CHECK_INTERVAL_TICKS then
    ui.checkAt = now
    ui.checkResult = Drive.check(drive, ui.config)
  end
  return ui.checkResult
end

--- The verdict in one sentence, grouped by the page of the radio's own menus a pilot has to open:
-- the mixer, the global variables, the trims. A list of one line per fault reads longer and says
-- the same thing.
local function describeCheck(i18n, result)
  if result == nil then return t(i18n, "check_unchecked", "Setup not checked") end
  if result == "ok" then return t(i18n, "check_ok", "Setup OK") end
  if type(result) ~= "table" then return "" end

  local unset, mix, gvar, trim = false, false, false, false
  for i = 1, #result do
    local code = result[i]
    if string.find(code, "mix", 1, true) then
      mix = true
    elseif string.find(code, "gvar_", 1, true) then
      gvar = true
    elseif string.find(code, "trim_mode", 1, true) then
      trim = true
    else
      unset = true
    end
  end

  local parts = {}
  if unset then parts[#parts + 1] = t(i18n, "check_unset", "Switch or variables not set") end
  if mix then parts[#parts + 1] = t(i18n, "check_mix", "Mixer line missing or wrong") end
  if gvar then parts[#parts + 1] = t(i18n, "check_gvar", "Variable range or precision") end
  if trim then parts[#parts + 1] = t(i18n, "check_trim", "Trim still active in this flight mode") end
  return table.concat(parts, " / ")
end

local function markValue(key, value)
  if ui.config[key] == value then return end
  ui.config[key] = value
  ui.checkAt = nil
  ui.runtime.markValueChanged()
end

local function saveToStore()
  local s = session()
  if s == nil or s.mcu_id == nil then return false, "missing_mcu_id" end
  if type(s.modelPreferences) ~= "table" then s.modelPreferences = {} end
  if type(s.modelPreferences.inflight) ~= "table" then s.modelPreferences.inflight = {} end
  Drive.storeSettings(s.modelPreferences.inflight, ui.config)

  local MP = loadModule("lib/model_preferences.lua")
  if type(MP) ~= "table" or type(MP.saveByMcuId) ~= "function" then return false, "model_preferences" end
  return MP.saveByMcuId(s.mcu_id, s.modelPreferences)
end

function M.getHeaderActions()
  ensureDeps()
  return { save = true, help = true }
end

function M.onReload(ctx)
  ensureDeps()
  ui.loaded = false
  ui.dirty = false
  ensureLoaded()
  return true
end

function M.onSave(ctx)
  ensureDeps()
  local ok, err = saveToStore()
  if ctx and type(ctx.reportSave) == "function" then
    if ok then
      ui.dirty = false
      ctx.reportSave({
        ok = true,
        title = t(ctx.i18n, "saved_title", "Saved"),
        message = t(ctx.i18n, "saved_message", "In-flight tuning settings saved")
      })
    else
      ctx.reportSave({
        title = t(ctx.i18n, "save_error_title", "Error"),
        message = t(ctx.i18n, "save_error_message", "Save failed") .. ": " .. tostring(err or "io")
      })
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- The sections
-- ---------------------------------------------------------------------------

local function appendNote(children, x, y, w, text)
  children[#children + 1] = {
    type = "label", x = x, y = y, w = w, text = text, color = COLOR_THEME_PRIMARY1, font = SMLSIZE
  }
  return 24
end

local function buildGeneral(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "enabled", "Enabled"),
    ui.runtime.getBoolGetter("enabled"),
    ui.runtime.getBoolSetter("enabled"))

  -- The interlock. The picker stores a signed switch POSITION, which is what getSwitchValue takes,
  -- so nothing has to be resolved between what the pilot chose and what the overlay reads.
  local pickerW = 172
  if pickerW > w then pickerW = w end
  local rowH = Controls.ROW_H
  children[#children + 1] = {
    type = "label", x = x, y = Controls.labelY(cursorY, rowH), w = w - pickerW - 18,
    text = t(i18n, "switch", "Interlock switch"), color = COLOR_THEME_PRIMARY1, font = SMLSIZE
  }
  children[#children + 1] = {
    type = "switch",
    x = x + w - pickerW - 10, y = Controls.controlY(cursorY, rowH), w = pickerW, h = rowH - 6,
    filter = SW_SWITCH | SW_NONE,
    get = function() return ui.config.switch or 0 end,
    set = function(value) markValue("switch", tonumber(value) or 0) end
  }
  cursorY = cursorY + rowH

  cursorY = cursorY + appendNote(children, x, cursorY, w, describeCheck(i18n, checkResult()))
  return cursorY
end

local function appendNumber(children, x, y, w, label, key, minValue, maxValue, step)
  return Controls.appendNumberField(children, x, y, w, label, {
    min = minValue,
    max = maxValue,
    step = step or 1,
    get = function() return ui.config[key] end,
    set = function(value) markValue(key, value) end
  })
end

local function buildWiring(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + appendNote(children, x, cursorY, w,
    t(i18n, "wiring_note", "One mixer line per channel: MAX at the named variable's weight, added, no switch."))
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "bank_ch", "Enable channel"), "bank_ch", Drive.CHANNEL_MIN, Drive.CHANNEL_MAX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "value_ch", "Value channel"), "value_ch", Drive.CHANNEL_MIN, Drive.CHANNEL_MAX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "bank_gvar", "Enable variable"), "bank_gvar", 0, Drive.GVAR_MAX_INDEX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "value_gvar", "Value variable"), "value_gvar", 0, Drive.GVAR_MAX_INDEX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "pulse_ms", "Step length (ms)"), "pulse_ms", Drive.PULSE_MS_MIN, Drive.PULSE_MS_MAX, 10)
  return cursorY
end

--- The six rows against the trims that drive them.
--
-- The options carry the radio's OWN trim names where they can be read: those labels are localised
-- and renameable, so a list of fixed stems would name something else on a radio set up
-- differently. Where they cannot be read the default order stands in.
local function trimOptions(i18n)
  local resolved = trimNames()
  local options = { { value = 0, label = t(i18n, "trim_off", "Off") } }
  local defaults = {
    t(i18n, "trim_1", "Rudder"),
    t(i18n, "trim_2", "Elevator"),
    t(i18n, "trim_3", "Throttle"),
    t(i18n, "trim_4", "Aileron"),
    t(i18n, "trim_5", "T5"),
    t(i18n, "trim_6", "T6")
  }
  for index = 1, Drive.TRIM_COUNT do
    local entry = resolved and resolved[index] or nil
    local label = (entry and entry.name) or defaults[index]
    options[#options + 1] = { value = index, label = label }
  end
  return options
end

local function buildTrims(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "trims", "Drive rows from the trims"),
    ui.runtime.getBoolGetter("trims"),
    ui.runtime.getBoolSetter("trims"))

  if trimNames() == nil then
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "trims_unreadable", "This radio did not report its trims; the default order is used."))
  end

  local options = trimOptions(i18n)
  local labels = {
    t(i18n, "row_1", "Row 1"),
    t(i18n, "row_2", "Row 2"),
    t(i18n, "row_3", "Row 3"),
    t(i18n, "row_4", "Row 4"),
    t(i18n, "row_5", "Row 5"),
    t(i18n, "row_6", "Row 6")
  }
  for row = 1, Drive.TRIM_COUNT do
    local index = row
    cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
      labels[row], options, ui.config.rowTrim[index],
      function(value)
        local chosen = tonumber(value) or 0
        if ui.config.rowTrim[index] == chosen then return end
        ui.config.rowTrim[index] = chosen
        ui.checkAt = nil
        ui.runtime.markDirty()
      end)
  end
  return cursorY
end

local function buildUndo(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + appendNote(children, x, cursorY, w,
    t(i18n, "undo_note", "The board saves an in-flight change itself, shortly after disarm, so the undo has to exist beforehand."))
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "backup_profile", "Backup PID profile"), "backup_profile", 0, Drive.PROFILE_MAX)
  return cursorY
end

local SECTIONS = {
  { key = "general", titleKey = "section_general", titleFallback = "In-flight tuning", build = buildGeneral },
  { key = "wiring", titleKey = "section_wiring", titleFallback = "Channels and variables", build = buildWiring },
  { key = "trims", titleKey = "section_trims", titleFallback = "Rows and trims", build = buildTrims },
  { key = "undo", titleKey = "section_undo", titleFallback = "Undo", build = buildUndo }
}

function M.build(ctx)
  ensureDeps()
  ensureLoaded()
  ui.runtime.setRequestRebuild(ctx.requestRebuild)

  local children = ctx.children
  local x, w = ctx.x, ctx.w
  local i18n = ctx.i18n
  local cursorY = ctx.y

  if not hasModelStore() then
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "no_model", "Connect a flight controller: these settings are stored with the model."))
  end

  for i = 1, #SECTIONS do
    local section = SECTIONS[i]
    if i > 1 then cursorY = cursorY + 10 end
    Controls.appendSectionHeader(children, x, cursorY, w,
      t(i18n, section.titleKey, section.titleFallback),
      ui.sections[section.key],
      ui.runtime.getSectionToggleHandler(section.key))
    cursorY = cursorY + Controls.SECTION_H
    if ui.sections[section.key] then
      cursorY = section.build(children, x, cursorY, w, i18n)
    end
  end
end

function M.onClose()
  Common.resetPageState(ui)
  ui.probe = nil
  ui.checkResult = nil
  ui.trimNames = nil
  Controls = nil
  Common = nil
  Drive = nil
  t = nil
end

return M
