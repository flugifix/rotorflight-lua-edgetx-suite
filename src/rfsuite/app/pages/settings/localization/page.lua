local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = nil
local Common = nil

-- ─── Config schema ────────────────────────────────────────────────────────────
-- All persisted localization settings. Loading and saving are automatic.
--   type "number" → tonumber() coercion, default must be a number

local CONFIG_SCHEMA = {
  { key = "temperature_unit", type = "number", default = 0 },
  { key = "altitude_unit",    type = "number", default = 0 },
}

local function buildDefaultConfig()
  local cfg = {}
  for _, field in ipairs(CONFIG_SCHEMA) do cfg[field.key] = field.default end
  return cfg
end

-- ─── State ────────────────────────────────────────────────────────────────────

local ui = {
  loaded    = false,
  config    = buildDefaultConfig(),
}

ui.runtime = nil

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local t = nil

local function ensureDeps()
  if not Common then
    Common = loadModule("app/pages/settings/common.lua")
  end
  if not Controls then
    Controls = loadModule("ui/controls.lua")
  end
  if not ui.runtime then
    ui.runtime = Common.createFormRuntime(ui)
  end
  if not t then
    t = Common.pageT("settings_localization")
  end
end

local function copyFromPrefs(prefs)
  local loc = (prefs and prefs.localizations) or {}

  for _, field in ipairs(CONFIG_SCHEMA) do
    ui.config[field.key] = tonumber(loc[field.key]) or field.default
  end
end

local function ensureLoaded(prefs)
  if ui.loaded then return end
  copyFromPrefs(prefs)
  ui.loaded = true
end

local function getTempOptions(i18n)
  return {
    { value = 0, label = t(i18n, "temp_celsius", "Celsius") },
    { value = 1, label = t(i18n, "temp_fahrenheit", "Fahrenheit") },
  }
end

local function getAltOptions(i18n)
  return {
    { value = 0, label = t(i18n, "alt_meter", "Meter") },
    { value = 1, label = t(i18n, "alt_feet", "Feet") },
  }
end

-- ─── Module API ──────────────────────────────────────────────────────────────

function M.getHeaderActions()
  ensureDeps()
  return { save = true, help = true }
end


function M.onReload(ctx)
  ensureDeps()
  copyFromPrefs(ctx.preferences)
end

function M.onSave(ctx)
  ensureDeps()
  if not ctx.preferences.localizations then ctx.preferences.localizations = {} end

  for _, field in ipairs(CONFIG_SCHEMA) do
    ctx.preferences.localizations[field.key] = ui.config[field.key]
  end
  local ok, err = ctx.savePreferences()
  if ok then
    if lvgl and lvgl.alert then
      lvgl.alert({ title = t(ctx.i18n, "saved_title", "Gespeichert"), message = t(ctx.i18n, "saved_message", "Einstellungen gespeichert") })
    end
  else
    if lvgl and lvgl.alert then
      lvgl.alert({ title = t(ctx.i18n, "save_error_title", "Fehler"), message = t(ctx.i18n, "save_error_message", "Speichern fehlgeschlagen") .. ": " .. tostring(err or "io") })
    end
  end
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded(ctx.preferences)

  local children = ctx.children
  local x, w = ctx.x, ctx.w
  local i18n = ctx.i18n
  local cursorY = ctx.y

  ui.runtime.setRequestRebuild(ctx.requestRebuild)

  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    t(i18n, "temperature_unit", "Temperatureinheit"),
    getTempOptions(i18n),
    ui.config.temperature_unit,
    function(val)
      ui.config.temperature_unit = val
    end
  )

  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    t(i18n, "altitude_unit", "Hoeheneinheit"),
    getAltOptions(i18n),
    ui.config.altitude_unit,
    function(val)
      ui.config.altitude_unit = val
    end
  )
end

function M.onClose()
  Common.resetPageState(ui)
  Controls = nil
  Common = nil
  t = nil
end

return M
