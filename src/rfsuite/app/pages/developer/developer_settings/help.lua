return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_developer_settings.help_message")
    or "How much the suite logs, and whether it writes the log to the SD card for a problem report."

  return { message = message }
end
