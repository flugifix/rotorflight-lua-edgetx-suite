if type(_G) == "table" and type(_G.__rfsuite_env_module) == "table" then
  return _G.__rfsuite_env_module
end

local M = {}

-- Returns the current execution environment: "tool" or "widget"
function M.get()
  if _G and _G.rfsuite and _G.rfsuite.session and _G.rfsuite.session.event_context then
    return _G.rfsuite.session.event_context
  end

  -- Default to "tool" if not explicitly set (e.g. when running from main.lua)
  return "tool"
end

function M.isTool()
  return M.get() == "tool"
end

function M.isWidget()
  return M.get() == "widget"
end

if type(_G) == "table" then
  _G.__rfsuite_env_module = M
end

return M
