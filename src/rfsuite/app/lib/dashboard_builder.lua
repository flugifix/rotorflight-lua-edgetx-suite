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
local OVERRIDES_ICON = "@pages/settings/dashboard/overrides/icon.png"
local DEBUG_PREFIX = "[dashboard.builder] "

-- The build reports in ONE debug line, written when it ends, for the reason lib.lua's theme scan
-- does: opened from the dashboard, the build runs inside the widget's per-call instruction limit,
-- and a line per theme and per theme page -- built whether or not the level lets it out -- is a
-- cost that grows with every theme that ships. `buildLog` is a table only while that line is
-- wanted, so nothing is collected below the debug level.
local buildLog = nil

local function logTheme(t)
  if buildLog then
    local pages = type(t.pages) == "table" and #t.pages or 0
    buildLog[#buildLog + 1] = pages > 0 and (tostring(t.path) .. "(" .. pages .. " pages)") or tostring(t.path)
  end
end

-- The theme path as hex, which is how it travels inside a menu id. One call into C for the whole
-- string rather than a concatenation per byte; theme paths are folder names, far shorter than
-- anything string.byte could not return at once.
local function hexEncode(input)
  if type(input) ~= "string" or input == "" then return "" end
  return string.format(string.rep("%02x", #input), string.byte(input, 1, -1))
end

-- Every theme is reachable in two scopes, and the menu id says which: the grid of the Settings
-- tile edits the radio's standard values, the model overrides page edits the connected model's.
-- The settings page reads the scope off the id's prefix, so the two never share a cached module.
local STANDARD_SCOPE = { menuPrefix = "settings_dashboard_settings_", idPrefix = "dashboard_settings_" }
local MODEL_SCOPE = { menuPrefix = "settings_dashboard_model_", idPrefix = "dashboard_model_" }
local OVERRIDES_MENU_ID = "settings_dashboard_overrides_page"
local OVERRIDES_TITLE = "@i18n(app.modules.dashboard_overrides.name)@"

-- The grid a theme's own tile opens when the theme declares pages: one tile per page, laid out
-- like the theme grid above it. Each tile opens the same settings page under a menu id that
-- carries the page id, which is how the page knows which half of the theme it is showing.
local function buildThemePageMenu(t, token, themeIcon, menus, scope)
  local menuId = scope.menuPrefix .. token .. "_menu"
  local pages = {}

  for i = 1, #t.pages do
    local page = t.pages[i]
    local pageMenuId = scope.menuPrefix .. token .. "_" .. page.id .. "_page"
    pages[#pages + 1] = {
      id = scope.idPrefix .. token .. "_" .. page.id,
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

-- One theme's entry in a scope's list, with the menus it opens registered beside it.
local function buildThemeEntry(t, token, index, menus, scope)
  local themeIcon = t.iconPath or FALLBACK_ICON
  local menuId
  if type(t.pages) == "table" then
    menuId = buildThemePageMenu(t, token, themeIcon, menus, scope)
  else
    menuId = scope.menuPrefix .. token .. "_page"
    menus[menuId] = {
      title = t.name,
      pages = {},
      themePath = t.path
    }
  end
  return {
    id = scope.idPrefix .. token,
    title = t.name,
    menuId = menuId,
    icon = themeIcon,
    row = math.floor((index - 1) / 6) + 1,
    col = ((index - 1) % 6) + 1,
    themePath = t.path
  }
end

-- The model overrides tile exists only while it has something to edit: a flight controller is
-- connected, so the model's store can be addressed, and overrides are on for that model and
-- allowed on this radio. Asked whenever the grid is drawn or entered, so turning overrides on
-- under Design shows the tile the next time the grid is opened.
local function modelOverridesVisible()
  local root = type(_G) == "table" and _G.rfsuite or nil
  local session = root and root.session
  if type(session) ~= "table" or session.mcu_id == nil then return false end
  local modelPrefs = session.modelPreferences
  if type(modelPrefs) ~= "table" then return false end
  local prefs = root.preferences
  local dashboard = type(prefs) == "table" and prefs.dashboard or nil
  return DashboardLib.modelOverridesActive(dashboard, modelPrefs.dashboard) == true
end

local function buildDashboardSettingsThemeMenus()
  local themes = DashboardLib.getConfigurableThemes(DashboardLib.listThemes())
  buildLog = (Log and Log.wanted("debug") == true) and {} or nil

  local entries = {}
  local modelEntries = {}
  local menus = {}

  -- The overview is a page, and its theme entries are what its buttons open: the menu registry
  -- opens an entry of the current menu id's list, and that id is the page's own. Its tile comes
  -- first, ahead of the themes: it is the one tile that is about the connected model, and the
  -- grid lays out only the tiles it shows, so while it is hidden the themes start the grid.
  if #themes > 0 then
    menus[OVERRIDES_MENU_ID] = {
      title = OVERRIDES_TITLE,
      pages = modelEntries
    }
    entries[1] = {
      id = "dashboard_overrides",
      title = OVERRIDES_TITLE,
      menuId = OVERRIDES_MENU_ID,
      icon = OVERRIDES_ICON,
      row = 1,
      col = 1,
      visibleWhen = modelOverridesVisible
    }
  end

  for i = 1, #themes do
    local t = themes[i]
    local token = hexEncode(t.path)
    entries[#entries + 1] = buildThemeEntry(t, token, #entries + 1, menus, STANDARD_SCOPE)
    modelEntries[#modelEntries + 1] = buildThemeEntry(t, token, i, menus, MODEL_SCOPE)
    logTheme(t)
  end

  if buildLog then
    Log.emit("dashboard.builder", string.format("%sthemes=%d entries=%d: %s", DEBUG_PREFIX, #themes,
      #entries, table.concat(buildLog, ", ")), "debug")
    buildLog = nil
  end

  return entries, menus
end

return {
  buildDashboardSettingsThemeMenus = buildDashboardSettingsThemeMenus
}
