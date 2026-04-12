local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = nil
local Common = nil

-- ─── Config schema ───────────────────────────────────────────────────────────
-- Single source of truth for all persisted settings.
-- To add a setting: one entry here — loading and saving are automatic.
--   type "bool"   → stored/restored as boolean, default must be true/false
--   type "number" → stored/restored via tonumber(), default must be a number

local CONFIG_SCHEMA = {
  { key = "iconsize",                     type = "number", default = 2     },
  { key = "developer_tools",              type = "bool",   default = false  },
  { key = "syncname",                     type = "bool",   default = false  },
  { key = "auto_msp_telem_sync",          type = "bool",   default = false  },
  { key = "postflight_hold_seconds",      type = "number", default = 20     },
  { key = "save_confirm",                 type = "bool",   default = false  },
  { key = "save_dirty_only",              type = "bool",   default = true   },
  { key = "save_armed_warning",           type = "bool",   default = true   },
  { key = "reload_confirm",               type = "bool",   default = false  },
  { key = "show_battery_profile_startup", type = "bool",   default = true   },
  { key = "show_confirmation_dialog",     type = "bool",   default = true   },
}

-- Build ui.config defaults from schema so there is no second place to update.
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
    safety      = true,
    integration = false,
    development = false,
  },
  config = buildDefaultConfig()
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
    ui.runtime.valueGetters = {}
    ui.runtime.valueSetters = {}
  end
  if not t then
    t = Common.pageT("settings_general")
  end
end

local function prefBool(value, default)
  if value == nil then return default end
  return value == true or value == "true" or value == 1 or value == "1"
end

-- Loads all settings from preferences using the schema — no manual field list.
local function copyFromPrefs(prefs)
  local general = (prefs and prefs.general) or {}
  for _, field in ipairs(CONFIG_SCHEMA) do
    local raw = general[field.key]
    if field.type == "number" then
      ui.config[field.key] = tonumber(raw) or field.default
    elseif field.type == "string" then
      local text = tostring(raw or "")
      if text == "" then text = field.default end
      ui.config[field.key] = string.lower(text)
    else
      ui.config[field.key] = prefBool(raw, field.default)
    end
  end
  if ui.config.postflight_hold_seconds < 0 then ui.config.postflight_hold_seconds = 0 end
  if ui.config.postflight_hold_seconds > 120 then ui.config.postflight_hold_seconds = 120 end
end

local function ensureLoaded(prefs)
  if ui.loaded then return end
  copyFromPrefs(prefs)
  ui.loaded = true
  ui.dirty  = false
end

local function getValueGetter(key)
  local getter = ui.runtime.valueGetters[key]
  if getter then return getter end

  getter = function()
    return ui.config[key]
  end
  ui.runtime.valueGetters[key] = getter
  return getter
end

local function getValueSetter(key)
  local setter = ui.runtime.valueSetters[key]
  if setter then return setter end

  setter = function(value)
    if ui.config[key] == value then return end
    ui.config[key] = value
    ui.runtime.markDirty()
  end
  ui.runtime.valueSetters[key] = setter
  return setter
end

-- ─── Section content builders ────────────────────────────────────────────────
-- Signature: (cursorY, children, x, w, i18n, requestRebuild) -> newCursorY

local SAFETY_ITEMS = {
  { key = "save_confirm",                 labelKey = "save_confirm",                 fallback = "Bestätigen beim Speichern" },
  { key = "save_dirty_only",              labelKey = "save_dirty_only",              fallback = "Speichern nur bei Änderungen" },
  { key = "save_armed_warning",           labelKey = "save_armed_warning",           fallback = "Warnung beim Speichern (armed)" },
  { key = "reload_confirm",               labelKey = "reload_confirm",               fallback = "Bestätigen beim Neuladen" },
  { key = "show_battery_profile_startup", labelKey = "show_battery_profile_startup", fallback = "Akkutyp bei Verbindung" },
  { key = "show_confirmation_dialog",     labelKey = "show_confirmation_dialog",     fallback = "Akkutyp bestätigen" }
}

local function buildSafety(cursorY, children, x, w, i18n)
  for _, item in ipairs(SAFETY_ITEMS) do
    local k = item.key
    cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
      t(i18n, item.labelKey, item.fallback),
      ui.runtime.getBoolGetter(k),
      ui.runtime.getBoolSetter(k)
    )
  end
  return cursorY
