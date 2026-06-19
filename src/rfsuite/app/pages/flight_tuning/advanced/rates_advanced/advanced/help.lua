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
  local t = Common and Common.pageT("flight_tuning_rates_advanced_advanced") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Response Time: Defines how quickly the control system responds to stick inputs on each axis.")
  local help_p2 = t(i18n, "help_p2", "Accelerometer Limit: Limits the maximum acceleration allowed to smooth cyclic and yaw movements.")
  
  local parts = { help_p1, help_p2 }

  -- Setpoint and deadband are conditionally supported based on API version >= 12.0.8.
  -- We fetch them if available.
  local help_p3 = t(i18n, "help_p3", "")
  if help_p3 ~= "" then
    parts[#parts + 1] = help_p3
  end

  local help_p4 = t(i18n, "help_p4", "")
  if help_p4 ~= "" then
    parts[#parts + 1] = help_p4
  end

  return {
    title = t(i18n, "help_title", "Dynamics Help"),
    message = table.concat(parts, "\n\n")
  }
end
