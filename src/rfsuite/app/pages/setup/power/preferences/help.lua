return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.setup_power_preferences.help_message")
    or "Configure the model type, the local SmartFuel source, whether SmFt and SmCp are "
    .. "published as sensors, and the current limit the speed controller is set to allow. "
    .. "Nothing here is written to the flight controller: the settings are kept on the "
    .. "radio, per flight controller."

  return {
    message = message
  }
end