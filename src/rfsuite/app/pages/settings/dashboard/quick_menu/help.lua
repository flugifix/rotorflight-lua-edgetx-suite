return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_quick_menu.help_message")
    or "Which entries the Quick Settings menu shows, row by row, left to right. An entry still hides where it does not apply; Battery profile is always the last row, not a position.\nPosition 1: the entry in that place, and so on; the dash leaves it empty, an entry chosen twice counts at its first place. With the default order saved, the menu follows the default."

  return {
    message = message
  }
end
