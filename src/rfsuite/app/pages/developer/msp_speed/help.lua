return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local key = "app.pages.developer_msp_speed.help_message"
  local fallback = "Measure MSP link performance and inspect timing, retries, and timeout statistics."

  local message = fallback
  if i18n and i18n.t then
    local translated = i18n.t(key)
    if translated and translated ~= key and translated ~= "" then
      message = translated
    end
  end

  return { message = message }
end
