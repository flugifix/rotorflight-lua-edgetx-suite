return function(ctx)
  local i18n = ctx and ctx.i18n
  local line1 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_intro")
    or "Radio-wide fullscreen shortcuts, including before FC connection."
  local line2 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_actions")
    or "Theme keeps theme/host defaults; Nothing disables a key. Other actions override the theme."
  local line3 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_safety")
    or "Tool and Flight Log keep safety guards. Short RTN stays Back/Close; long RTN leaves fullscreen."
  local line4 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_page_down")
    or "PAGE >: action for the next-page key."
  local line5 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_page_up")
    or "PAGE <: action for the previous-page key."
  local line6 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_mdl")
    or "MDL: action for the model key."
  local line7 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_sys")
    or "SYS: action for the system key."
  local line8 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_tele")
    or "TELE: action for the telemetry key."
  return { message = table.concat({ line1, line2, line3, line4, line5, line6, line7, line8 }, "\n") }
end
