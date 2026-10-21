-- MSP_MOTOR_TELEMETRY: count followed by 16 bytes per motor.
local Api = { command = 139, simulatorResponse = {0} }
local function u16(b, p) return b[p] + b[p + 1] * 256 end
local function s16(b, p)
  local v = u16(b, p)
  if v >= 32768 then v = v - 65536 end
  return v
end
function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 1 then return nil end
  local count = buf[1]
  if count > 4 or #buf ~= 1 + count * 16 then return nil end
  local motors = {}
  for i = 1, count do
    local p = 2 + (i - 1) * 16
    motors[i] = {
      rpm = u16(buf, p) + u16(buf, p + 2) * 65536,
      invalid_percent = u16(buf, p + 4), voltage = u16(buf, p + 6),
      current = u16(buf, p + 8), consumption = u16(buf, p + 10),
      temperature = s16(buf, p + 12), temperature2 = s16(buf, p + 14)
    }
  end
  return { motors = motors, motor_count = count }
end
return Api
