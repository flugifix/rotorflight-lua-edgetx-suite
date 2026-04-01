local function loadPageEntry(path)
  local pagePath = path .. "/page.lua"
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/" .. pagePath
  local chunk = assert(loadScript(fullPath, "t"))
  return {
    module = chunk(),
    iconPath = path .. "/icon.png"
  }
end

local entries = {
  settings_general_page = loadPageEntry("settings/general"),
  --settings_shortcuts_page = loadPageEntry("settings/shortcuts"),
  settings_dashboard_page = loadPageEntry("settings/dashboard"),
  --settings_activelook_page = loadPageEntry("settings/activelook"),
  settings_localization_page = loadPageEntry("settings/localization"),
  settings_audio_page = loadPageEntry("settings/audio"),
  settings_audio_events_page = loadPageEntry("settings/audio/events"),
  settings_audio_switches_page = loadPageEntry("settings/audio/switches"),
  settings_audio_timer_page = loadPageEntry("settings/audio/timer")
}

local byMenuId = {}
local iconByMenuId = {}

for menuId, entry in pairs(entries) do
  byMenuId[menuId] = entry.module
  iconByMenuId[menuId] = entry.iconPath
end

return {
  byMenuId = byMenuId,
  iconByMenuId = iconByMenuId
}