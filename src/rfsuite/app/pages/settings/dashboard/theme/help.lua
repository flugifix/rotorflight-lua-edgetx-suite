return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_theme.help_message")
    or "Theme is the dashboard theme of every model. A theme covers all three flight phases itself. Allow model overrides lets a model use its own theme and its own theme settings; they are stored for the connected flight controller, so one has to be connected to set them. Overrides for this model turns them on for that model, and its Theme picks the model's own; Disabled keeps the theme above. Switching either off keeps the model's values and ignores them until it is on again. A card from an earlier version has not stored the switches yet: models keep what they already use, and Allow model overrides is stored only once it is changed. Per-Phase Themes adds an inflight and a postflight override to each theme; left at 'Use theme above', the phase keeps the theme above it."
  
  return {
    message = message
  }
end
