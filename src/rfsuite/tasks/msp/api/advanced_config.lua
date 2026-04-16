-- EdgeTX MSP API: ADVANCED_CONFIG
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 90, -- MSP_ADVANCED_CONFIG
  writeCommand = 91, -- MSP_SET_ADVANCED_CONFIG
  simulatorResponse = { 1, 1, 0, 0, 232, 3 },
}

-- Helper to parse unsigned 16-bit from two bytes (little endian)
local function parseU16(lo, hi)
  return (tonumber(hi) or 0) << 8 | (tonumber(lo) or 0)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 6 then return nil end
  return {
    gyro_sync_denom_compat = buf[1] or 1,
    pid_process_denom = buf[2] or 1,
    use_unsynced_pwm = buf[3] or 0,
    motor_pwm_protocol = buf[4] or 0,
    motor_pwm_rate = parseU16(buf[5], buf[6])
  }
end

-- Optional: buildWritePayload for writing new values (only writable fields)
function Api.buildWritePayload(data)
  local gyro_sync = tonumber(data.gyro_sync_denom_compat) or 1
  local pid_denom = tonumber(data.pid_process_denom) or 1
  return { gyro_sync, pid_denom }
end

return Api
