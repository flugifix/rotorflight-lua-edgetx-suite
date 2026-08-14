local Api = {
  command = 1,
  simulatorResponse = { 0, 12, 9 }
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 3 then return nil end
  local major = tonumber(buf[2]) or 0
  local minor = tonumber(buf[3]) or 0
  return {
    major = major,
    minor = minor,
    version = string.format("%d.%02d", major, minor)
  }
end

return Api
