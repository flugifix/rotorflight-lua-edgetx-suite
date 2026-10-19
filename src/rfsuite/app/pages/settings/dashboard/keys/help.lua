return function(ctx)
  local i18n = ctx and ctx.i18n
  local line1 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_intro")
    or "Radio-wide shortcuts: Theme keeps defaults, Nothing disables a key. Other choices override."
  local line2 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_page_down")
    or "PAGE >: next-page action."
  local line3 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_page_up")
    or "PAGE <: previous-page action."
  local line4 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_mdl")
    or "MDL: model-key action. RTN keeps Back/Close; long RTN exits."
  local line5 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_sys")
    or "SYS: system-key action. Tool access requires a disarmed model."
  local line6 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_tele")
    or "TELE: telemetry-key action. Flight Log requires its preview switch."
  return { message = table.concat({ line1, line2, line3, line4, line5, line6 }, "\n") }
end
