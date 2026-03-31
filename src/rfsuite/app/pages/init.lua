local function loadPage(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local SettingsGeneralPage = loadPage("settings/general.lua")
--local SettingsShortcutsPage = loadPage("settings/shortcuts.lua")
local SettingsDashboardPage = loadPage("settings/dashboard.lua")
--local SettingsActiveLookPage = loadPage("settings/activelook.lua")
local SettingsLocalizationPage = loadPage("settings/localization.lua")
local SettingsAudioPage = loadPage("settings/audio.lua")

return {
  byMenuId = {
    settings_general_page = SettingsGeneralPage,
    --settings_shortcuts_page = SettingsShortcutsPage,
    settings_dashboard_page = SettingsDashboardPage,
    --settings_activelook_page = SettingsActiveLookPage,
    settings_localization_page = SettingsLocalizationPage,
    settings_audio_page = SettingsAudioPage
  }
}
