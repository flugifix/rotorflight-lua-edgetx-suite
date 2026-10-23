return function(ctx)
  local i18n = ctx and ctx.i18n
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_standby.help_message")
    or "Standby screen: show radio information while the dashboard waits for the flight controller.\nRow 1: filled fields share the row equally; a smaller zone skips rows that do not fit.\nField 1: choose a module; the list includes only modules that fit. TX GPS shows its details in a full-width field on an 800x480 screen.\n+ Field: add another equal field when current modules and all offered choices fit.\nRemove field: delete this field.\n+ Row: add a row while the screen has room.\nRemove row: delete this row."
  return { message = message }
end
