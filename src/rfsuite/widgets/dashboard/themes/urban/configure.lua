-- Settings page for this theme: which value the five rows of the right-hand panel show.
--
-- Follows the shipped default theme's configure module: load through
-- DashboardLib.getThemeConfig, save through setThemeConfig plus the per-model store, and
-- build the form with the shared Controls helpers. The source catalog itself lives in
-- layout.lua beside the rows that render it, so the page and the panel cannot drift apart.

local function loadModule(path)
  local chunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. path, "t"))
  return chunk()
end

local Controls = loadModule("ui/controls.lua")
local DashboardLib = loadModule("app/pages/settings/dashboard/lib.lua")
local Layout = loadModule("widgets/dashboard/themes/urban/layout.lua")

-- The settings page loads this file for the theme it is configuring and hands that theme to
-- the factory at the foot of this file, so a copy of this theme under rfsuite.user/dashboard
-- stores its values under its own key prefix instead of this one's. The literal is the
-- fallback for a caller that passes no theme.
local THEME_PATH = "system/urban"

local SLOT_COUNT = 5

-- The arm-state colour choice. common.lua resolves the value; the default is green and red.
local ARM_COLORS = {
  { label = "@i18n(app.pages.settings_dashboard_settings.urban_arm_signal)@", value = "signal" },
  { label = "@i18n(app.pages.settings_dashboard_settings.urban_arm_amber)@", value = "amber" },
}
local ARM_COLORS_VALID = { amber = true, signal = true }
local ARM_COLORS_DEFAULT = "signal"

-- The colour scheme: light or dark. The list and the default come from the theme itself, so
-- this page cannot offer a scheme the palettes have no colours for. The default is `light`, so
-- a page nobody has opened changes nothing.
local SCHEMES = {}
local SCHEMES_VALID = {}
for i = 1, #Layout.SCHEMES do
  SCHEMES[i] = { label = Layout.SCHEMES[i].label, value = Layout.SCHEMES[i].id }
  SCHEMES_VALID[Layout.SCHEMES[i].id] = true
end
local SCHEME_DEFAULT = Layout.DEFAULT_SCHEME

-- Everything the theme carries beyond the five rows, the scheme and the arm colours comes from
-- Layout.SETTINGS: the key, the page it is set on, the values that are valid and the default, in
-- one list that this page and the panels drawing the answers both read. A row added there
-- appears here without this file being touched, which is what stops a setting from existing on a
-- page and nowhere in the drawing, or the other way round.
--
-- The wording is the second half of the same declaration and comes from Layout.settingsLabels(),
-- which is a function for a cost reason stated there -- the widget's Lua state must not build
-- strings it never draws. This module runs in the settings tool's Lua state, so it calls it once
-- and builds the host combo's option list from the two halves together. A value the labels do
-- not cover falls back to the value itself: the page then reads oddly and works, which is the
-- right way round.
local SETTINGS = Layout.SETTINGS or {}
local SETTINGS_LABELS = (type(Layout.settingsLabels) == "function") and Layout.settingsLabels() or {}
local SETTINGS_VALID = {}
local SETTINGS_OPTIONS = {}
local SETTINGS_ROW_LABEL = {}
for i = 1, #SETTINGS do
  local entry = SETTINGS[i]
  local labels = SETTINGS_LABELS[entry.key] or {}
  local valueLabels = labels.values or {}
  local valid, options = {}, {}
  for j = 1, #entry.values do
    local value = entry.values[j]
    valid[value] = true
    options[j] = { label = valueLabels[value] or value, value = value }
  end
  SETTINGS_VALID[entry.key] = valid
  SETTINGS_OPTIONS[entry.key] = options
  SETTINGS_ROW_LABEL[entry.key] = labels.label or entry.key
end

local THEME_DEFAULTS = { arm_colors = ARM_COLORS_DEFAULT, scheme = SCHEME_DEFAULT }
for i = 1, SLOT_COUNT do
  THEME_DEFAULTS["slot" .. i] = Layout.DEFAULT_SLOTS[i]
