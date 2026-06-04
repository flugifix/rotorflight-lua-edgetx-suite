return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local key = "app.pages.diagnostics_validate_sensors.help_message"
  local fallback = "Validates configured telemetry sensors by checking if they exist in radio telemetry and provide numeric values."

  local message = fallback
  if i18n and i18n.t then
    local translated = i18n.t(key)
    if translated and translated ~= key and translated ~= "" then
      message = translated
    end
  end

  return { message = message }
end
