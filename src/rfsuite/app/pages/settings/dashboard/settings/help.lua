return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_settings.help_message")
    or "Each tile opens a theme's own settings. They are the standard values, used by every model without overrides. Model Overrides is shown while a flight controller is connected and overrides are on for its model: it lists what that model changes and opens each theme's settings for that model alone, where only a value that differs from the standard is stored. The first line of a theme's page says which of the two it edits."

  return { message = message }
end
