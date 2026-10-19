return function(ctx)
  local i18n = ctx and ctx.i18n
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_standby.help_message")
    or "Standby screen: show one fullscreen surface while waiting for the flight controller.\nPosition 1: choose and order tiles; Move up and Move down reorder them, and Remove deletes one.\nSize: choose Small, Wide, or Full row; ELRS needs Wide or Full row. Turning on requires a fitting layout; turning off keeps the last valid layout."
  return { message = message }
end
