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
  local t = Common and Common.pageT("flight_tuning_advanced_main_rotor") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Collective Pitch Compensation: Increasing will compensate for the pitching motion caused by tail drag when climbing.")
  local help_p2 = t(i18n, "help_p2", "Cross Coupling Gain: Removes roll coupling when only elevator is applied.")
  local help_p3 = t(i18n, "help_p3", "Cross Coupling Ratio: Amount of compensation (pitch vs roll) to apply.")
  local help_p4 = t(i18n, "help_p4", "Cross Coupling Freq. Limit: Frequency limit for the compensation, higher value will make the compensation action faster.")

  local parts = { help_p1, help_p2, help_p3, help_p4 }

  return {
    title = t(i18n, "help_title", "Main Rotor Help"),
    message = table.concat(parts, "\n\n")
  }
end
