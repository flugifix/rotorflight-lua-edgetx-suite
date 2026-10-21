-- EdgeTX MSP API: SERVO_OVERRIDE (ported)
-- Optional timeouts must only be used after a firmware capability probe.

local Api = {
  command = 192,
  writeCommand = 193
}

local FIELD_SPEC = {
  {"servo_1", "U16"}, {"servo_2", "U16"}, {"servo_3", "U16"}, {"servo_4", "U16"},
  {"servo_5", "U16"}, {"servo_6", "U16"}, {"servo_7", "U16"}, {"servo_8", "U16"}
}

local WRITE_FIELD_SPEC = {
  {"servo_id", "U8"}, {"action", "U16"}
}

local SIM_RESPONSE = {209,7, 209,7, 209,7, 209,7, 209,7, 209,7, 209,7, 209,7}

Api.fields = FIELD_SPEC
Api.simulatorResponse = SIM_RESPONSE

local function read_u16_le(buf, pos)
  local lo = tonumber(buf[pos]) or 0
  local hi = tonumber(buf[pos+1]) or 0
  return lo + hi * 256
end

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local parsed = {}
  local pos = 1
  for i = 1, 8 do
    parsed["servo_" .. i] = read_u16_le(buf, pos)
    pos = pos + 2
  end
  return parsed
end

function Api.buildWritePayload(data)
  local id = tonumber(data and data.servo_id) or 0
  local action = tonumber(data and data.action) or 0
  local lo = action % 256
  local hi = math.floor(action / 256) % 256
  local p = { id, lo, hi }
  if data.timeout ~= nil then
    local timeout = math.floor(math.max(500, math.min(30000, data.timeout)))
    p[4], p[5] = timeout % 256, math.floor(timeout / 256) % 256
  end
  return p
end

return Api
