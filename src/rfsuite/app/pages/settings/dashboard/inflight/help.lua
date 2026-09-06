return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_inflight.help_message")
    or "Choose the interlock switch, the two channels and variables its mixer lines use, and which trim drives each row."

  return {
    message = message
  }
end
