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
  local t = Common and Common.pageT("setup_alignment") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Set board roll, pitch and yaw mounting offsets.")
  local help_p2 = t(i18n, "help_p2", "Set magnetometer alignment and save to write EEPROM.")
  local help_p3 = t(i18n, "help_p3", "The visual follows live attitude from MSP.")
  local help_lv = t(i18n, "live_view_help", "Toggle Live View to enable real-time updates. Turning it off keeps focus stable during edits.")

  local parts = { help_p1, help_p2, help_p3, help_lv }

  return {
    title = t(i18n, "help_title", "Alignment Help"),
    message = table.concat(parts, "\n\n")
  }
end
