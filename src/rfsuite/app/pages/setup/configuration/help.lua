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
  local t = Common and Common.pageT("setup_configuration") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Use this page for system-level setup such as craft name, PID loop speed, and feature flags.")
  local help_p2 = t(i18n, "help_p2", "Saving writes these values to EEPROM and reboots the flight controller.")

  local parts = { help_p1, help_p2 }

  return {
    title = t(i18n, "help_title", "Configuration Help"),
    message = table.concat(parts, "\n\n")
  }
end
