return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local key = "app.pages.settings_dashboard_settings.help_message"
  local fallback = "Configure settings exposed by the selected dashboard theme."

  local message = fallback
  if i18n and i18n.t then
    local translated = i18n.t(key)
    if translated and translated ~= key and translated ~= "" then
      message = translated
    end
  end

  return { message = message }
end
