local function definePage(path)
  return {
    pagePath = path .. "/page.lua",
    iconPath = path .. "/icon.png"
  }
end

local entries = {
  settings_general_page = definePage("settings/general"),
  developer_msp_speed_page = definePage("developer/msp_speed"),
  developer_api_tester_page = definePage("developer/api_tester"),
  developer_settings_page = definePage("developer/developer_settings"),
  developer_msp_experiments_page = definePage("developer/msp_experiments"),
  --settings_shortcuts_page = definePage("settings/shortcuts"),
  settings_dashboard_theme_page = definePage("settings/dashboard/theme"),
  settings_dashboard_settings_page = definePage("settings/dashboard/settings"),
  --settings_activelook_page = definePage("settings/activelook"),
  settings_localization_page = definePage("settings/localization"),
  settings_audio_page = definePage("settings/audio"),
  settings_audio_events_page = definePage("settings/audio/events"),
  settings_audio_switches_page = definePage("settings/audio/switches"),
  settings_audio_timer_page = definePage("settings/audio/timer"),
  diagnostics_fblsensors_page = definePage("tools/diagnostics/fblsensors"),
  diagnostics_fblstatus_page = definePage("tools/diagnostics/fblstatus"),
  diagnostics_rfstatus_page = definePage("tools/diagnostics/rfstatus"),
  diagnostics_validate_sensors_page = definePage("tools/diagnostics/validate_sensors"),
  diagnostics_info_page = definePage("tools/diagnostics/info")
}

local registry = {}
local loadedByMenuId = {}
local loadedByPagePath = {}
local iconByMenuId = {}
local pagePathByMenuId = {}
local cacheOrder = {}
local MAX_CACHED_PAGE_MODULES = 8
local closePageModule

local function isDynamicDashboardSettingsPage(menuId)
  if type(menuId) ~= "string" then return false end
  return string.match(menuId, "^settings_dashboard_settings_[0-9a-f]+_page$") ~= nil
end

local function isCacheableMenuId(menuId)
  -- Dynamic dashboard settings IDs can grow over time; do not retain them.
  return not isDynamicDashboardSettingsPage(menuId)
end

local function touchCache(menuId)
  for i = #cacheOrder, 1, -1 do
    if cacheOrder[i] == menuId then
      table.remove(cacheOrder, i)
      break
    end
  end
  cacheOrder[#cacheOrder + 1] = menuId
end

local function removeFromCacheOrder(menuId)
  for i = #cacheOrder, 1, -1 do
    if cacheOrder[i] == menuId then
      table.remove(cacheOrder, i)
    end
  end
end

local function evictIfNeeded(keepMenuId, ctx)
  while #cacheOrder > MAX_CACHED_PAGE_MODULES do
    local victim = table.remove(cacheOrder, 1)
    if victim and victim ~= keepMenuId then
      closePageModule(victim, ctx)
    end
  end
end

local function loadPageModule(menuId)
  local entry = entries[menuId]
  if not entry and isDynamicDashboardSettingsPage(menuId) then
    entry = entries.settings_dashboard_settings_page
    iconByMenuId[menuId] = entry.iconPath
    pagePathByMenuId[menuId] = entry.pagePath
  end
  if not entry then
    return nil
  end

  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/" .. entry.pagePath

  -- Special cache for dashboard settings page: always cache by file path
  if entry.pagePath == "settings/dashboard/settings/page.lua" then
    if loadedByPagePath[fullPath] then
      return loadedByPagePath[fullPath]
    end
    local chunk = assert(loadScript(fullPath, "t"))
    local module = chunk()
    loadedByPagePath[fullPath] = module
    return module
  end

  local chunk = assert(loadScript(fullPath, "t"))
  local module = chunk()
  if isCacheableMenuId(menuId) then
    loadedByMenuId[menuId] = module
    touchCache(menuId)
  end
  return module
end

closePageModule = function(menuId, ctx)
  -- Special handling: dashboard settings page module is cached by file path
  local entry = entries[menuId]
  if not entry and isDynamicDashboardSettingsPage(menuId) then
    entry = entries.settings_dashboard_settings_page
  end
  if entry and entry.pagePath == "settings/dashboard/settings/page.lua" then
    local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/" .. entry.pagePath
    local module = loadedByPagePath[fullPath]
    if type(module) == "table" then
      local hook = module.onClose or module.close or module.closePage or module.destroy
      if type(hook) == "function" then
        pcall(hook, ctx or {})
      end
      loadedByPagePath[fullPath] = nil
      return true
    end
    return false
  end
  -- Default: cache by menuId
  local module = loadedByMenuId[menuId]
  if type(module) ~= "table" then
    loadedByMenuId[menuId] = nil
    removeFromCacheOrder(menuId)
    return false
  end
  local hook = module.onClose or module.close or module.closePage or module.destroy
  if type(hook) == "function" then
    pcall(hook, ctx or {})
  end
  loadedByMenuId[menuId] = nil
  removeFromCacheOrder(menuId)
  return true
end

for menuId, entry in pairs(entries) do
  iconByMenuId[menuId] = entry.iconPath
  pagePathByMenuId[menuId] = entry.pagePath
end

function registry.get(menuId)
  if type(menuId) ~= "string" or menuId == "" then
    return nil
  end

  local module = loadedByMenuId[menuId]
  if module ~= nil then
    touchCache(menuId)
    return module
  end

  local loaded = loadPageModule(menuId)
  if loaded and isCacheableMenuId(menuId) then
    evictIfNeeded(menuId)
  end
  return loaded
end

function registry.release(menuId, ctx)
  local released = false
  if not isCacheableMenuId(menuId) then
    released = closePageModule(menuId, ctx)
  else
    local module = loadedByMenuId[menuId]
    if type(module) == "table" then
      local hook = module.onClose or module.close or module.closePage or module.destroy
      if type(hook) == "function" then
        pcall(hook, ctx or {})
      end
      released = true
    end
  end
  -- Do NOT force collectgarbage() here.
  -- Forcing GC before lvgl.build() replaces the scene can collect Lua closures
  -- that LVGL still holds raw references to, causing a crash in lvgl.build().
  return released
end

function registry.releaseAll(ctx)
  local released = false
  for menuId in pairs(loadedByMenuId) do
    if closePageModule(menuId, ctx) then
      released = true
    end
  end

  if released and collectgarbage then
    collectgarbage("collect")
  end

  return released
end

registry.byMenuId = setmetatable({}, {
  __index = function(_, menuId)
    return registry.get(menuId)
  end
})

registry.iconByMenuId = iconByMenuId
registry.pagePathByMenuId = pagePathByMenuId

return registry