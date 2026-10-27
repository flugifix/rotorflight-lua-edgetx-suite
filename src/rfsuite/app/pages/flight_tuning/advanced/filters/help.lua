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
  local help_p2 = t(i18n, "help_p2", "Lowpass 1 Filter type: Selects no filter, first-order or second-order filtering.")
  local help_p3 = t(i18n, "help_p3", "Lowpass 1 Cutoff: Sets the static cutoff frequency in Hz.")
  local help_p4 = t(i18n, "help_p4", "Lowpass 1 dyn. Min cutoff: Sets the lower limit of the cutoff that follows main rotor RPM.")
  local help_lpf1_max = t(i18n, "help_lpf1_max", "Max cutoff: Sets the upper limit of the dynamic lowpass cutoff in Hz.")
  local help_lpf2_type = t(i18n, "help_lpf2_type", "Lowpass 2 Filter type: Selects no filter, first-order or second-order filtering.")
  local help_lpf2_cutoff = t(i18n, "help_lpf2_cutoff", "Lowpass 2 Cutoff: Sets the second lowpass cutoff frequency in Hz.")
  local help_notch1_center = t(i18n, "help_notch1_center", "Notch 1 Center: Sets the frequency of strongest attenuation in Hz.")
  local help_notch1_cutoff = t(i18n, "help_notch1_cutoff", "Notch 1 Cutoff: Sets the lower edge of the filtered frequency band in Hz.")
  local help_notch2_center = t(i18n, "help_notch2_center", "Notch 2 Center: Sets the frequency of strongest attenuation in Hz.")
  local help_notch2_cutoff = t(i18n, "help_notch2_cutoff", "Notch 2 Cutoff: Sets the lower edge of the filtered frequency band in Hz.")
  local help_dyn_count = t(i18n, "help_dyn_count", "Dynamic Filters: Notch Count selects how many notches track noise peaks automatically.")
  local help_dyn_q = t(i18n, "help_dyn_q", "Dynamic Filters: Notch Q sets notch width; higher values make it narrower.")
  local help_dyn_min = t(i18n, "help_dyn_min", "Min: Sets the lowest frequency tracked by dynamic notch filters in Hz.")
  local help_dyn_max = t(i18n, "help_dyn_max", "Max: Sets the highest frequency tracked by dynamic notch filters in Hz.")
  local help_rpm_type = t(i18n, "help_rpm_type", "RPM filter Type: Selects the preset strength; stronger filtering adds delay.")
  local help_rpm_min = t(i18n, "help_rpm_min", "RPM filter Min. Frequency: Sets the minimum frequency, slightly below the lowest flying main rotor frequency.")

  local parts = { help_p1, help_p2, help_p3, help_p4, help_lpf1_max, help_lpf2_type, help_lpf2_cutoff,
    help_notch1_center, help_notch1_cutoff, help_notch2_center, help_notch2_cutoff,
    help_dyn_count, help_dyn_q, help_dyn_min, help_dyn_max, help_rpm_type, help_rpm_min }

  return {
    title = t(i18n, "help_title", "Filters Help"),
    message = table.concat(parts, "\n")
  }
end
