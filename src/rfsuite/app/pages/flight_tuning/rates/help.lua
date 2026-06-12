return function(ctx)
  local i18n = ctx.i18n
  local t = i18n and i18n.t or function(k) return k end

  local title = t("app.pages.flight_tuning_rates.help_title", "Rates")
  local ratesType = ctx.ratesType or 6 -- Default Rotorflight
  
  local parts = {}
  local helpText = t("app.pages.flight_tuning_rates.help_table_" .. tostring(ratesType))
  if helpText and helpText ~= "app.pages.flight_tuning_rates.help_table_" .. tostring(ratesType) then
    parts[#parts + 1] = helpText
  end
  
  if #parts == 0 then
    parts[1] = t("app.pages.flight_tuning_rates.help_message", "Configure the rotation rates and stick feel.")
  end

  return {
    title = title,
    message = table.concat(parts, "\n\n")
  }
end
