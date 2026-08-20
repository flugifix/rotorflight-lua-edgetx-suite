return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_general.help_message")
    or "Configure safety prompts, integration options, and developer visibility in general settings."

  return { message = message }
end
