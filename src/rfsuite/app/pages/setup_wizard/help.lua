local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

-- Help is per PROCEDURE rather than per page. The screens carry controls and the sentences live
-- here, which is what keeps a screen inside its own height: every explanatory line removed from
-- the body is a control row gained.
--
-- Their help registry is keyed by menu id and a procedure is not a manifest entry, so the route
-- from a procedure to its text does not exist in the tree -- this is that route, kept small.
return function(ctx, proc)
  local Common = loadModule("app/pages/settings/common.lua")
  local t = Common and Common.pageT("setup_wizard") or function(_, _, fb) return fb end
  local i18n = ctx and ctx.i18n

  local key = proc and ("help_" .. tostring(proc.id)) or "help_opening"
  local body = t(i18n, key, nil)
  if body == nil or body == key then
    body = t(i18n, "help_general",
      "This assistant walks the first setup of a bare flight controller. It proposes, shows " ..
      "what it will do, and writes only after a press.")
  end

  return {
    title = t(i18n, "help_title", "Setup Assistant"),
    message = body
  }
end
