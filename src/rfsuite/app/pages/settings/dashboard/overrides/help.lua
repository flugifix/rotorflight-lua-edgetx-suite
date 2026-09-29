return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_overrides.help_message")
    or "The theme settings the connected model changes, each beside the standard value it replaces. Reset removes the model's own value, so the model uses the standard again and follows later changes of it. Reset all does that for every setting after asking. A reset is saved at once. The buttons below open a theme's settings for this model only: a value saved there that equals the standard is not stored as an override. Model overrides are switched on under Dashboard > Design."

  return { message = message }
end
