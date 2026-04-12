local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = nil
local Common = nil

-- ─── Config schema ───────────────────────────────────────────────────────────
-- Single source of truth for all persisted audio event settings.

local CONFIG_SCHEMA = {
  { key = "arming_flags",      type = "bool", default = true  },
  { key = "governor_state",    type = "bool", default = true  },
  { key = "voltage_alert",     type = "bool", default = true  },
  { key = "pid_profile",       type = "bool", default = true  },
  { key = "rate_profile",      type = "bool", default = true  },
  { key = "esc_temperature",   type = "bool", default = false },
  { key = "esc_threshold",     type = "number", default = 90  },
  { key = "adjustment_events", type = "bool", default = false },
  { key = "fuel_alerts",       type = "bool", default = true  },
  { key = "fuel_callout_percent", type = "number", default = 10 },
  { key = "fuel_repeat_below_zero", type = "number", default = 1 },
  { key = "fuel_haptic_below_zero", type = "bool", default = false },
  { key = "battery_profile",   type = "bool", default = true  },
  { key = "model_announcement",type = "bool", default = false },
}

-- Build ui.config defaults from schema
local function buildDefaultConfig()
  local cfg = {}
  for _, field in ipairs(CONFIG_SCHEMA) do
    cfg[field.key] = field.default
  end
  return cfg
end

-- ─── State ────────────────────────────────────────────────────────────────────

local ui = {
  loaded = false,
  dirty  = false,
  sections = {
    arming = true,
    governor = true,
    voltage = true,
    profiles = true,
    esc = true,
    adjustment = true,
    fuel = true,
    battery = true,
    other = true,
  },
  config = buildDefaultConfig(),
  runtime = {
    escThresholdEnabled = nil,
    escThresholdGet = nil,
    escThresholdSet = nil,
    fuelEnabled = nil,
    fuelCalloutGet = nil,
    fuelCalloutSet = nil,
    fuelRepeatGet = nil,
    fuelRepeatSet = nil,
    fuelHapticGet = nil,
    fuelHapticSet = nil
  }
}

ui.runtimeBase = nil

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local t = nil

local function ensureDeps()
  if not Common then
    Common = loadModule("app/pages/settings/common.lua")
  end
  if not Controls then
    Controls = loadModule("ui/controls.lua")
  end
  if not ui.runtimeBase then
    ui.runtimeBase = Common.createFormRuntime(ui)
    setmetatable(ui.runtime, {__index = ui.runtimeBase})
  end
  if not t then
    t = Common.pageT("settings_audio_events")
  end
end
local FUEL_CALLOUT_VALUES = { [0] = true, [5] = true, [10] = true, [20] = true, [25] = true, [50] = true }

local function getEscThresholdEnabled()
  if ui.runtime.escThresholdEnabled then return ui.runtime.escThresholdEnabled end
  ui.runtime.escThresholdEnabled = function()
    return ui.config.esc_temperature == true
  end
  return ui.runtime.escThresholdEnabled
end

local function getEscThresholdGetter(minVal, maxVal)
  if ui.runtime.escThresholdGet then return ui.runtime.escThresholdGet end
  ui.runtime.escThresholdGet = function()
    local current = tonumber(ui.config.esc_threshold) or minVal
    if current < minVal then current = minVal end
    if current > maxVal then current = maxVal end
    return current
  end
  return ui.runtime.escThresholdGet
end

local function getEscThresholdSetter(minVal, maxVal)
  if ui.runtime.escThresholdSet then return ui.runtime.escThresholdSet end
  ui.runtime.escThresholdSet = function(val)
    local nextVal = tonumber(val) or minVal
    if nextVal < minVal then nextVal = minVal end
    if nextVal > maxVal then nextVal = maxVal end
    if ui.config.esc_threshold ~= nextVal then
      ui.config.esc_threshold = nextVal
      ui.runtime.markDirty()
    end
  end
  return ui.runtime.escThresholdSet
end

