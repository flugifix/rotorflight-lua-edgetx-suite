local M = {}

function M.append(children, supported, definition)
  if supported ~= true or type(children) ~= "table" or type(definition) ~= "table" then return 0 end
  children[#children + 1] = definition
  return 1
end

return M
