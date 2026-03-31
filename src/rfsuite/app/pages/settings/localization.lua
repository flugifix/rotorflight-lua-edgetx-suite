local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = loadModule("ui/controls.lua")

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
  dirty     = false,
  config    = buildDefaultConfig(),
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function t(i18n, key, fallback)
  if i18n and i18n.t then return i18n.t("app.pages.settings_localization." .. key) end
  return fallback
end

local function markDirty(requestRebuild)
  if ui.dirty then return end
  ui.dirty = true
  if requestRebuild then
    requestRebuild()
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
  ui.dirty  = false
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

-- ─── Section builder ─────────────────────────────────────────────────────────

local function buildLocalization(cursorY, children, x, w, i18n, requestRebuild)
  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    t(i18n, "temperature_unit", "Temperatureinheit"),
    getTempOptions(i18n),
    ui.config.temperature_unit,
    false,
    nil,
    function(val)
      ui.config.temperature_unit = val
      markDirty(requestRebuild)
    end
  )

  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    t(i18n, "altitude_unit", "Hoeheneinheit"),
    getAltOptions(i18n),
    ui.config.altitude_unit,
    false,
    nil,
    function(val)
      ui.config.altitude_unit = val
      markDirty(requestRebuild)
    end
  )

  return cursorY
end

-- ─── Module API ──────────────────────────────────────────────────────────────

function M.getHeaderActions()
  return { save = ui.dirty, reload = true, help = false }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onReload(ctx)
  copyFromPrefs(ctx.preferences)
  ui.dirty = false
end

function M.onSave(ctx)
  if not ctx.preferences.localizations then ctx.preferences.localizations = {} end
  for _, field in ipairs(CONFIG_SCHEMA) do
    ctx.preferences.localizations[field.key] = ui.config[field.key]
  end
  local ok, err = ctx.savePreferences()
  if ok then
    ui.dirty = false
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
  ensureLoaded(ctx.preferences)

  local children       = ctx.children
  local x, w           = ctx.x, ctx.w
  local i18n           = ctx.i18n
  local requestRebuild = ctx.requestRebuild
  local cursorY        = ctx.y

  buildLocalization(cursorY, children, x, w, i18n, requestRebuild)
end

return M
