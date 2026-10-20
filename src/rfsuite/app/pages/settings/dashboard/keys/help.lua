return function(ctx)
  local i18n = ctx and ctx.i18n
  local line1 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_intro")
    or "Radio-wide shortcuts for every theme. Theme: what the theme binds, else nothing; Nothing disables a key."
  local line2 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_page_down")
    or "PAGE >: Theme by default; unbound, it opens the Quick menu."
  local line3 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_page_up")
    or "PAGE <: Theme by default; unbound, it opens the Quick menu."
  local line4 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_mdl")
    or "MDL: Theme by default. RTN keeps Back/Close; long RTN exits."
  local line5 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_sys")
    or "SYS: Main menu by default; it requires a disarmed model."
  local line6 = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_tele")
    or "TELE: Quick menu by default. Flight log requires its preview switch."
  return { message = table.concat({ line1, line2, line3, line4, line5, line6 }, "\n") }
end
