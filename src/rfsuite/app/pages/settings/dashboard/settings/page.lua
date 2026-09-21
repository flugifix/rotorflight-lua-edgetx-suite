
local loadedModules = {}
local loadedThemeConfigs = {}
local function loadModule(path)
  if loadedModules[path] then return loadedModules[path] end
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  local mod = chunk()
  loadedModules[path] = mod
  return mod
end

local function loadThemeConfig(configurePath)
  local cached = loadedThemeConfigs[configurePath]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end
  local ok, chunk = pcall(loadScript, configurePath, "t")
  if not ok or type(chunk) ~= "function" then
    loadedThemeConfigs[configurePath] = false
    return nil
  end
  local loadedOk, loaded = pcall(chunk)
  if not loadedOk then
    loadedThemeConfigs[configurePath] = false
    return nil
  end
  loadedThemeConfigs[configurePath] = loaded
  return loaded
end

local Common = nil
local DashboardLib = nil

local M = {}

local ui = {
  loaded = false,
  themes = nil,
  configurableThemes = nil,
  activeThemeConfigPath = nil,
  activePageId = nil,
  activePage = nil,
  activeTheme = nil,
  activeModule = nil,
}

ui.runtime = nil
local t = nil

local function ensureDeps()
  if not Common then
    Common = loadModule("app/pages/settings/common.lua")
  end
  if not DashboardLib then
    DashboardLib = loadModule("app/pages/settings/dashboard/lib.lua")
  end
  if not ui.runtime then
    ui.runtime = Common.createFormRuntime(ui)
  end
  if not t then
    t = Common.pageT("settings_dashboard_settings")
  end
end