end

local function buildIntegration(cursorY, children, x, w, i18n)
  local holdOptions = {
    { value = 0, label = t(i18n, "value_off", "OFF") },
    { value = 10, label = "10s" },
    { value = 20, label = "20s" },
    { value = 30, label = "30s" },
    { value = 60, label = "60s" },
    { value = 120, label = "120s" },
  }

  local function resolveHoldChoiceValue(raw)
    local current = tonumber(raw) or 20
    local nearest = holdOptions[1].value
    local nearestDiff = math.abs(current - nearest)
    for i = 2, #holdOptions do
      local v = holdOptions[i].value
      local d = math.abs(current - v)
      if d < nearestDiff then
        nearest = v
        nearestDiff = d
      end
    end
    return nearest
  end

  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "sync_model_name", "Modellname synchronisieren"),
    ui.runtime.getBoolGetter("syncname"),
    ui.runtime.getBoolSetter("syncname")
  )
  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "auto_msp_telem_sync", "MSP Telemetry automatisch abgleichen"),
    ui.runtime.getBoolGetter("auto_msp_telem_sync"),
    ui.runtime.getBoolSetter("auto_msp_telem_sync")
  )

  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    t(i18n, "postflight_hold_seconds", "Postflight halten"),
    holdOptions,
    resolveHoldChoiceValue(ui.config.postflight_hold_seconds),
    function(value)
      local nextVal = tonumber(value) or 20
      if ui.config.postflight_hold_seconds ~= nextVal then
        ui.config.postflight_hold_seconds = nextVal
        ui.runtime.markDirty()
      end
    end
  )
  return cursorY
end

local function buildDevelopment(cursorY, children, x, w, i18n)
  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "developer_tools", "Entwickler Tools"),
    ui.runtime.getBoolGetter("developer_tools"),
    ui.runtime.getBoolSetter("developer_tools")
  )
  return cursorY
end

-- ─── Section manifest ────────────────────────────────────────────────────────
-- Add new sections here — one entry, one builder function above, done.

local SECTIONS = {
  { key = "safety",      titleKey = "section_safety",      titleFallback = "Sicherheit & Prompts", build = buildSafety      },
  { key = "integration", titleKey = "section_integration", titleFallback = "Integration",         build = buildIntegration },
  { key = "development", titleKey = "section_development", titleFallback = "Entwicklung",         build = buildDevelopment },
}

-- ─── Module API ──────────────────────────────────────────────────────────────

function M.getHeaderActions()
  ensureDeps()
  return { save = ui.dirty, reload = true, help = false }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onReload(ctx)
  ensureDeps()
  copyFromPrefs(ctx.preferences)
  ui.dirty = false
end

function M.onSave(ctx)
  ensureDeps()
  if not ctx.preferences.general then ctx.preferences.general = {} end

  -- Saves all settings using the schema — no manual field list.
  for _, field in ipairs(CONFIG_SCHEMA) do
    ctx.preferences.general[field.key] = ui.config[field.key]
  end

  local ok, err = ctx.savePreferences()
  if ok then
    if ctx.menu and ctx.menu.setCondition then
      ctx.menu.setCondition("developerTools", ui.config.developer_tools == true)
    end
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
  ensureDeps()
  ensureLoaded(ctx.preferences)

  local children       = ctx.children
  local x, w          = ctx.x, ctx.w
  local i18n           = ctx.i18n
  ui.runtime.setRequestRebuild(ctx.requestRebuild)
  local cursorY        = ctx.y

  for i, section in ipairs(SECTIONS) do
    if i > 1 then cursorY = cursorY + 10 end

    local key = section.key
    Controls.appendSectionHeader(children, x, cursorY, w,
      t(i18n, section.titleKey, section.titleFallback),
      ui.sections[key],
      ui.runtime.getSectionToggleHandler(key)
    )

    cursorY = cursorY + Controls.SECTION_H
    if ui.sections[key] then
      cursorY = section.build(cursorY, children, x, w, i18n)
    end
  end
end

function M.onClose()
  ui.runtime = nil
  Controls = nil
  Common = nil
  t = nil
end

return M
