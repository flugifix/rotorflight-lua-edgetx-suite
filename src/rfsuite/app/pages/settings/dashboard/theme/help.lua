return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_theme.help_message")
    or "Theme: the dashboard theme of every model without settings of its own.\nAllow per-model settings: lets a model use its own theme and theme settings, stored for its flight controller.\nOwn settings for this model: turns them on for the connected model; its Theme picks the model's theme, Disabled keeps the one above.\nPer-Phase Themes: adds an inflight and a postflight override; 'Use theme above' keeps the theme above.\nSwitching off keeps the stored values."
  
  return {
    message = message
  }
end