local function hexDecode(input)
  if type(input) ~= "string" or input == "" then return nil end
  if #input % 2 ~= 0 then return nil end
  local out = {}
  for i = 1, #input, 2 do
    local byte = tonumber(string.sub(input, i, i + 1), 16)
    if not byte then return nil end
    out[#out + 1] = string.char(byte)
  end
  return table.concat(out)
end

-- The menu id carries the theme, and for a theme that splits its settings it carries the page
-- as well. The theme token is hexadecimal and so holds no underscore, which is what keeps the
-- two apart however many underscores a page id has.
local function themePathFromMenu(ctx)
  local menu = ctx and ctx.menu
  local menuId = menu and menu.getCurrentMenuId and menu.getCurrentMenuId() or nil
  if type(menuId) ~= "string" then return nil end

  local token = string.match(menuId, "^settings_dashboard_settings_([0-9a-f]+)_page$")
  if token then return hexDecode(token) end

  local pageToken, pageId = string.match(menuId, "^settings_dashboard_settings_([0-9a-f]+)_([a-z0-9_]+)_page$")
  if pageToken then return hexDecode(pageToken), pageId end

  return nil
end

-- What the theme declared for the page this menu id names, so the module is told the page by
-- the same title the tile was drawn with. A page id the theme no longer declares resolves to
-- nothing, and the module is then called exactly as a theme without pages is.
local function findThemePage(theme, pageId)
  if type(pageId) ~= "string" or type(theme) ~= "table" or type(theme.pages) ~= "table" then
    return nil
  end
  for i = 1, #theme.pages do
    local page = theme.pages[i]
    if page.id == pageId then
      return { id = page.id, title = page.title }
    end
  end
  return nil
end

-- Every context the theme's module is handed carries the page, not only the factory's: a module
-- returned as a plain table never sees the factory context, and reads the page inside `build`.
local function setContextPage(ctx)
  if type(ctx) == "table" then
    ctx.page = ui.activePage
  end
end

local function ensureThemes()
  ensureDeps()
  ui.themes = DashboardLib.listThemes()
  ui.configurableThemes = DashboardLib.getConfigurableThemes(ui.themes)
end

local function ensureLoaded(prefs)
  if ui.loaded then return end
  ensureThemes()

  ui.loaded = true
end

local function loadThemeModule(ctx)
  ensureThemes()

  local path, pageId = themePathFromMenu(ctx)
  if type(path) ~= "string" or path == "" then
    ui.activeThemeConfigPath = nil
    ui.activePageId = nil
    ui.activePage = nil
    ui.activeTheme = nil
    ui.activeModule = nil
    setContextPage(ctx)
    return nil
  end

  if ui.activeThemeConfigPath == path and ui.activePageId == pageId and ui.activeModule ~= nil then
    setContextPage(ctx)
    return ui.activeModule
  end

  local theme = DashboardLib.getThemeByPath(ui.configurableThemes, path)
  ui.activeThemeConfigPath = path
  ui.activePageId = pageId
  ui.activePage = findThemePage(theme, pageId)
  ui.activeTheme = theme
  ui.activeModule = false
  setContextPage(ctx)

  if not theme or type(theme.configurePath) ~= "string" or theme.configurePath == "" then
    return nil
  end

  local loaded = loadThemeConfig(theme.configurePath)
  if type(loaded) == "function" then
    local createdOk, created = pcall(loaded, {
      theme = theme,
      page = ui.activePage,
      preferences = ctx and ctx.preferences or nil,
      i18n = ctx and ctx.i18n or nil,
      dashboardLib = DashboardLib,
    })
    if createdOk then
      loaded = created
    else
      loaded = nil
    end
  end
  if type(loaded) ~= "table" then
    loaded = {}
  end
  ui.activeModule = loaded
  return loaded
end

function M.getHeaderActions()
  -- Save und Reload immer aktiv für Theme-Settings
  return { save = true, reload = true, help = true }
end


function M.onReload(ctx)
  ensureDeps()
  ui.loaded = false
  ui.themes = nil
  ui.configurableThemes = nil
  ui.activeThemeConfigPath = nil
  ui.activePageId = nil
  ui.activePage = nil
  ui.activeTheme = nil
  ui.activeModule = nil

  ensureLoaded(ctx.preferences)
  local module = loadThemeModule(ctx)
  if type(module) == "table" and type(module.onReload) == "function" then
    return module.onReload(ctx)
  end
  return true
end

function M.onSave(ctx)
  ensureDeps()
  local module = loadThemeModule(ctx)
  if type(module) == "table" then
    if type(module.onSave) == "function" then
      return module.onSave(ctx)
    end
    if type(module.write) == "function" then
      local okWrite = pcall(module.write, ctx)
      if not okWrite then
        return true
      end
      local ok, err = ctx.savePreferences()
      if not ok and ctx and type(ctx.reportSave) == "function" then
        ctx.reportSave({ title = t(ctx.i18n, "save_error_title", "Error"), message = t(ctx.i18n, "save_error_message", "Save failed") .. ": " .. tostring(err or "io") })
      end
      return true
    end
  end
  return true
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded(ctx.preferences)
  ui.runtime.setRequestRebuild(ctx.requestRebuild)

  local module = loadThemeModule(ctx)
  if type(module) == "table" then
    if type(module.build) == "function" then
      module.build(ctx)
      return
    end
    if type(module.configure) == "function" then
      module.configure(ctx)
      return
    end
    if ui.activeTheme ~= nil then
      return
    end
  end

  local children = ctx.children
  local x, y, w = ctx.x, ctx.y, ctx.w
  local i18n = ctx.i18n
  local labelY = y + 10

  children[#children + 1] = {
    type = "label",
    x = x,
    y = labelY,
    w = w,
    text = t(i18n, "no_theme_settings", "No settings available for this dashboard theme"),
    color = COLOR_THEME_PRIMARY1,
    font = SMLSIZE
  }
end

function M.onClose()
  Common.resetPageState(ui)
  ui.themes = nil
  ui.configurableThemes = nil
  ui.activeThemeConfigPath = nil
  ui.activePageId = nil
  ui.activePage = nil
  ui.activeTheme = nil
  ui.activeModule = nil
  Common = nil
  DashboardLib = nil
  t = nil
end

return M