local function getFuelEnabled()
  if ui.runtime.fuelEnabled then return ui.runtime.fuelEnabled end
  ui.runtime.fuelEnabled = function()
    return ui.config.fuel_alerts == true
  end
  return ui.runtime.fuelEnabled
end

local function getFuelCalloutOptions(i18n)
  return {
    { value = 0, label = t(i18n, "fuel_callout_default", "Standard") },
    { value = 5, label = t(i18n, "fuel_callout_5", "5%") },
    { value = 10, label = t(i18n, "fuel_callout_10", "10%") },
    { value = 20, label = t(i18n, "fuel_callout_20", "20%") },
    { value = 25, label = t(i18n, "fuel_callout_25", "25%") },
    { value = 50, label = t(i18n, "fuel_callout_50", "50%") },
  }
end

local function getFuelCalloutGetter()
  if ui.runtime.fuelCalloutGet then return ui.runtime.fuelCalloutGet end
  ui.runtime.fuelCalloutGet = function()
    local value = tonumber(ui.config.fuel_callout_percent) or 10
    if not FUEL_CALLOUT_VALUES[value] then return 10 end
    return value
  end
  return ui.runtime.fuelCalloutGet
end

local function getFuelCalloutSetter()
  if ui.runtime.fuelCalloutSet then return ui.runtime.fuelCalloutSet end
  ui.runtime.fuelCalloutSet = function(value)
    if ui.config.fuel_alerts ~= true then return end
    local nextValue = tonumber(value) or 10
    if not FUEL_CALLOUT_VALUES[nextValue] then nextValue = 10 end
    if ui.config.fuel_callout_percent ~= nextValue then
      ui.config.fuel_callout_percent = nextValue
      ui.runtime.markDirty()
    end
  end
  return ui.runtime.fuelCalloutSet
end

local function getFuelRepeatGetter(minVal, maxVal)
  if ui.runtime.fuelRepeatGet then return ui.runtime.fuelRepeatGet end
  ui.runtime.fuelRepeatGet = function()
    local current = tonumber(ui.config.fuel_repeat_below_zero) or minVal
    if current < minVal then current = minVal end
    if current > maxVal then current = maxVal end
    return current
  end
  return ui.runtime.fuelRepeatGet
end

local function getFuelRepeatSetter(minVal, maxVal)
  if ui.runtime.fuelRepeatSet then return ui.runtime.fuelRepeatSet end
  ui.runtime.fuelRepeatSet = function(value)
    if ui.config.fuel_alerts ~= true then return end
    local nextValue = tonumber(value) or minVal
    if nextValue < minVal then nextValue = minVal end
    if nextValue > maxVal then nextValue = maxVal end
    if ui.config.fuel_repeat_below_zero ~= nextValue then
      ui.config.fuel_repeat_below_zero = nextValue
      ui.runtime.markDirty()
    end
  end
  return ui.runtime.fuelRepeatSet
end

local function getFuelHapticGetter()
  if ui.runtime.fuelHapticGet then return ui.runtime.fuelHapticGet end
  ui.runtime.fuelHapticGet = function(nextVal)
    if nextVal ~= nil then return end
    return ui.config.fuel_alerts == true and ui.config.fuel_haptic_below_zero == true
  end
  return ui.runtime.fuelHapticGet
end

local function getFuelHapticSetter()
  if ui.runtime.fuelHapticSet then return ui.runtime.fuelHapticSet end
  ui.runtime.fuelHapticSet = function(nextVal)
    if ui.config.fuel_alerts ~= true then return end
    local nextBool = (nextVal == true)
    if ui.config.fuel_haptic_below_zero ~= nextBool then
      ui.config.fuel_haptic_below_zero = nextBool
      ui.runtime.markDirty()
    end
  end
  return ui.runtime.fuelHapticSet
end

local function prefBool(value, default)
  if value == nil then return default end
  return value == true or value == "true" or value == 1 or value == "1"
end

