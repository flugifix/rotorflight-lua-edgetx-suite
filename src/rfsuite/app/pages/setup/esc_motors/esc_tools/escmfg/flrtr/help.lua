-- The page overview stays in a local fallback: the precompiler replaces the call together
-- with the first literal after `or`, so text appended there would follow the translation.
return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local fallback = "Reads and writes the Flyrotor ESC's parameters so its protections, startup behaviour and governor can be configured from the radio."
  local message = i18n and i18n.t and i18n.t("app.pages.setup_esc_motors.help_flrtr") or fallback
  return { message = message }
end
