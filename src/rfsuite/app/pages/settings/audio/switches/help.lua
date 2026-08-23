return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_audio_switches.help_message")
    or "Configure which switch and flight-mode changes trigger audio announcements."

  return { message = message }
end
