local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = nil
local Common = nil

-- ─── Config schema ───────────────────────────────────────────────────────────
-- Single source of truth for all persisted audio switch settings.

local CONFIG_SCHEMA = {
  { key = "flight_mode_switch",    type = "bool", default = false },
  { key = "arm_disarm_switch",     type = "bool", default = false },
  { key = "stabilize_mode_switch", type = "bool", default = false },
  { key = "acro_mode_switch",      type = "bool", default = false },
  { key = "altitude_hold_switch",  type = "bool", default = false },
  { key = "position_hold_switch",  type = "bool", default = false },
  { key = "return_to_home_switch", type = "bool", default = false },
  { key = "channel_6_switch",      type = "bool", default = false },
  { key = "switch_feedback",       type = "bool", default = false },
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
  sections = {
    core = true,
    modes = true,
    hold = true,
    extras = true,
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
    t = Common.pageT("settings_audio_switches")
  end
end

local function prefBool(value, default)
  if value == nil then return default end
  return value == true or value == "true" or value == 1 or value == "1"
end

-- Loads all settings from preferences using the schema
local function copyFromPrefs(prefs)
  local audio_switches = (prefs and prefs.audio_switches) or {}
  for _, field in ipairs(CONFIG_SCHEMA) do
    local raw = audio_switches[field.key]
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
end

-- ─── Settings items ──────────────────────────────────────────────────────────

local SECTIONS = {
  {
    key = "core",
    titleKey = "section_core",
    titleFallback = "Hauptschalter",
    items = {
      { key = "flight_mode_switch", labelKey = "flight_mode_switch", labelFallback = "Flugmodus-Schalter" },
      { key = "arm_disarm_switch",  labelKey = "arm_disarm_switch",  labelFallback = "Arm/Disarm" },
    },
  },
  {
    key = "modes",
    titleKey = "section_modes",
    titleFallback = "Flugmodi",
    items = {
      { key = "stabilize_mode_switch", labelKey = "stabilize_mode_switch", labelFallback = "Stabilisierungsmodus" },
      { key = "acro_mode_switch",      labelKey = "acro_mode_switch",      labelFallback = "Acro-Modus" },
    },
  },
  {
    key = "hold",
    titleKey = "section_hold",
    titleFallback = "Hold-Funktionen",
    items = {
      { key = "altitude_hold_switch",  labelKey = "altitude_hold_switch",  labelFallback = "Hoehenhaltung" },
      { key = "position_hold_switch",  labelKey = "position_hold_switch",  labelFallback = "Positionshaltung" },
      { key = "return_to_home_switch", labelKey = "return_to_home_switch", labelFallback = "Rueckkehr nach Hause" },
    },
  },
  {
    key = "extras",
    titleKey = "section_extras",
    titleFallback = "Sonstiges",
    items = {
      { key = "channel_6_switch", labelKey = "channel_6_switch", labelFallback = "Kanal 6" },
      { key = "switch_feedback",  labelKey = "switch_feedback",  labelFallback = "Schalter-Rueckmeldung" },
    },
  },
}

-- ─── Module API ──────────────────────────────────────────────────────────────

function M.getHeaderActions()
  ensureDeps()
  return { save = true, help = true }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onReload(ctx)
  ensureDeps()
  copyFromPrefs(ctx.preferences)
  return true
end

function M.onSave(ctx)
  ensureDeps()
  if not ctx.preferences.audio_switches then ctx.preferences.audio_switches = {} end

  -- Saves all settings using the schema
  for _, field in ipairs(CONFIG_SCHEMA) do
    ctx.preferences.audio_switches[field.key] = ui.config[field.key]
  end

  local ok, err = ctx.savePreferences()
  if ok then
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
  Common.resetPageState(ui, {
    tablesToWipe = { "sections" }
  })
  Controls = nil
  Common = nil
  t = nil
end

return M
