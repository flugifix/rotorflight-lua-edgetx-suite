return function(ctx)
  local i18n = ctx and ctx.i18n
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_standby.help_message")
    or "Standby screen: show one fullscreen surface while waiting for the flight controller.\nMove up and Move down reorder items; Remove deletes the chosen item from positions 1-8.\nSize: choose Small, Wide, or Full row; ELRS needs Wide or Full row. Enabling refuses a layout that does not fit. Switching the screen off still saves and keeps the last valid layout."
  return { message = message }
end