end
for i = 1, #SETTINGS do
  THEME_DEFAULTS[SETTINGS[i].key] = SETTINGS[i].default
end

local VALID_IDS = {}
local OPTIONS = {}
for i = 1, #Layout.SOURCES do
  local src = Layout.SOURCES[i]
  VALID_IDS[src.id] = true
  OPTIONS[i] = { label = src.label, value = src.id }
end

local ui = {
  loaded = false,
  config = {}
}

local function loadConfig(prefs)
  if ui.loaded then return end

  local modelPrefs = nil
  if type(_G) == "table" and _G.rfsuite and type(_G.rfsuite.session) == "table" then
    modelPrefs = _G.rfsuite.session.modelPreferences
  end

  local cfg = DashboardLib.getThemeConfig(prefs, THEME_PATH, THEME_DEFAULTS, modelPrefs)
  for i = 1, SLOT_COUNT do
    local key = "slot" .. i
    local value = cfg[key]
    if type(value) ~= "string" or not VALID_IDS[value] then
      value = THEME_DEFAULTS[key]
    end
    ui.config[key] = value
  end

  local arm = cfg.arm_colors
  if type(arm) ~= "string" or not ARM_COLORS_VALID[arm] then arm = ARM_COLORS_DEFAULT end
  ui.config.arm_colors = arm

  local scheme = cfg.scheme
  if type(scheme) ~= "string" or not SCHEMES_VALID[scheme] then scheme = SCHEME_DEFAULT end
  ui.config.scheme = scheme

  -- Same guard for every declared row, and it is the guard that matters most for the numeric
  -- ones: they are stored as text, so a file written by hand -- or by a build of this theme
  -- that offered a value this one does not -- comes back as a string nothing on the page
  -- matches. Falling back to the default is the only answer that leaves the picture defined.
  for i = 1, #SETTINGS do
    local entry = SETTINGS[i]
    local value = cfg[entry.key]
    if type(value) == "number" then value = tostring(value) end
    if type(value) ~= "string" or not SETTINGS_VALID[entry.key][value] then
      value = entry.default
    end
    ui.config[entry.key] = value
  end
  ui.loaded = true
end

local function saveConfig(prefs)
  local session = type(_G) == "table" and _G.rfsuite and type(_G.rfsuite.session) == "table" and _G.rfsuite.session or nil
  local modelPrefs = session and session.modelPreferences

  local values = {}
  for i = 1, SLOT_COUNT do
    local key = "slot" .. i
    values[key] = ui.config[key] or THEME_DEFAULTS[key]
  end
  values.arm_colors = ui.config.arm_colors or ARM_COLORS_DEFAULT
  values.scheme = ui.config.scheme or SCHEME_DEFAULT
  for i = 1, #SETTINGS do
    local entry = SETTINGS[i]
    values[entry.key] = ui.config[entry.key] or entry.default
  end
  DashboardLib.setThemeConfig(prefs, THEME_PATH, values, modelPrefs)

  if session and session.mcu_id and modelPrefs then
    local loadMod = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/model_preferences.lua", "t")
    if type(loadMod) == "function" then
      local ok, MP = pcall(loadMod)
      if ok and type(MP) == "table" and type(MP.saveByMcuId) == "function" then
        MP.saveByMcuId(session.mcu_id, modelPrefs)
      end
    end
  end
end

local M = {}

function M.getHeaderActions()
  return { save = true, help = false }
end

function M.onReload(ctx)
  ui.loaded = false
  loadConfig(ctx.preferences)
  return true
end

