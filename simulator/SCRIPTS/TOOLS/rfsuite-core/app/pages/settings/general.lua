local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = loadModule("ui/controls.lua")

-- ─── Config schema ───────────────────────────────────────────────────────────
-- Single source of truth for all persisted settings.
-- To add a setting: one entry here — loading and saving are automatic.
--   type "bool"   → stored/restored as boolean, default must be true/false
--   type "number" → stored/restored via tonumber(), default must be a number

local CONFIG_SCHEMA = {
  { key = "iconsize",                     type = "number", default = 2     },
  { key = "developer_tools",              type = "bool",   default = false  },
  { key = "syncname",                     type = "bool",   default = false  },
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
  comboOpen = nil,
  sections = {
    safety      = true,
    integration = false,
    development = false,
  },
  config = buildDefaultConfig()
}

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function t(i18n, key, fallback)
  if i18n and i18n.t then
    return i18n.t("app.pages.settings_general." .. key)
  end
  return fallback
end

local function markDirty()
  ui.dirty = true
end

local function toggleSection(name)
  ui.sections[name] = not ui.sections[name]
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
    else
      ui.config[field.key] = prefBool(raw, field.default)
    end
  end
end

local function ensureLoaded(prefs)
  if ui.loaded then return end
  copyFromPrefs(prefs)
  ui.loaded    = true
  ui.dirty     = false
  ui.comboOpen = nil
end

-- ─── Combo (icon size) ───────────────────────────────────────────────────────


local function appendComboRow(children, x, y, w, labelText, valueText, selected, onPress)
  local valueW = math.floor(w * 0.52)
  local valueX = x + w - valueW
  children[#children + 1] = { type = "label",     x = x,                    y = y + 10, w = valueX - x - 8, text = labelText,  color = WHITE,                           font = MIDSIZE }
  children[#children + 1] = { type = "button",    x = valueX,               y = y,      w = valueW,         h = 40, text = "", press = onPress, color = selected and COLOR_THEME_SECONDARY1 or GREY_DEFAULT }
  children[#children + 1] = { type = "label",     x = valueX + 8,           y = y + 10, w = valueW - 30,    text = valueText, color = selected and BLACK or WHITE, align = RIGHT, font = MIDSIZE }
  children[#children + 1] = { type = "label",     x = valueX + valueW - 20, y = y + 10, w = 14,             text = "v",       color = selected and BLACK or WHITE, align = RIGHT, font = MIDSIZE }
  children[#children + 1] = { type = "rectangle", x = x,                    y = y + 40, w = w,              h = 1,            color = GREY_DEFAULT, filled = true }
end

local function appendComboPopup(children, x, y, w, i18n, requestRebuild)
  local popupW  = math.min(380, math.floor(w * 0.52))
  local popupX  = x + w - popupW
  local optionH = 44
  children[#children + 1] = { type = "rectangle", x = popupX, y = y, w = popupW, h = optionH * #ICONSIZE_OPTIONS, color = GREY_DEFAULT, filled = true }
  for i = 1, #ICONSIZE_OPTIONS do
    local opt      = ICONSIZE_OPTIONS[i]
    local selected = opt.value == ui.config.iconsize
    children[#children + 1] = {
      type  = "button",
      x     = popupX,
      y     = y + (i - 1) * optionH,
      w     = popupW,
      h     = optionH,
      text  = t(i18n, opt.key, opt.fallback),
      color = selected and COLOR_THEME_SECONDARY1 or GREY_DEFAULT,
      press = function()
        ui.config.iconsize = opt.value
        ui.comboOpen       = nil
        markDirty()
        requestRebuild()
      end
    }
  end
end

-- ─── Section content builders ────────────────────────────────────────────────
-- Signature: (cursorY, children, x, w, i18n, requestRebuild) -> newCursorY


local function buildSafety(cursorY, children, x, w, i18n, requestRebuild)
  local items = {
    { key = "save_confirm",                 labelKey = "save_confirm",                 fallback = "Bestätigen beim Speichern"   },
    { key = "save_dirty_only",              labelKey = "save_dirty_only",              fallback = "Speichern nur bei Änderungen" },
    { key = "save_armed_warning",           labelKey = "save_armed_warning",           fallback = "Warnung beim Speichern (armed)" },
    { key = "reload_confirm",               labelKey = "reload_confirm",               fallback = "Bestätigen beim Neuladen"    },
    { key = "show_battery_profile_startup", labelKey = "show_battery_profile_startup", fallback = "Akkutyp bei Verbindung"      },
    { key = "show_confirmation_dialog",     labelKey = "show_confirmation_dialog",     fallback = "Akkutyp bestätigen"          },
  }
  for _, item in ipairs(items) do
    local k = item.key
    Controls.appendRadioSwitch(children, x, cursorY, w,
      t(i18n, item.labelKey, item.fallback),
      ui.config[k] == true,
      nil, nil,
      function()
        ui.config[k] = not ui.config[k]
        markDirty()
        requestRebuild()
      end,
      i18n
    )
    cursorY = cursorY + 44
  end
  return cursorY
end

local function buildIntegration(cursorY, children, x, w, i18n, requestRebuild)
  Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "sync_model_name", "Modellname synchronisieren"),
    ui.config.syncname == true,
    nil, nil,
    function()
      ui.config.syncname = not ui.config.syncname
      markDirty()
      requestRebuild()
    end,
    i18n
  )
  return cursorY + 44
end

local function buildDevelopment(cursorY, children, x, w, i18n, requestRebuild)
  Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "developer_tools", "Entwickler Tools"),
    ui.config.developer_tools == true,
    nil, nil,
    function()
      ui.config.developer_tools = not ui.config.developer_tools
      markDirty()
      requestRebuild()
    end,
    i18n
  )
  return cursorY + 44
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
  return { save = ui.dirty, reload = true, help = false }
end

function M.allowMemAutoRefresh()
  return ui.comboOpen == nil
end

function M.onReload(ctx)
  copyFromPrefs(ctx.preferences)
  ui.comboOpen = nil
  ui.dirty     = false
end

function M.onSave(ctx)
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
  ensureLoaded(ctx.preferences)

  local children       = ctx.children
  local x, w          = ctx.x, ctx.w
  local i18n           = ctx.i18n
  local requestRebuild = ctx.requestRebuild
  local cursorY        = ctx.y

  for i, section in ipairs(SECTIONS) do
    if i > 1 then cursorY = cursorY + 10 end

    local key = section.key
    Controls.appendSectionHeader(children, x, cursorY, w,
      t(i18n, section.titleKey, section.titleFallback),
      ui.sections[key],
      function()
        ui.comboOpen = nil
        toggleSection(key)
        requestRebuild()
      end
    )

    cursorY = cursorY + Controls.SECTION_H
    if ui.sections[key] then
      cursorY = section.build(cursorY, children, x, w, i18n, requestRebuild)
    end
  end
end

return M
