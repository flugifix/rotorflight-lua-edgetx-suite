local SYSTEM_THEMES_PATH = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/"
local USER_THEMES_PATH = "/SCRIPTS/TOOLS/rfsuite.user/dashboard/"

local function hexEncode(input)
  if type(input) ~= "string" then return "" end
  local result = ""
  for i = 1, string.len(input) do
    local byte = string.byte(input, i)
    result = result .. string.format("%02x", byte)
  end
  return result
end

-- Static manifest definition - themes are loaded dynamically at runtime
local manifest = {
  sections = {
    {
      id = "configuration",
      title = "@i18n(app.header_configuration)@",
      pages = {
        { id = "flight_tuning", title = "@i18n(app.modules.flight_tuning.name)@", menuId = "flight_tuning_menu", icon = "@pages/flight_tuning/icon.png", row = 1, col = 1, enabled = true },
        { id = "setup", title = "@i18n(app.modules.setup.name)@", menuId = "setup_menu", icon = "@pages/setup/icon.png", row = 1, col = 2, enabled = false }
      }
    },
    {
      id = "system",
      title = "@i18n(app.header_system)@",
      pages = {
        { id = "tools", title = "@i18n(app.modules.tools.name)@", icon = "@pages/tools/icon.png", row = 1, col = 1, enabled = false },
        { id = "logs", title = "@i18n(app.modules.logs.name)@", icon = "@pages/logs/icon.png", row = 1, col = 2, enabled = false },
        { id = "settings", title = "@i18n(app.modules.settings.name)@", menuId = "settings_admin", icon = "@pages/settings/icon.png", row = 1, col = 3, enabled = true },
        { id = "developer", title = "@i18n(app.modules.developer.name)@", menuId = "developer_menu", icon = "@pages/developer/icon.png", row = 1, col = 4, enabledWhen = "developerTools", hideWhenDisabled = true }
      }
    }
  },
  menus = {
    flight_tuning_menu = {
      title = "@i18n(app.modules.flight_tuning.name)@",
      pages = {
        { id = "pids", title = "@i18n(app.modules.pids.name)@", icon = "@pages/flight_tuning/pids/icon.png", row = 1, col = 1, enabled = true },
        { id = "rates", title = "@i18n(app.modules.rates.name)@", icon = "@pages/flight_tuning/rates/icon.png", row = 1, col = 2, enabled = true },
        { id = "governor", title = "@i18n(app.modules.governor.name)@", icon = "@pages/flight_tuning/governor/icon.png", row = 1, col = 3, enabled = true },
        { id = "advanced", title = "@i18n(app.modules.advanced.name)@", icon = "@pages/flight_tuning/advanced/icon.png", row = 1, col = 4, enabled = true }
      }
    },
    setup_menu = {
      title = "@i18n(app.modules.setup.name)@",
      pages = {
        { id = "configuration", title = "@i18n(app.modules.configuration.name)@", icon = "@pages/setup/configuration/icon.png", row = 1, col = 1, enabled = false },
        { id = "radio_config", title = "@i18n(app.modules.radio_config.name)@", icon = "@pages/setup/radio_config/icon.png", row = 1, col = 2, enabled = false },
        { id = "telemetry", title = "@i18n(app.modules.telemetry.name)@", icon = "@pages/setup/telemetry/icon.png", row = 1, col = 3, enabled = false }
      }
    },
    settings_admin = {
      title = "@i18n(app.modules.settings.name)@",
      pages = {
        { id = "general", title = "@i18n(app.modules.general.name)@", menuId = "settings_general_page", row = 1, col = 1, enabled = true },
        { id = "dashboard", title = "@i18n(app.modules.dashboard.name)@", menuId = "settings_dashboard_menu", icon = "@pages/settings/dashboard/icon.png", row = 1, col = 2, enabled = true },
        { id = "localization", title = "@i18n(app.modules.localization.name)@", menuId = "settings_localization_page", row = 1, col = 3, enabled = true },
        { id = "audio", title = "@i18n(app.modules.audio.name)@", menuId = "settings_audio_page", row = 1, col = 4, enabled = true },
        { id = "shortcuts", title = "@i18n(app.modules.shortcuts.name)@", menuId = "settings_shortcuts_page", row = 1, col = 5, enabled = false, hideWhenDisabled = true },
        { id = "activelook", title = "@i18n(app.modules.activelook.name)@", menuId = "settings_activelook_page", row = 1, col = 6, enabled = false, hideWhenDisabled = true }      }
    },
    settings_dashboard_menu = {
      title = "@i18n(app.modules.dashboard.name)@",
      pages = {
        { id = "dashboard_theme", title = "@i18n(app.modules.dashboard_theme.name)@", menuId = "settings_dashboard_theme_page", row = 1, col = 1, enabled = true },
        { id = "dashboard_settings", title = "@i18n(app.modules.dashboard_settings.name)@", menuId = "settings_dashboard_settings_menu", icon = "@pages/settings/dashboard/settings/icon.png", row = 1, col = 2, enabled = true }
      }
    },
    settings_dashboard_settings_menu = {
      title = "@i18n(app.modules.dashboard_settings.name)@",
      pages = {},  -- Populated dynamically at runtime by dashboard_builder
      _dynamicThemes = true  -- Flag to indicate this menu should be populated dynamically
    },
    settings_general_page = {
      title = "@i18n(app.modules.general.name)@",
      pages = {}
    },
    settings_dashboard_theme_page = {
      title = "@i18n(app.modules.dashboard_theme.name)@",
      pages = {}
    },
    settings_dashboard_settings_page = {
      title = "@i18n(app.modules.dashboard_settings.name)@",
      pages = {}
    },
    settings_shortcuts_page = {
      title = "@i18n(app.modules.shortcuts.name)@",
      pages = {}
    },
    settings_activelook_page = {
      title = "@i18n(app.modules.activelook.name)@",
      pages = {}
    },
    settings_localization_page = {
      title = "@i18n(app.modules.localization.name)@",
      pages = {}
    },
    settings_audio_page = {
      title = "@i18n(app.modules.audio.name)@",
      pages = {
        { id = "audio_events", title = "@i18n(app.modules.audio_events.name)@", menuId = "settings_audio_events_page", row = 1, col = 1, enabled = true },
        { id = "audio_switches", title = "@i18n(app.modules.audio_switches.name)@", menuId = "settings_audio_switches_page", row = 1, col = 2, enabled = true },
        { id = "audio_timer", title = "@i18n(app.modules.audio_timer.name)@", menuId = "settings_audio_timer_page", row = 1, col = 3, enabled = true }      }
    },
    developer_menu = {
      title = "@i18n(app.modules.developer.name)@",
      pages = {
        { id = "msp_speed", title = "@i18n(app.modules.msp_speed.name)@", icon = "@pages/developer/msp_speed/icon.png", row = 1, col = 1, enabled = true },
        { id = "api_tester", title = "@i18n(app.modules.api_tester.name)@", icon = "@pages/developer/api_tester/icon.png", row = 1, col = 2, enabled = true },
        { id = "msp_experiments", title = "@i18n(app.modules.msp_experiments.name)@", icon = "@pages/developer/msp_experiments/icon.png", row = 1, col = 3, enabled = true },
        { id = "developer_settings", title = "@i18n(app.modules.developer_settings.name)@", icon = "@pages/developer/developer_settings/icon.png", row = 1, col = 4, enabled = true }
      }
    },
    settings_audio_events_page = {
      title = "@i18n(app.modules.audio_events.name)@",
      pages = {}
    },
    settings_audio_switches_page = {
      title = "@i18n(app.modules.audio_switches.name)@",
      pages = {}
    },
    settings_audio_timer_page = {
      title = "@i18n(app.modules.audio_timer.name)@",
      pages = {}
    }
  }
}

return manifest
