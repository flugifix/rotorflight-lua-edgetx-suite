return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_overrides.help_message")
    or "Each theme this model draws is listed first, with the flight phases it is drawn in; its button opens the theme's settings for this model only, and a value saved there that equals the standard is not stored for the model. Below are the theme settings the connected model changes, each beside the standard value it replaces. Reset removes the model's own value, so the model uses the standard again and follows later changes of it. Reset all does that for every setting after asking. A reset is saved at once. Per-model settings are switched on under Dashboard > Design."

  return { message = message }
end
