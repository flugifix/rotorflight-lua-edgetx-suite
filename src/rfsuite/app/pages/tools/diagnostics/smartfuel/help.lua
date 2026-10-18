return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.diagnostics_smartfuel.help_message")
    or "Smart Fuel and Smart mAh clear when the estimate is unavailable. Reload refreshes other rows."

  return { message = message }
end
