local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = nil
local Controls = nil
local DashboardLib = nil
local Log = nil

local M = {}

local DEBUG_PREFIX = "[dashboard.theme.page] "

local function debugLog(message)
  if Log and type(Log.emit) == "function" then
    Log.emit("dashboard.theme.page", DEBUG_PREFIX .. tostring(message), "debug", true)
  end
end

local ui = {
  loaded = false,
  dirty = false,
  config = {
    theme_preflight = nil,
    theme_inflight = nil,
    theme_postflight = nil,
    model_override = false,
    model_theme_preflight = "nil",
    model_theme_inflight = "nil",
    model_theme_postflight = "nil",
  },
  themes = nil,
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
  if not DashboardLib then
    DashboardLib = loadModule("app/pages/settings/dashboard/lib.lua")
  end
  if not Log then
    Log = loadModule("lib/log.lua")
  end
  if not ui.runtime then
    ui.runtime = Common.createFormRuntime(ui)
  end
  if not t then
    t = Common.pageT("settings_dashboard_theme")
  end
end

local function refreshThemes()
  ensureDeps()
  ui.themes = DashboardLib.listThemes()
  debugLog("refreshThemes count=" .. tostring(ui.themes and #ui.themes or 0))
end

local function ensureValidSelections()
  local defaultPath = DashboardLib.getDefaultThemePath(ui.themes)
  if not defaultPath then return end

  if not DashboardLib.getThemeByPath(ui.themes, ui.config.theme_preflight) then
    ui.config.theme_preflight = defaultPath
  end
  if not DashboardLib.getThemeByPath(ui.themes, ui.config.theme_inflight) then
    ui.config.theme_inflight = defaultPath
  end
  if not DashboardLib.getThemeByPath(ui.themes, ui.config.theme_postflight) then
    ui.config.theme_postflight = defaultPath
  end

  if ui.config.model_theme_preflight ~= "nil" and not DashboardLib.getThemeByPath(ui.themes, ui.config.model_theme_preflight) then
    ui.config.model_theme_preflight = "nil"
  end
  if ui.config.model_theme_inflight ~= "nil" and not DashboardLib.getThemeByPath(ui.themes, ui.config.model_theme_inflight) then
    ui.config.model_theme_inflight = "nil"
  end
  if ui.config.model_theme_postflight ~= "nil" and not DashboardLib.getThemeByPath(ui.themes, ui.config.model_theme_postflight) then
    ui.config.model_theme_postflight = "nil"
  end
end

local function ensureLoaded(prefs)
  if ui.loaded then return end

  refreshThemes()
  local defaultPath = DashboardLib.getDefaultThemePath(ui.themes)
  local src = (prefs and prefs.dashboard) or {}

  ui.config.theme_preflight = src.theme_preflight or defaultPath
  ui.config.theme_inflight = src.theme_inflight or defaultPath
  ui.config.theme_postflight = src.theme_postflight or defaultPath
  ui.config.model_override = src.model_override == true
  ui.config.model_theme_preflight = src.model_theme_preflight or "nil"
  ui.config.model_theme_inflight = src.model_theme_inflight or "nil"
  ui.config.model_theme_postflight = src.model_theme_postflight or "nil"

  ui.loaded = true
  ui.dirty = false
end

local function getThemeId(path)
  local fallback = DashboardLib.getThemeIdByPath(ui.themes, DashboardLib.getDefaultThemePath(ui.themes), 1)
  return DashboardLib.getThemeIdByPath(ui.themes, path, fallback)
end

local function getModelThemeId(path)
  if path == nil or path == "" or path == "nil" then return 0 end
  local fallback = DashboardLib.getThemeIdByPath(ui.themes, DashboardLib.getDefaultThemePath(ui.themes), 1)
  return DashboardLib.getThemeIdByPath(ui.themes, path, fallback)
end

local function setThemeFromId(key, id)
  local theme = DashboardLib.getThemeById(ui.themes, id)
  if not theme then return end
  if ui.config[key] ~= theme.path then
    ui.config[key] = theme.path
    ui.runtime.markDirty()
  end
end

local function setModelThemeFromId(key, id)
  local numeric = tonumber(id) or 0
  local nextPath = "nil"
  if numeric ~= 0 then
    local theme = DashboardLib.getThemeById(ui.themes, numeric)
    if not theme then return end
    nextPath = theme.path
  end
  if ui.config[key] ~= nextPath then
    ui.config[key] = nextPath
    ui.runtime.markDirty()
  end
end

local function saveToPreferences(prefs)
  if not prefs.dashboard then prefs.dashboard = {} end
  prefs.dashboard.theme_preflight = ui.config.theme_preflight
  prefs.dashboard.theme_inflight = ui.config.theme_inflight
  prefs.dashboard.theme_postflight = ui.config.theme_postflight
  prefs.dashboard.model_override = ui.config.model_override == true
  prefs.dashboard.model_theme_preflight = ui.config.model_theme_preflight
  prefs.dashboard.model_theme_inflight = ui.config.model_theme_inflight
  prefs.dashboard.model_theme_postflight = ui.config.model_theme_postflight
end

function M.getHeaderActions()
  ensureDeps()
  return { save = ui.dirty, reload = true, help = false }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onReload(ctx)
  ensureDeps()
  ui.loaded = false
  ui.themes = nil
  ensureLoaded(ctx.preferences)
  ui.dirty = false
  return true
end

function M.onSave(ctx)
  ensureDeps()
  saveToPreferences(ctx.preferences)
  local ok, err = ctx.savePreferences()
  if ok then
    ui.dirty = false
  elseif lvgl and lvgl.alert then
    lvgl.alert({ title = t(ctx.i18n, "save_error_title", "Error"), message = t(ctx.i18n, "save_error_message", "Save failed") .. ": " .. tostring(err or "io") })
  end
  return true
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded(ctx.preferences)
  refreshThemes()
  ensureValidSelections()
  ui.runtime.setRequestRebuild(ctx.requestRebuild)

  debugLog("build theme count=" .. tostring(ui.themes and #ui.themes or 0) .. " preflight=" .. tostring(ui.config.theme_preflight) .. " inflight=" .. tostring(ui.config.theme_inflight) .. " postflight=" .. tostring(ui.config.theme_postflight))
  if type(ui.themes) == "table" then
    for i = 1, #ui.themes do
      local theme = ui.themes[i]
      debugLog("option[" .. tostring(i) .. "] name=" .. tostring(theme.name) .. " path=" .. tostring(theme.path))
    end
  end

  local children = ctx.children
  local x, y, w = ctx.x, ctx.y, ctx.w
  local i18n = ctx.i18n
  local cursorY = y

  if not ui.themes or #ui.themes == 0 then
    children[#children + 1] = {
      type = "label",
      x = x,
      y = y + 10,
      w = w,
      text = t(i18n, "no_themes_found", "No dashboard themes found"),
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }
    return
  end

  local themeOptions = DashboardLib.buildThemeOptions(ui.themes)
  local modelOptions = DashboardLib.buildModelThemeOptions(ui.themes, t(i18n, "model_disabled", "Disabled"))

  Controls.appendSectionHeader(children, x, cursorY, w,
    t(i18n, "section_dashboard_theme", "Dashboard Theme"), true, function() end)
  cursorY = cursorY + Controls.SECTION_H

  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    t(i18n, "theme_preflight", "Theme Preflight"),
    themeOptions,
    getThemeId(ui.config.theme_preflight),
    function(id) setThemeFromId("theme_preflight", id) end
  )

  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    t(i18n, "theme_inflight", "Theme Inflight"),
    themeOptions,
    getThemeId(ui.config.theme_inflight),
    function(id) setThemeFromId("theme_inflight", id) end
  )

  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    t(i18n, "theme_postflight", "Theme Postflight"),
    themeOptions,
    getThemeId(ui.config.theme_postflight),
    function(id) setThemeFromId("theme_postflight", id) end
  )

  cursorY = cursorY + 10
  Controls.appendSectionHeader(children, x, cursorY, w,
    t(i18n, "section_dashboard_theme_model", "Model Override"), true, function() end)
  cursorY = cursorY + Controls.SECTION_H

  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "model_override", "Model Override"),
    ui.runtime.getBoolGetter("model_override"),
    ui.runtime.getBoolSetter("model_override")
  )

  if ui.config.model_override == true then
    cursorY = cursorY + Controls.appendComboSelect(
      children, x, cursorY, w,
      t(i18n, "theme_preflight", "Theme Preflight"),
      modelOptions,
      getModelThemeId(ui.config.model_theme_preflight),
      function(id) setModelThemeFromId("model_theme_preflight", id) end
    )

    cursorY = cursorY + Controls.appendComboSelect(
      children, x, cursorY, w,
      t(i18n, "theme_inflight", "Theme Inflight"),
      modelOptions,
      getModelThemeId(ui.config.model_theme_inflight),
      function(id) setModelThemeFromId("model_theme_inflight", id) end
    )

    cursorY = cursorY + Controls.appendComboSelect(
      children, x, cursorY, w,
      t(i18n, "theme_postflight", "Theme Postflight"),
      modelOptions,
      getModelThemeId(ui.config.model_theme_postflight),
      function(id) setModelThemeFromId("model_theme_postflight", id) end
    )
  end
end

function M.onClose()
  ui.runtime = nil
  ui.themes = nil
  Controls = nil
  Common = nil
  DashboardLib = nil
  Log = nil
  t = nil
end

return M
