return {
  sections = {
    {
      id = "configuration",
      title = "@i18n(app.header_configuration)@",
      pages = {
        { id = "flight_tuning", title = "@i18n(app.modules.flight_tuning.name)@", menuId = "flight_tuning_menu", icon = "flight_tuning.png", row = 1, col = 1, enabled = true },
        { id = "setup", title = "@i18n(app.modules.setup.name)@", menuId = "setup_menu", icon = "hardware.png", row = 1, col = 2, enabled = false }
      }
    },
    {
      id = "system",
      title = "@i18n(app.header_system)@",
      pages = {
        { id = "tools", title = "@i18n(app.modules.tools.name)@", icon = "tools.png", row = 1, col = 1, enabled = false },
        { id = "logs", title = "@i18n(app.modules.logs.name)@", icon = "logs.png", row = 1, col = 2, enabled = false },
        { id = "settings", title = "@i18n(app.modules.settings.name)@", menuId = "settings_admin", icon = "settings.png", row = 1, col = 3, enabled = false },
        { id = "developer", title = "@i18n(app.modules.developer.name)@", icon = "developer.png", row = 1, col = 4, enabled = false }
      }
    }
  },
  menus = {
    flight_tuning_menu = {
      title = "@i18n(app.modules.flight_tuning.name)@",
      pages = {
        { id = "pids", title = "@i18n(app.modules.pids.name)@", icon = "setup.png", row = 1, col = 1, enabled = true },
        { id = "rates", title = "@i18n(app.modules.rates.name)@", icon = "input.png", row = 1, col = 2, enabled = true },
        { id = "governor", title = "@i18n(app.modules.governor.name)@", icon = "flight_tuning.png", row = 1, col = 3, enabled = true },
        { id = "advanced", title = "@i18n(app.modules.advanced.name)@", icon = "tools.png", row = 1, col = 4, enabled = true }
      }
    },
    setup_menu = {
      title = "@i18n(app.modules.setup.name)@",
      pages = {
        { id = "configuration", title = "@i18n(app.modules.configuration.name)@", icon = "setup.png", row = 1, col = 1, enabled = false },
        { id = "radio_config", title = "@i18n(app.modules.radio_config.name)@", icon = "input.png", row = 1, col = 2, enabled = false },
        { id = "telemetry", title = "@i18n(app.modules.telemetry.name)@", icon = "display.png", row = 1, col = 3, enabled = false }
      }
    },
    settings_admin = {
      title = "@i18n(app.modules.settings.name)@",
      pages = {
        { id = "general", title = "@i18n(app.modules.general.name)@", icon = "setup.png", row = 1, col = 1, enabled = false },
        { id = "shortcuts", title = "@i18n(app.modules.shortcuts.name)@", icon = "input.png", row = 1, col = 2, enabled = false },
        { id = "dashboard", title = "@i18n(app.modules.dashboard.name)@", menuId = "settings_dashboard", icon = "display.png", row = 1, col = 3, enabled = false }
      }
    },
    settings_dashboard = {
      title = "@i18n(app.modules.dashboard.name)@",
      pages = {
        { id = "theme", title = "@i18n(app.modules.dashboard_theme.name)@", icon = "display.png", row = 1, col = 1, enabled = false },
        { id = "preferences", title = "@i18n(app.modules.dashboard_settings.name)@", icon = "setup.png", row = 1, col = 2, enabled = false }
      }
    },
    audio_menu = {
      title = "@i18n(app.modules.audio.name)@",
      pages = {
        { id = "audio_events", title = "@i18n(app.modules.audio_events.name)@", icon = "audio.png", row = 1, col = 1, enabled = false },
        { id = "audio_switches", title = "@i18n(app.modules.audio_switches.name)@", icon = "input.png", row = 1, col = 2, enabled = false },
        { id = "audio_timer", title = "@i18n(app.modules.audio_timer.name)@", icon = "logs.png", row = 1, col = 3, enabled = false }
      }
    }
  }
}
