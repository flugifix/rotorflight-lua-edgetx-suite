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
  local t = Common and Common.pageT("flight_tuning_rates") or function(_, k) return k end
  local i18n = ctx and ctx.i18n

  local parts = {
    t(i18n, "table_help_p1"),
    t(i18n, "table_help_p2")
  }

  return {
    title = t(i18n, "rate_table"),
    message = table.concat(parts, "\n\n")
  }
end
