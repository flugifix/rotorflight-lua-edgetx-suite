return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_audio_timer.help_message")
    or "Configure timer-related audio announcements and bell behavior."

  return { message = message }
end
