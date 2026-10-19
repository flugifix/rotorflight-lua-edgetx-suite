return function(ctx)
  local i18n = ctx and ctx.i18n
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_standby.help_message")
    or "Standby screen: show one fullscreen surface while waiting for the flight controller.\nPosition 1-8: add, remove, and move items up or down.\nSize: choose Small, Wide, or Full row; ELRS needs Wide or Full row. Save refuses a layout that does not fit and keeps the last valid screen."
  return { message = message }
end
