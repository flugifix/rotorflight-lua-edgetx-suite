return function(ctx)
  local i18n = ctx and ctx.i18n
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_standby.help_message")
    or "Standby screen: show one fullscreen surface while waiting for the flight controller.\nPositions: add, remove, and move up or down up to eight items.\nSize: choose Small, Wide, or Full row; ELRS needs Wide or Full row.\nFit: Save refuses a layout that does not fit and keeps the last valid screen."
  return { message = message }
end
