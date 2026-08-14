local Api = {
  command = 2,
  simulatorResponse = { 82, 79, 84, 79, 82, 70, 76, 73, 71, 72, 84 }
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf == 0 then return nil end
  
  -- Parse variant name (null-terminated string)
  local name = ""
  for i, byte in ipairs(buf) do
    local n = tonumber(byte) or 0
    if n == 0 then break end
    name = name .. string.char(n)
  end
  
  return {
    variant = name
  }
end

return Api
