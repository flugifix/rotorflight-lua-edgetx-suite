local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = loadModule("ui/controls.lua")

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
  config = buildDefaultConfig()
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function t(i18n, key, fallback)
  local fullKey = "app.pages.settings_audio_events." .. key
  if i18n and i18n.t then
    local translated = i18n.t(fullKey)
    if translated and translated ~= fullKey then
      return translated
    end
  end
  return fallback
end

local function markDirty(requestRebuild)
  if ui.dirty then return end
  ui.dirty = true
  if requestRebuild then
    requestRebuild()
  end
end

local function toggleSection(name)
  ui.sections[name] = not ui.sections[name]
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
      { key = "fuel_alerts", labelKey = "fuel_alerts", labelFallback = "Kraftstoff" },
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
  return { save = ui.dirty, reload = ui.dirty, help = false }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onReload(ctx)
  copyFromPrefs(ctx.preferences)
  ui.dirty = false
  return true
end

function M.onSave(ctx)
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
  ensureLoaded(ctx.preferences)

  local children       = ctx.children
  local x, w          = ctx.x, ctx.w
  local i18n           = ctx.i18n
  local requestRebuild = ctx.requestRebuild
  local cursorY        = ctx.y

  for i, section in ipairs(SECTIONS) do
    if i > 1 then cursorY = cursorY + 10 end

    Controls.appendSectionHeader(children, x, cursorY, w,
      t(i18n, section.titleKey, section.titleFallback),
      ui.sections[section.key],
      function()
        toggleSection(section.key)
        requestRebuild()
      end
    )

    cursorY = cursorY + Controls.SECTION_H
    if ui.sections[section.key] then
      for _, item in ipairs(section.items) do
        local k = item.key
        if item.kind == "number" then
          local minVal = item.min or 0
          local maxVal = item.max or 100
          cursorY = cursorY + Controls.appendNumberField(
            children, x, cursorY, w,
            t(i18n, item.labelKey, item.labelFallback),
            {
              enabled = function()
                return ui.config.esc_temperature == true
              end,
              min = minVal,
              max = maxVal,
              suffix = item.suffix or "",
              get = function()
                local current = tonumber(ui.config[k]) or minVal
                if current < minVal then current = minVal end
                if current > maxVal then current = maxVal end
                return current
              end,
              set = function(val)
                local nextVal = tonumber(val) or minVal
                if nextVal < minVal then nextVal = minVal end
                if nextVal > maxVal then nextVal = maxVal end
                if ui.config[k] ~= nextVal then
                  ui.config[k] = nextVal
                  markDirty(requestRebuild)
                end
              end
            }
          )
        else
          cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
            t(i18n, item.labelKey, item.labelFallback),
            function(nextVal)
              if nextVal ~= nil then return end
              return ui.config[k] == true
            end,
            function(nextVal)
              local nextBool = (nextVal == true)
              ui.config[k] = nextBool
              markDirty(requestRebuild)
            end
          )
        end
      end
    end
  end
end

return M
