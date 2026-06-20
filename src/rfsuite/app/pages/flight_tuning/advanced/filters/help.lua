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

  local help_p1 = t(i18n, "help_p1", "Typically you would not edit this page without checking your Blackbox logs!")
  local help_p2 = t(i18n, "help_p2", "Gyro lowpass: Lowpass filters for the gyro signal. Typically left at default.")
  local help_p3 = t(i18n, "help_p3", "Gyro notch filters: Use for filtering specific frequency ranges. Typically not needed in most helis.")
  local help_p4 = t(i18n, "help_p4", "Dynamic Notch Filters: Automatically creates notch filters within the min and max frequency range.")

  local parts = { help_p1, help_p2, help_p3, help_p4 }

  return {
    title = t(i18n, "help_title", "Filters Help"),
    message = table.concat(parts, "\n\n")
  }
end
