-- A timed OFF is also a harmless capability probe: pre-timeout firmware rejects
-- the four-byte payload, whereas it can silently accept a five-byte per-servo write.
local Api = { writeCommand = 196 }
function Api.buildWritePayload(data)
  local value = math.floor(data.value) & 0xFFFF
  local p = { value & 255, (value >> 8) & 255 }
  if data.timeout ~= nil then
    local timeout = math.max(500, math.min(30000, math.floor(data.timeout)))
    p[3], p[4] = timeout & 255, (timeout >> 8) & 255
  end
  return p
end
return Api