function M.onSave(ctx)
  saveConfig(ctx.preferences)
  local ok, err = ctx.savePreferences()
  if ok then
    if ctx and type(ctx.reportSave) == "function" then
      local i18n = ctx.i18n
      local title = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_settings.saved_title") or "Saved"
      local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_settings.saved_message") or "Theme settings saved"
      ctx.reportSave({ ok = true, title = title, message = message })
    end
  else
    if ctx and type(ctx.reportSave) == "function" then
      local i18n = ctx.i18n
      local title = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_settings.save_error_title") or "Error"
      local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_settings.save_error_message") or "Save failed"
      ctx.reportSave({ title = title, message = message .. ": " .. tostring(err or "io") })
    end
  end
  return true
end

-- The host may hand this module a page of the theme's own `pages` table on `ctx.page`, in
-- which case only that page's section is built. `ctx.page == nil` -- a host that does not
-- know the field, or a theme entry that declared none -- means the whole page, which is what
-- the module has always built. Either way the configuration is loaded and saved whole, so a
-- page is a view of the form and never a slice of the stored values.
-- The declared rows of one page, in the order Layout.SETTINGS declares them, and one loop for
-- all of them rather than a hand-written block each: every one is the same control over the same
-- kind of value, and nine blocks would be nine chances for a row to write into another row's
-- key. Answers the cursor the caller continues from.
local function appendSettings(children, x, cursorY, w, page)
  for i = 1, #SETTINGS do
    local entry = SETTINGS[i]
    if entry.page == page then
      local key = entry.key
      cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
        SETTINGS_ROW_LABEL[key], SETTINGS_OPTIONS[key], ui.config[key],
        function(value)
          if type(value) == "string" and SETTINGS_VALID[key][value] then
            ui.config[key] = value
          end
        end)
    end
  end
  return cursorY
end

function M.build(ctx)
  loadConfig(ctx.preferences)

  -- Every id init.lua declares has to stand here as well. One that does not falls through to
  -- `only == nil`, which renders the whole form on that one tile and says nothing about it.
  local pageId = ctx and ctx.page and ctx.page.id
  local only = (pageId == "look" or pageId == "rows" or pageId == "topbar") and pageId or nil

  local children = ctx.children
  local x, y, w = ctx.x, ctx.y, ctx.w
  local cursorY = y

  if only == nil or only == "look" then
    Controls.appendSectionHeader(children, x, cursorY, w,
      "@i18n(app.pages.settings_dashboard_settings.urban_page_look)@", true, function() end)
    cursorY = cursorY + Controls.SECTION_H

    cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
      "@i18n(app.pages.settings_dashboard_settings.urban_scheme)@", SCHEMES, ui.config.scheme,
      function(value)
        if SCHEMES_VALID[value] then
          ui.config.scheme = value
        end
      end)

    cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
      "@i18n(app.pages.settings_dashboard_settings.urban_arm_colors)@", ARM_COLORS, ui.config.arm_colors,
      function(value)
        if ARM_COLORS_VALID[value] then
          ui.config.arm_colors = value
        end
      end)
  end

  if only == nil or only == "rows" then
    Controls.appendSectionHeader(children, x, cursorY, w,
      "@i18n(app.pages.settings_dashboard_settings.urban_page_rows)@", true, function() end)
    cursorY = cursorY + Controls.SECTION_H

    for i = 1, SLOT_COUNT do
      local key = "slot" .. i
      cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
        "@i18n(app.pages.settings_dashboard_settings.urban_row)@ " .. i, OPTIONS, ui.config[key],
        function(value)
          if type(value) == "string" and VALID_IDS[value] then
            ui.config[key] = value
          end
        end)
    end

    cursorY = appendSettings(children, x, cursorY, w, "rows")
  end

  if only == nil or only == "topbar" then
    Controls.appendSectionHeader(children, x, cursorY, w,
      "@i18n(app.pages.settings_dashboard_settings.urban_page_topbar)@", true, function() end)
    cursorY = cursorY + Controls.SECTION_H
    cursorY = appendSettings(children, x, cursorY, w, "topbar")
  end
end

return function(ctx)
  local theme = ctx and ctx.theme
  if type(theme) == "table" and type(theme.path) == "string" and theme.path ~= "" then
    THEME_PATH = theme.path
  end
  return M
end
