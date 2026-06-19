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
  local t = Common and Common.pageT("flight_tuning_rates_advanced_cyclic_behaviour") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Polar coordinates: Defines cyclic rates using polar (magnitude and angle) coordinates instead of independent Roll and Pitch rates.")
  local help_p2 = t(i18n, "help_p2", "Cyclic ring: Limits the total cyclic stick deflection to a circular shape, preventing excessive combined roll and pitch deflection.")

  return {
    title = t(i18n, "help_title", "Cyclic Behaviour"),
    message = help_p1 .. "\n\n" .. help_p2
  }
end
