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
  local t = Common and Common.pageT("setup_accelerometer") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1",
    "The trims correct a drift in modes such as Angle, Horizon and Rescue; Save writes them to EEPROM. The * button calibrates: disarm, then hold the model level and still until the notice.")
  local help_p2 = t(i18n, "help_p2", "Roll: raise it to correct a drift to the left, lower it for a drift to the right.")
  local help_p3 = t(i18n, "help_p3", "Pitch: raise it to correct a drift to the rear, lower it for a drift to the front.")

  local parts = { help_p1, help_p2, help_p3 }

  return {
    title = t(i18n, "help_title", "Accelerometer Help"),
    message = table.concat(parts, "\n")
  }
end