-- Loads all settings from preferences using the schema
local function copyFromPrefs(prefs)
  local audio_events = (prefs and prefs.audio_events) or {}
  for _, field in ipairs(CONFIG_SCHEMA) do
    local raw = audio_events[field.key]
    if field.type == "number" then
      ui.config[field.key] = tonumber(raw) or field.default
    else
      ui.config[field.key] = prefBool(raw, field.default)
    end
  end

  if ui.config.esc_threshold < 60 then ui.config.esc_threshold = 60 end
  if ui.config.esc_threshold > 300 then ui.config.esc_threshold = 300 end
  if not FUEL_CALLOUT_VALUES[ui.config.fuel_callout_percent] then ui.config.fuel_callout_percent = 10 end
  if ui.config.fuel_repeat_below_zero < 1 then ui.config.fuel_repeat_below_zero = 1 end
  if ui.config.fuel_repeat_below_zero > 10 then ui.config.fuel_repeat_below_zero = 10 end
end

local function ensureLoaded(prefs)
  if ui.loaded then return end
  copyFromPrefs(prefs)
  ui.loaded = true
  ui.dirty  = false
end

-- ─── Settings items ──────────────────────────────────────────────────────────

local SECTIONS = {
  {
    key = "arming",
    titleKey = "section_arming",
    titleFallback = "Arming-Flags",
    items = {
      { key = "arming_flags", labelKey = "arming_flags", labelFallback = "Arming-Flags" },
    },
  },
  {
    key = "governor",
    titleKey = "section_governor",
    titleFallback = "Governor-Status",
    items = {
      { key = "governor_state", labelKey = "governor_state", labelFallback = "Governor-Status" },
    },
  },
  {
    key = "voltage",
    titleKey = "section_voltage",
    titleFallback = "Spannung",
    items = {
      { key = "voltage_alert", labelKey = "voltage_alert", labelFallback = "Spannung" },
    },
  },
  {
    key = "profiles",
    titleKey = "section_profiles",
    titleFallback = "PID/Raten-Profil",
    items = {
      { key = "pid_profile",  labelKey = "pid_profile",  labelFallback = "PID-Profil" },
      { key = "rate_profile", labelKey = "rate_profile", labelFallback = "Raten-Profil" },
    },
  },
  {
    key = "esc",
    titleKey = "section_esc",
    titleFallback = "ESC-Temperatur",
    items = {
      { kind = "bool", key = "esc_temperature", labelKey = "esc_temperature", labelFallback = "ESC-Temperatur" },
      { kind = "number", key = "esc_threshold", labelKey = "esc_threshold", labelFallback = "Schwellwert (deg)", min = 60, max = 300, suffix = "°" },
    },
  },
  {
    key = "adjustment",
    titleKey = "section_adjustment",
    titleFallback = "Einstellungsansagen",
    items = {
      { key = "adjustment_events", labelKey = "adjustment_events", labelFallback = "Einstellungsansagen" },
    },
  },
  {
    key = "fuel",
    titleKey = "section_fuel",
    titleFallback = "Kraftstoff",
    items = {
      { kind = "bool", key = "fuel_alerts", labelKey = "fuel_alerts", labelFallback = "Kraftstoff" },
      { kind = "choice", key = "fuel_callout_percent", labelKey = "fuel_callout_percent", labelFallback = "Ansage %" },
      { kind = "number", key = "fuel_repeat_below_zero", labelKey = "fuel_repeat_below_zero", labelFallback = "Wiederholungen unter 0%", min = 1, max = 10, suffix = "x" },
      { kind = "bool", key = "fuel_haptic_below_zero", labelKey = "fuel_haptic_below_zero", labelFallback = "Haptisch unter 0%" },
    },
  },
  {
    key = "battery",
    titleKey = "section_battery",
    titleFallback = "Akku",
    items = {
      { key = "battery_profile", labelKey = "battery_profile", labelFallback = "Akku-Kapazitaet" },
    },
  },
  {
    key = "other",
    titleKey = "section_other",
    titleFallback = "Sonstiges",
    items = {
      { key = "model_announcement", labelKey = "model_announcement", labelFallback = "Modellansage" },
    },
  },
}

