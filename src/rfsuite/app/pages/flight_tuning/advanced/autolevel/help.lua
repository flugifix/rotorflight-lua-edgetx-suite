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
  local t = Common and Common.pageT("flight_tuning_advanced_autolevel") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Acro Trainer: How aggressively the heli tilts back to level when flying in Acro Trainer Mode.")
  local help_p2 = t(i18n, "help_p2", "Angle Mode: How aggressively the heli tilts back to level when flying in Angle Mode.")
  local help_p3 = t(i18n, "help_p3", "Horizon Mode: How aggressively the heli tilts back to level when flying in Horizon Mode.")

  local parts = { help_p1, help_p2, help_p3 }

  return {
    title = t(i18n, "help_title", "Autolevel Help"),
    message = table.concat(parts, "\n\n")
  }
end
