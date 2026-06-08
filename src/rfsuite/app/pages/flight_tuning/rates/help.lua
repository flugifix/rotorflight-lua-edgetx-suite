return function(ctx)
  local i18n = ctx.i18n
  local t = i18n and i18n.t or function(k) return k end

  local title = t("app.pages.flight_tuning_rates.help_title", "Rates")
  local msg = t("app.pages.flight_tuning_rates.help_message", "Configure the rotation rates and stick feel.")

  -- In Ethos this is dynamic based on rate profile type,
  -- but for now a generic help text is provided to give basic context.
  
  return {
    title = title,
    message = msg
  }
end
