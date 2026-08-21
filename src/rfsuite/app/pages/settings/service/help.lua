return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_service.help_message")
    or "Configure what the background service does while it has a link to the flight controller."

  return { message = message }
end
