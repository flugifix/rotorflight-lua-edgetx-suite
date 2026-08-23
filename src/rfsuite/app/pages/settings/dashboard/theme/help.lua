return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_theme.help_message")
    or "Select the dashboard theme for each flight phase (preflight, inflight, postflight)."
  
  return {
    message = message
  }
end