-- ─── Module API ──────────────────────────────────────────────────────────────

function M.getHeaderActions()
  ensureDeps()
  return { save = ui.dirty, reload = ui.dirty, help = false }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onReload(ctx)
  ensureDeps()
  copyFromPrefs(ctx.preferences)
  ui.dirty = false
  return true
end

function M.onSave(ctx)
  ensureDeps()
  if not ctx.preferences.audio_events then ctx.preferences.audio_events = {} end

  -- Saves all settings using the schema
  for _, field in ipairs(CONFIG_SCHEMA) do
    ctx.preferences.audio_events[field.key] = ui.config[field.key]
  end

  local ok, err = ctx.savePreferences()
  if ok then
    ui.dirty = false
    return true
  else
    if lvgl and lvgl.alert then
      lvgl.alert({ title = t(ctx.i18n, "save_error_title", "Fehler"), message = t(ctx.i18n, "save_error_message", "Speichern fehlgeschlagen") .. ": " .. tostring(err or "io") })
    end
    return true
  end
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded(ctx.preferences)

  local children       = ctx.children
  local x, w          = ctx.x, ctx.w
  local i18n           = ctx.i18n
  ui.runtime.setRequestRebuild(ctx.requestRebuild)
  local cursorY        = ctx.y

  for i, section in ipairs(SECTIONS) do
    if i > 1 then cursorY = cursorY + 10 end

    Controls.appendSectionHeader(children, x, cursorY, w,
      t(i18n, section.titleKey, section.titleFallback),
      ui.sections[section.key],
      ui.runtime.getSectionToggleHandler(section.key)
    )

    cursorY = cursorY + Controls.SECTION_H
    if ui.sections[section.key] then
      for _, item in ipairs(section.items) do
        local k = item.key
        if item.kind == "choice" and k == "fuel_callout_percent" then
          cursorY = cursorY + Controls.appendComboSelect(
            children, x, cursorY, w,
            t(i18n, item.labelKey, item.labelFallback),
            getFuelCalloutOptions(i18n),
            getFuelCalloutGetter()(),
            getFuelCalloutSetter()
          )
        elseif item.kind == "number" and k == "fuel_repeat_below_zero" then
          local minVal = item.min or 1
          local maxVal = item.max or 10
          cursorY = cursorY + Controls.appendNumberField(
            children, x, cursorY, w,
            t(i18n, item.labelKey, item.labelFallback),
            {
              enabled = getFuelEnabled(),
              min = minVal,
              max = maxVal,
              suffix = item.suffix or "",
              get = getFuelRepeatGetter(minVal, maxVal),
              set = getFuelRepeatSetter(minVal, maxVal)
            }
          )
        elseif item.kind == "number" then
          local minVal = item.min or 0
          local maxVal = item.max or 100
          cursorY = cursorY + Controls.appendNumberField(
            children, x, cursorY, w,
            t(i18n, item.labelKey, item.labelFallback),
            {
              enabled = getEscThresholdEnabled(),
              min = minVal,
              max = maxVal,
              suffix = item.suffix or "",
              get = getEscThresholdGetter(minVal, maxVal),
              set = getEscThresholdSetter(minVal, maxVal)
            }
          )
        elseif item.kind == "bool" and k == "fuel_haptic_below_zero" then
          cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
            t(i18n, item.labelKey, item.labelFallback),
            getFuelHapticGetter(),
            getFuelHapticSetter()
          )
        else
          cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
            t(i18n, item.labelKey, item.labelFallback),
            ui.runtime.getBoolGetter(k),
            ui.runtime.getBoolSetter(k)
          )
        end
      end
    end
  end
end

function M.onClose()
  if type(ui.runtime) == "table" then
    setmetatable(ui.runtime, nil)
  end
  Common.resetPageState(ui, {
    tablesToWipe = { "sections", "runtime" }
  })
  ui.runtimeBase = nil
  Controls = nil
  Common = nil
  t = nil
end

return M
