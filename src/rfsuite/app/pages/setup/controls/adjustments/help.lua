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
  local t = Common and Common.pageT("setup_adjustments") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Configure Adjustment Function ranges and channels.")
  local help_p2 = t(i18n, "help_p2", "Use Save once after all edits to write every range and then EEPROM.")

  local parts = { help_p1, help_p2 }

  return {
    title = t(i18n, "help_title", "Adjustments Help"),
    message = table.concat(parts, "\n\n")
  }
end
