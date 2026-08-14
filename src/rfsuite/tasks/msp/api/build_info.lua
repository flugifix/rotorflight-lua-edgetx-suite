local Api = {
  command = 5,
  simulatorResponse = { 68, 101, 99, 32, 49, 50, 32, 50, 48, 50, 52, 32, 49, 51, 58, 50, 48, 58, 51, 50 } -- "Dec 12 2024 13:20:32"
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf == 0 then return nil end
  
  -- Parse build date/time string (variable length, space-separated components)
  local buildInfo = ""
  for i, byte in ipairs(buf) do
    if byte == 0 then break end
    buildInfo = buildInfo .. string.char(byte)
  end
  
  return {
    buildInfo = buildInfo
  }
end

return Api
