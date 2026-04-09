local M = {}

M.MAJOR = 1
M.MINOR = 0
M.PATCH = 0

M.VERSION = M.MAJOR .. "." .. M.MINOR .. "." .. M.PATCH

function M.getVersionString()
  return "v" .. M.VERSION
end

return M
