return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.setup_power_battery.help_message")
    or "The flight controller's battery profiles, the pack's cell voltages and cell count, and the consumption reserve; each row's ? explains its setting."

  return {
    message = message
  }
end
