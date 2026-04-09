local function definePage(path)
  return {
    pagePath = path .. "/page.lua",
    iconPath = path .. "/icon.png"
  }
end

local entries = {
  settings_general_page = definePage("settings/general"),
  developer_settings_page = definePage("developer/developer_settings"),
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
local iconByMenuId = {}
local pagePathByMenuId = {}

local function isDynamicDashboardSettingsPage(menuId)
  if type(menuId) ~= "string" then return false end
  return string.match(menuId, "^settings_dashboard_settings_[0-9a-f]+_page$") ~= nil
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
  local chunk = assert(loadScript(fullPath, "t"))
  local module = chunk()
  loadedByMenuId[menuId] = module
  return module
end

local function closePageModule(menuId, ctx)
  local module = loadedByMenuId[menuId]
  if type(module) ~= "table" then
    loadedByMenuId[menuId] = nil
    return false
  end

  local hook = module.onClose or module.close or module.destroy
  if type(hook) == "function" then
    pcall(hook, ctx or {})
  end

  loadedByMenuId[menuId] = nil
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
    return module
  end

  return loadPageModule(menuId)
end

function registry.release(menuId, ctx)
  local released = closePageModule(menuId, ctx)
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