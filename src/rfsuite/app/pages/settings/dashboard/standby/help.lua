return function(ctx)
  local i18n = ctx and ctx.i18n
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_standby.help_message") or "Shows radio information while the dashboard waits for a flight controller. Add, remove and order items with the position rows. Every saved layout must fit on one screen; an invalid edit is not saved. TX GPS reports the transmitter's internal GPS, and no fix is a waiting state."
  return { message = message }
end
