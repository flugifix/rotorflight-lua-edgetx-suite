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
        { id = "flight_tuning", title = "@i18n(app.modules.flight_tuning.name)@", menuId = "flight_tuning_menu", icon = "@pages/flight_tuning/icon.png", enabledWhen = "fblConnected" },
        { id = "setup", title = "@i18n(app.modules.setup.name)@", menuId = "setup_menu", icon = "@pages/setup/icon.png", enabledWhen = "fblConnected" }
      }
    },
    {
      id = "system",
      title = "@i18n(app.header_system)@",
      pages = {
        { id = "tools", title = "@i18n(app.modules.tools.name)@", menuId = "tools_menu", icon = "@pages/tools/icon.png" },
        { id = "logs", title = "@i18n(app.modules.logs.name)@", icon = "@pages/logs/icon.png", enabled = false },
        { id = "settings", title = "@i18n(app.modules.settings.name)@", menuId = "settings_admin", icon = "@pages/settings/icon.png" },
        { id = "developer", title = "@i18n(app.modules.developer.name)@", menuId = "developer_menu", icon = "@pages/developer/icon.png", enabledWhen = "developerTools", hideWhenDisabled = true }
      }
    }
  },
  menus = {
    tools_menu = {
      title = "@i18n(app.modules.tools.name)@",
      pages = {
        { id = "copy_profiles", title = "@i18n(app.modules.copyprofiles.name)@", menuId = "tools_copy_profiles_page", icon = "@pages/tools/copy.png", enabledWhen = "fblConnected" },
        { id = "select_profile", title = "@i18n(app.modules.profile_select.name)@", menuId = "tools_select_profile_page", icon = "@pages/tools/select_profile.png", enabledWhen = "fblConnected" },
        { id = "diagnostics", title = "@i18n(app.modules.diagnostics.name)@", menuId = "diagnostics_menu", icon = "@pages/tools/diagnostics.png" }
      }
    },
    diagnostics_menu = {
      title = "@i18n(app.modules.diagnostics.name)@",
      pages = {
        -- Disabled, did not know if we need this realy and the page is not fully implemented yet. Can be re-enabled later if needed.
        -- { id = "fblsensors", title = "@i18n(app.modules.fblsensors.name)@", menuId = "diagnostics_fblsensors_page", enabledWhen = "fblConnected" },
        { id = "fblstatus", title = "@i18n(app.modules.fblstatus.name)@", menuId = "diagnostics_fblstatus_page", enabledWhen = "fblConnected" },
        { id = "rfstatus", title = "@i18n(app.modules.rfstatus.name)@", menuId = "diagnostics_rfstatus_page", enabledWhen = "fblConnected" },
        { id = "elrs_link", title = "@i18n(app.modules.elrs_link.name)@", menuId = "diagnostics_elrs_link_page" },
        { id = "validate_sensors", title = "@i18n(app.modules.validate_sensors.name)@", menuId = "diagnostics_validate_sensors_page", enabledWhen = "fblConnected" },
        { id = "smartfuel", title = "@i18n(app.modules.smartfuel.name)@", menuId = "diagnostics_smartfuel_page", enabledWhen = "fblConnected", minApiVersion = { 12, 0, 9 } },
        { id = "session_logs", title = "@i18n(app.modules.session_logs.name)@", menuId = "diagnostics_session_logs_page" },
        { id = "info", title = "@i18n(app.modules.info.name)@", menuId = "diagnostics_info_page" }
      }
    },
    flight_tuning_menu = {
      title = "@i18n(app.modules.flight_tuning.name)@",
      pages = {
        { id = "pids", title = "@i18n(app.modules.pids.name)@", menuId = "flight_tuning_pids_page", icon = "@pages/flight_tuning/pids/icon.png" },
        { id = "rates", title = "@i18n(app.modules.rates.name)@", menuId = "flight_tuning_rates_page", icon = "@pages/flight_tuning/rates/icon.png" },
        { id = "governor", title = "@i18n(app.modules.governor.name)@", menuId = "flight_tuning_governor_page", icon = "@pages/flight_tuning/governor/icon.png", minApiVersion = { 12, 0, 9 } },
        { id = "advanced", title = "@i18n(app.modules.advanced.name)@", menuId = "flight_tuning_advanced_menu", icon = "@pages/flight_tuning/advanced/icon.png", enabled = true }
      }
    },
    flight_tuning_advanced_menu = {
      title = "@i18n(app.modules.advanced.name)@",
      pages = {
        { id = "filters", title = "@i18n(app.modules.filters.name)@", menuId = "flight_tuning_advanced_filters_page", icon = "@pages/flight_tuning/advanced/filters/icon.png", enabled = false },
        { id = "pid_controller", title = "@i18n(app.modules.pid_controller.name)@", menuId = "flight_tuning_advanced_pid_controller_page", icon = "@pages/flight_tuning/advanced/pid_controller/icon.png", enabled = false },
        { id = "pid_bandwidth", title = "@i18n(app.modules.pid_bandwidth.name)@", menuId = "flight_tuning_advanced_pid_bandwidth_page", icon = "@pages/flight_tuning/advanced/pid_bandwidth/icon.png", enabled = false },
        { id = "autolevel", title = "@i18n(app.modules.autolevel.name)@", menuId = "flight_tuning_advanced_autolevel_page", icon = "@pages/flight_tuning/advanced/autolevel/icon.png", enabled = false },
        { id = "main_rotor", title = "@i18n(app.modules.main_rotor.name)@", menuId = "flight_tuning_advanced_main_rotor_page", icon = "@pages/flight_tuning/advanced/main_rotor/icon.png", enabled = false },
        { id = "tail_rotor", title = "@i18n(app.modules.tail_rotor.name)@", menuId = "flight_tuning_advanced_tail_rotor_page", icon = "@pages/flight_tuning/advanced/tail_rotor/icon.png", enabled = false },
        { id = "rescue", title = "@i18n(app.modules.rescue.name)@", menuId = "flight_tuning_advanced_rescue_page", icon = "@pages/flight_tuning/advanced/rescue/icon.png" },
        { id = "rates_advanced", title = "@i18n(app.modules.rates_advanced.name)@", menuId = "flight_tuning_advanced_rates_advanced_menu", icon = "@pages/flight_tuning/advanced/rates_advanced/icon.png" }
      }
    },
    flight_tuning_advanced_rates_advanced_menu = {
      title = "@i18n(app.modules.rates_advanced.name)@",
      pages = {
        { id = "advanced", title = "@i18n(app.modules.rates_advanced.advanced)@", menuId = "flight_tuning_advanced_rates_advanced_advanced_page", icon = "@pages/flight_tuning/advanced/rates_advanced/advanced/icon.png" },
        { id = "cyclic_behaviour", title = "@i18n(app.modules.rates_advanced.cyclic_behaviour)@", menuId = "flight_tuning_advanced_rates_advanced_cyclic_behaviour_page", icon = "@pages/flight_tuning/advanced/rates_advanced/cyclic_behaviour/icon.png" },
        { id = "table", title = "@i18n(app.modules.rates_advanced.table)@", menuId = "flight_tuning_advanced_rates_advanced_table_page", icon = "@pages/flight_tuning/advanced/rates_advanced/table/icon.png" }
      }
    },
    flight_tuning_advanced_rates_advanced_advanced_page = {
      title = "@i18n(app.modules.rates_advanced.advanced)@",
      pages = {}
    },
    flight_tuning_advanced_rates_advanced_cyclic_behaviour_page = {
      title = "@i18n(app.modules.rates_advanced.cyclic_behaviour)@",
      pages = {}
    },
    flight_tuning_advanced_rates_advanced_table_page = {
      title = "@i18n(app.modules.rates_advanced.table)@",
      pages = {}
    },
    flight_tuning_advanced_filters_page = {
      title = "@i18n(app.modules.filters.name)@",
      pages = {}
    },
    flight_tuning_advanced_pid_controller_page = {
      title = "@i18n(app.modules.pid_controller.name)@",
      pages = {}
    },
    flight_tuning_advanced_pid_bandwidth_page = {
      title = "@i18n(app.modules.pid_bandwidth.name)@",
      pages = {}
    },
    flight_tuning_advanced_autolevel_page = {
      title = "@i18n(app.modules.autolevel.name)@",
      pages = {}
    },
    flight_tuning_advanced_main_rotor_page = {
      title = "@i18n(app.modules.main_rotor.name)@",
      pages = {}
    },
    flight_tuning_advanced_tail_rotor_page = {
      title = "@i18n(app.modules.tail_rotor.name)@",
      pages = {}
    },
    flight_tuning_advanced_rescue_page = {
      title = "@i18n(app.modules.rescue.name)@",
      pages = {}
    },
    flight_tuning_advanced_rates_advanced_page = {
      title = "@i18n(app.modules.rates_advanced.name)@",
      pages = {}
    },
    setup_menu = {
      title = "@i18n(app.modules.setup.name)@",
      pages = {
        { id = "configuration", title = "@i18n(app.modules.configuration.name)@", icon = "@pages/setup/configuration/icon.png", row = 1, col = 1, enabled = false },
        { id = "radio_config", title = "@i18n(app.modules.radio_config.name)@", icon = "@pages/setup/radio_config/icon.png", row = 1, col = 2, enabled = false },
        { id = "telemetry", title = "@i18n(app.modules.telemetry.name)@", menuId = "setup_telemetry_page", icon = "@pages/setup/telemetry/icon.png", row = 1, col = 3 },
        { id = "accelerometer", title = "@i18n(app.modules.accelerometer.name)@", icon = "@pages/setup/accelerometer/icon.png", row = 1, col = 4, enabled = false },
        { id = "alignment", title = "@i18n(app.modules.alignment.name)@", icon = "@pages/setup/alignment/icon.png", row = 1, col = 5, enabled = false },
        { id = "ports", title = "@i18n(app.modules.ports.name)@", icon = "@pages/setup/ports/icon.png", row = 1, col = 6, enabled = false },
        { id = "mixer", title = "@i18n(app.modules.mixer.name)@", icon = "@pages/setup/mixer/icon.png", row = 2, col = 1, enabled = false },
        { id = "servos", title = "@i18n(app.modules.servos.name)@", icon = "@pages/setup/servos/icon.png", row = 2, col = 2, enabled = false },
        { id = "controls", title = "@i18n(app.modules.controls.name)@", icon = "@pages/setup/controls/icon.png", row = 2, col = 3, enabled = false },
        { id = "power", title = "@i18n(app.modules.power.name)@", menuId = "power_menu", icon = "@pages/setup/power/icon.png", row = 2, col = 4 },
        { id = "esc_motors", title = "@i18n(app.modules.esc_motors.name)@", icon = "@pages/setup/esc_motors/icon.png", row = 2, col = 5, enabled = false },
        { id = "governor", title = "@i18n(app.modules.governor.name)@", icon = "@pages/setup/governor/icon.png", row = 2, col = 6, enabled = false }
      }
    },
    power_menu = {
      title = "@i18n(app.modules.power.name)@",
      pages = {
        { id = "battery", title = "@i18n(app.modules.battery.name)@", menuId = "setup_power_battery_page", icon = "@pages/setup/power/battery/icon.png", row = 1, col = 1 },
        { id = "alerts", title = "@i18n(app.modules.alerts.name)@", menuId = "setup_power_alerts_page", icon = "@pages/setup/power/alerts/icon.png", row = 1, col = 2 },
        { id = "sources", title = "@i18n(app.modules.sources.name)@", menuId = "setup_power_sources_page", icon = "@pages/setup/power/sources/icon.png", row = 1, col = 3 },
        { id = "smartfuel", title = "@i18n(app.modules.smartfuel.name)@", menuId = "setup_power_smartfuel_page", icon = "@pages/setup/power/smartfuel/icon.png", row = 1, col = 4, minApiVersion = { 12, 0, 9 } },
        { id = "preferences", title = "@i18n(app.modules.preferences.name)@", menuId = "setup_power_preferences_page", icon = "@pages/setup/power/preferences/icon.png", row = 1, col = 5 }
      }
    },
    setup_power_battery_page = {
      title = "@i18n(app.modules.battery.name)@",
      pages = {}
    },
    setup_power_alerts_page = {
      title = "@i18n(app.modules.alerts.name)@",
      pages = {}
    },
    setup_power_sources_page = {
      title = "@i18n(app.modules.sources.name)@",
      pages = {}
    },
    setup_power_smartfuel_page = {
      title = "@i18n(app.modules.smartfuel.name)@",
      pages = {}
    },
    setup_power_preferences_page = {
      title = "@i18n(app.modules.preferences.name)@",
      pages = {}
    },
    flight_tuning_pids_page = {
      title = "@i18n(app.modules.pids.name)@",
      pages = {}
    },
    flight_tuning_rates_page = {
      title = "@i18n(app.modules.rates.name)@",
      pages = {}
    },
    flight_tuning_governor_page = {
      title = "@i18n(app.modules.governor.name)@",
      pages = {}
    },
    setup_telemetry_page = {
      title = "@i18n(app.modules.telemetry.name)@",
      pages = {}
    },
    settings_admin = {
      title = "@i18n(app.modules.settings.name)@",
      pages = {
        { id = "general", title = "@i18n(app.modules.general.name)@", menuId = "settings_general_page" },
        { id = "dashboard", title = "@i18n(app.modules.dashboard.name)@", menuId = "settings_dashboard_menu", icon = "@pages/settings/dashboard/icon.png" },
        { id = "localization", title = "@i18n(app.modules.localization.name)@", menuId = "settings_localization_page" },
        { id = "audio", title = "@i18n(app.modules.audio.name)@", menuId = "settings_audio_page" },
        { id = "shortcuts", title = "@i18n(app.modules.shortcuts.name)@", menuId = "settings_shortcuts_page", enabled = false, hideWhenDisabled = true }
        --{ id = "activelook", title = "@i18n(app.modules.activelook.name)@", menuId = "settings_activelook_page", enabled = false, hideWhenDisabled = true }      
      }
    },
    settings_dashboard_menu = {
      title = "@i18n(app.modules.dashboard.name)@",
      pages = {
        { id = "dashboard_theme", title = "@i18n(app.modules.dashboard_theme.name)@", menuId = "settings_dashboard_theme_page" },
        { id = "dashboard_settings", title = "@i18n(app.modules.dashboard_settings.name)@", menuId = "settings_dashboard_settings_menu", icon = "@pages/settings/dashboard/settings/icon.png" }
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
        { id = "audio_events", title = "@i18n(app.modules.audio_events.name)@", menuId = "settings_audio_events_page" }
        --{ id = "audio_switches", title = "@i18n(app.modules.audio_switches.name)@", menuId = "settings_audio_switches_page" },
        --{ id = "audio_timer", title = "@i18n(app.modules.audio_timer.name)@", menuId = "settings_audio_timer_page" }      
      }
    },
    developer_menu = {
      title = "@i18n(app.modules.developer.name)@",
      pages = {
        { id = "msp_speed", title = "@i18n(app.modules.msp_speed.name)@", menuId = "developer_msp_speed_page", icon = "@pages/developer/msp_speed/icon.png", enabledWhen = "fblConnected" },
        { id = "api_tester", title = "@i18n(app.modules.api_tester.name)@", menuId = "developer_api_tester_page", icon = "@pages/developer/api_tester/icon.png", enabledWhen = "fblConnected" },
        { id = "msp_experiments", title = "@i18n(app.modules.msp_experiments.name)@", menuId = "developer_msp_experiments_page", icon = "@pages/developer/msp_experiments/icon.png", enabledWhen = "fblConnected" },
        { id = "developer_settings", title = "@i18n(app.modules.developer_settings.name)@", menuId = "developer_settings_page", icon = "@pages/developer/developer_settings/icon.png" },
      }
    },
    developer_msp_speed_page = {
      title = "@i18n(app.modules.msp_speed.name)@",
      pages = {}
    },
    developer_api_tester_page = {
      title = "@i18n(app.modules.api_tester.name)@",
      pages = {}
    },
    developer_msp_experiments_page = {
      title = "@i18n(app.modules.msp_experiments.name)@",
      pages = {}
    },
    developer_settings_page = {
      title = "@i18n(app.modules.developer_settings.name)@",
      pages = {}
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
    },
    diagnostics_fblsensors_page = {
      title = "@i18n(app.modules.fblsensors.name)@",
      pages = {}
    },
    diagnostics_fblstatus_page = {
      title = "@i18n(app.modules.fblstatus.name)@",
      pages = {}
    },
    diagnostics_rfstatus_page = {
      title = "@i18n(app.modules.rfstatus.name)@",
      pages = {}
    },
    diagnostics_elrs_link_page = {
      title = "@i18n(app.modules.elrs_link.name)@",
      pages = {}
    },
    diagnostics_validate_sensors_page = {
      title = "@i18n(app.modules.validate_sensors.name)@",
      pages = {}
    },
    diagnostics_smartfuel_page = {
      title = "@i18n(app.modules.smartfuel.name)@",
      pages = {}
    },
    diagnostics_session_logs_page = {
      title = "@i18n(app.modules.session_logs.name)@",
      pages = {}
    },
    diagnostics_info_page = {
      title = "@i18n(app.modules.info.name)@",
      pages = {}
    },
    tools_select_profile_page = {
      title = "@i18n(app.modules.profile_select.name)@",
      pages = {}
    },
    tools_copy_profiles_page = {
      title = "@i18n(app.modules.copyprofiles.name)@",
      pages = {}
    }
  }
}

return manifest
