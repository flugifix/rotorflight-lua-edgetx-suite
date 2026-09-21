-- Dynamic dashboard settings menu builder
-- Reuses the dashboard settings library so menus and pages discover
-- the exact same theme set at runtime.

local function loadModule(path)
  local chunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. path, "t"))
  return chunk()
end

local DashboardLib = loadModule("app/pages/settings/dashboard/lib.lua")
local Log = loadModule("lib/log.lua")
local FALLBACK_ICON = "@pages/settings/dashboard/settings/icon.png"
local DEBUG_PREFIX = "[dashboard.builder] "

local function debugLog(message)
  if Log and type(Log.emit) == "function" then
    Log.emit("dashboard.builder", DEBUG_PREFIX .. tostring(message), "debug")
  end
end

local function hexEncode(input)
  if type(input) ~= "string" then return "" end
  local result = ""
  for i = 1, string.len(input) do
    local byte = string.byte(input, i)
    result = result .. string.format("%02x", byte)
  end
  return result
end

-- The grid a theme's own tile opens when the theme declares pages: one tile per page, laid out
-- like the theme grid above it. Each tile opens the same settings page under a menu id that
-- carries the page id, which is how the page knows which half of the theme it is showing.
local function buildThemePageMenu(t, token, themeIcon, menus)
  local menuId = "settings_dashboard_settings_" .. token .. "_menu"
  local pages = {}

  for i = 1, #t.pages do
    local page = t.pages[i]
    local pageMenuId = "settings_dashboard_settings_" .. token .. "_" .. page.id .. "_page"
    debugLog("page entry theme=" .. tostring(t.path) .. " page=" .. tostring(page.id) .. " menuId=" .. tostring(pageMenuId))
    pages[#pages + 1] = {
      id = "dashboard_settings_" .. token .. "_" .. page.id,
      title = page.title,
      menuId = pageMenuId,
      icon = page.iconPath or themeIcon,
      row = math.floor((i - 1) / 6) + 1,
      col = ((i - 1) % 6) + 1,
      themePath = t.path
    }
    menus[pageMenuId] = {
      title = page.title,
      pages = {},
      themePath = t.path
    }
  end

  menus[menuId] = {
    title = t.name,
    pages = pages,
    themePath = t.path
  }

  return menuId
end

local function buildDashboardSettingsThemeMenus()
  local themes = DashboardLib.getConfigurableThemes(DashboardLib.listThemes())
  debugLog("buildDashboardSettingsThemeMenus configurable count=" .. tostring(#themes))

  local entries = {}
  local menus = {}

  for i = 1, #themes do
    local t = themes[i]
    local token = hexEncode(t.path)
    local themeIcon = t.iconPath or FALLBACK_ICON
    local menuId
    if type(t.pages) == "table" then
      menuId = buildThemePageMenu(t, token, themeIcon, menus)
    else
      menuId = "settings_dashboard_settings_" .. token .. "_page"
      menus[menuId] = {
        title = t.name,
        pages = {},
        themePath = t.path
      }
    end
    debugLog("menu entry name=" .. tostring(t.name) .. " path=" .. tostring(t.path) .. " menuId=" .. tostring(menuId))
    entries[#entries + 1] = {
      id = "dashboard_settings_" .. token,
      title = t.name,
      menuId = menuId,
      icon = themeIcon,
      row = math.floor((i - 1) / 6) + 1,
      col = ((i - 1) % 6) + 1,
      themePath = t.path
    }
  end

  debugLog("buildDashboardSettingsThemeMenus entries=" .. tostring(#entries))

  return entries, menus
end

return {
  buildDashboardSettingsThemeMenus = buildDashboardSettingsThemeMenus
}
