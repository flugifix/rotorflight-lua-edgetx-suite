return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local message = i18n and i18n.t and i18n.t("app.pages.diagnostics_smartfuel.help_message")
    or "Read-only snapshot; Reload reads the configuration again.\nSmart Fuel: Remaining fuel after reserve; - while the local estimate is unavailable. Clears and recovers without Reload.\nSmart mAh: Estimated consumption; - while unavailable. Other rows keep their snapshot until Reload."

  return { message = message }
end
