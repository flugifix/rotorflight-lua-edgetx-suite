-- EdgeTX MSP API: SET_SERVO_OVERRIDE_ALL (MSP_SET_SERVO_OVERRIDE_ALL, 196, write only)
--
-- One U16 value for every servo (2001 releases them) and, only when the caller supplies
-- `timeout`, a U16 timeout in ms. A timed OFF is also a harmless capability probe: firmware
-- without override timeouts refuses the four-byte payload, whereas it can silently accept a
-- five-byte per-servo write. A missing value, or a timeout that is not a number, is refused.

local Api = { writeCommand = 196 }

function Api.buildWritePayload(data)
  if type(data) ~= "table" or type(data.value) ~= "number" then return nil end
  if data.timeout ~= nil and type(data.timeout) ~= "number" then return nil end
  local value = math.floor(data.value) & 0xFFFF
  local p = { value & 255, (value >> 8) & 255 }
  if data.timeout ~= nil then
    local timeout = math.max(500, math.min(30000, math.floor(data.timeout)))
    p[3], p[4] = timeout & 255, (timeout >> 8) & 255
  end
  return p
end

return Api
