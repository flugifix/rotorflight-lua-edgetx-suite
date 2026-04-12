local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = nil
local Common = nil

-- ─── Config schema ───────────────────────────────────────────────────────────
-- Single source of truth for all persisted audio timer settings.

local CONFIG_SCHEMA = {
  { key = "timer1_alerts",     type = "bool", default = false },
  { key = "timer2_alerts",     type = "bool", default = false },
  { key = "timer3_alerts",     type = "bool", default = false },
  { key = "flight_time_alert", type = "bool", default = false },
  { key = "battery_timer",     type = "bool", default = false },
  { key = "armed_timer",       type = "bool", default = false },
  { key = "count_down_timer",  type = "bool", default = false },
  { key = "count_up_timer",    type = "bool", default = false },
  { key = "timer_bell_sound",  type = "bool", default = false },
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
    timer_alerts = true,
    flight = true,
    counting = true,
    sound = true,
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
  end
  if not t then
    t = Common.pageT("settings_audio_timer")
  end
end

local function prefBool(value, default)
  if value == nil then return default end
  return value == true or value == "true" or value == 1 or value == "1"
end

-- Loads all settings from preferences using the schema
local function copyFromPrefs(prefs)
  local audio_timer = (prefs and prefs.audio_timer) or {}
  for _, field in ipairs(CONFIG_SCHEMA) do
    local raw = audio_timer[field.key]
    if field.type == "number" then
      ui.config[field.key] = tonumber(raw) or field.default
    else
      ui.config[field.key] = prefBool(raw, field.default)
    end
  end
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
    key = "timer_alerts",
    titleKey = "section_timer_alerts",
    titleFallback = "Timer-Alarme",
    items = {
      { key = "timer1_alerts", labelKey = "timer1_alerts", labelFallback = "Timer 1 Alarme" },
      { key = "timer2_alerts", labelKey = "timer2_alerts", labelFallback = "Timer 2 Alarme" },
      { key = "timer3_alerts", labelKey = "timer3_alerts", labelFallback = "Timer 3 Alarme" },
    },
  },
  {
    key = "flight",
    titleKey = "section_flight",
    titleFallback = "Flugzeit",
    items = {
      { key = "flight_time_alert", labelKey = "flight_time_alert", labelFallback = "Flugzeit-Warnung" },
      { key = "battery_timer",     labelKey = "battery_timer",     labelFallback = "Akku-Timer" },
      { key = "armed_timer",       labelKey = "armed_timer",       labelFallback = "Armed-Zeit" },
    },
  },
  {
    key = "counting",
    titleKey = "section_counting",
    titleFallback = "Zaehlen",
    items = {
      { key = "count_down_timer", labelKey = "count_down_timer", labelFallback = "Countdown-Timer" },
      { key = "count_up_timer",   labelKey = "count_up_timer",   labelFallback = "Hochzaehler-Timer" },
    },
  },
  {
    key = "sound",
    titleKey = "section_sound",
    titleFallback = "Klang",
    items = {
      { key = "timer_bell_sound", labelKey = "timer_bell_sound", labelFallback = "Glockensound bei Timer" },
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
  if not ctx.preferences.audio_timer then ctx.preferences.audio_timer = {} end

  -- Saves all settings using the schema
  for _, field in ipairs(CONFIG_SCHEMA) do
    ctx.preferences.audio_timer[field.key] = ui.config[field.key]
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
        cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
          t(i18n, item.labelKey, item.labelFallback),
          ui.runtime.getBoolGetter(k),
          ui.runtime.getBoolSetter(k)
        )
      end
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
