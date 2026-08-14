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
  local t = Common and Common.pageT("setup_modes") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "help_p1", "Flight modes allow you to map radio channels (AUX) to specific features on the flight controller (such as Stabilize, Governor, etc.).")
  local help_p2 = t(i18n, "help_p2", "Add a range, select the channel, logic, and adjust the slider limits. Press 'Set' to automatically configure limits using your current radio switch position.")

  local parts = { help_p1, help_p2 }

  return {
    title = t(i18n, "help_title", "Modes Help"),
    message = table.concat(parts, "\n\n")
  }
end
