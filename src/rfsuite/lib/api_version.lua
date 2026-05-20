local M = {}

local function toNumber(value)
  local n = tonumber(value)
  if n == nil then return nil end
  return math.floor(n)
end

function M.parse(value)
  if type(value) == "table" then
    local major = toNumber(value[1])
    local minor = toNumber(value[2])
    local patch = toNumber(value[3]) or 0
    if major == nil or minor == nil then return nil end
    return { major, minor, patch }
  end

  if type(value) ~= "string" then return nil end

  local major, minor, patch = string.match(value, "^(%d+)%.(%d+)%.(%d+)$")
  if major then
    return { tonumber(major), tonumber(minor), tonumber(patch) }
  end

  major, minor = string.match(value, "^(%d+)%.(%d+)$")
  if major then
    return { tonumber(major), tonumber(minor), 0 }
  end

  return nil
end

function M.isAtLeast(current, required)
  local a = current
  local b = required

  if type(a) ~= "table" then
    a = M.parse(a)
  end
  if type(b) ~= "table" then
    b = M.parse(b)
  end
  if type(a) ~= "table" or type(b) ~= "table" then return false end

  for i = 1, 3 do
    local av = tonumber(a[i]) or 0
    local bv = tonumber(b[i]) or 0
    if av > bv then return true end
    if av < bv then return false end
  end

  return true
end

return M
