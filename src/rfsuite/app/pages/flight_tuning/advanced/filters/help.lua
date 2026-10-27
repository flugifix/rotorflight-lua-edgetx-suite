local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

return function(ctx)
  local Common = loadModule("app/pages/settings/common.lua")
  local t = Common and Common.pageT("flight_tuning_advanced_filters") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Filters remove vibration noise from the gyro signal.")
  local help_p2 = t(i18n, "help_p2", "Lowpass 1: Selects no filter, first-order or second-order filtering and sets the first gyro lowpass cutoff in Hz.")
  local help_p4 = t(i18n, "help_p4", "Lowpass 1 dyn.: Sets the minimum and maximum cutoff in Hz as the first lowpass follows main rotor RPM.")
  local help_lpf2 = t(i18n, "help_lpf2", "Lowpass 2: Selects no filter, first-order or second-order filtering and sets the second gyro lowpass cutoff in Hz.")
  local help_notch1 = t(i18n, "help_notch1", "Notch 1: Sets the center frequency and lower cutoff of the first static notch in Hz.")
  local help_notch2 = t(i18n, "help_notch2", "Notch 2: Sets the center frequency and lower cutoff of the second static notch in Hz.")
  local help_dyn = t(i18n, "help_dyn", "Dynamic Filters: Sets notch count, Q (higher is narrower) and minimum and maximum tracking frequencies in Hz.")
  local help_rpm = t(i18n, "help_rpm", "RPM filter: Selects the preset strength and sets the minimum frequency slightly below the lowest flying main rotor frequency.")

  local parts = { help_p1, help_p2, help_p4, help_lpf2, help_notch1, help_notch2, help_dyn, help_rpm }

  return {
    title = t(i18n, "help_title", "Filters Help"),
    message = table.concat(parts, "\n")
  }
end
