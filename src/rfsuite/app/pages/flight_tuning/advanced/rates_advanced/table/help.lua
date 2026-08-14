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
  local t = Common and Common.pageT("flight_tuning_rates") or function(_, _, fb) return fb end
  local i18n = ctx.i18n

  local help_p1 = t(i18n, "table_help_p1", "Rates type: Choose the rate type you prefer flying with. Raceflight and Actual are the most straightforward.")
  local help_p2 = t(i18n, "table_help_p2", "Dynamics: Applied regardless of rates type. Typically left on defaults but can be adjusted to smooth heli movements, like with scale helis.")

  return {
    title = t(i18n, "rate_table", "Rate Table"),
    message = help_p1 .. "\n\n" .. help_p2
  }
end
