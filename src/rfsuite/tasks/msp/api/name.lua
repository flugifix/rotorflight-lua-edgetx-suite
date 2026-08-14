-- EdgeTX MSP API: name (ported from Ethos)

local Api = {
  command = 10,
  writeCommand = 11,
  simulatorResponse = {80, 105, 108, 111, 116}
}

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local name = ""
  for i = 1, #buf do
    local ch = tonumber(buf[i])
    if ch == nil or ch == 0 then break end
    name = name .. string.char(ch)
  end
  return {name = name}
end

function Api.buildWritePayload(data)
  local nameValue = data and data.name
  if nameValue == nil then nameValue = "" end
  if type(nameValue) ~= "string" then nameValue = tostring(nameValue) end
  local payload = {}
  local length = math.min(#nameValue, 16)
  for i = 1, length do
    payload[#payload + 1] = string.byte(nameValue, i)
  end
  return payload
end

return Api
