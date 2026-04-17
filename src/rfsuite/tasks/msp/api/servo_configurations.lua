-- EdgeTX MSP API: SERVO_CONFIGURATIONS (ported)

local Api = {
  command = 120
}

local SERVO_FIELDS = {
  {"mid", "U16"},
  {"min", "S16"},
  {"max", "S16"},
  {"rneg", "U16"},
  {"rpos", "U16"},
  {"rate", "U16"},
  {"speed", "U16"},
  {"flags", "U16"}
}

local SIM_RESPONSE = {
  4,
  180,5, 12,254, 244,1, 244,1, 144,0, 0,0, 1,0,
  160,5, 12,254, 244,1, 244,1, 144,0, 0,0, 1,0,
  14,6, 12,254, 244,1, 244,1, 144,0, 0,0, 0,0,
  120,5, 212,254, 44,1, 244,1, 77,1, 0,0, 0,0
}

local function read_s16_le(buf, pos)
  local lo = tonumber(buf[pos]) or 0
  local hi = tonumber(buf[pos+1]) or 0
  local val = lo + hi * 256
  if val >= 32768 then val = val - 65536 end
  return val
end

local function read_u16_le(buf, pos)
  local lo = tonumber(buf[pos]) or 0
  local hi = tonumber(buf[pos+1]) or 0
  return lo + hi * 256
end

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local pos = 1
  local servoCount = tonumber(buf[pos]) or 0
  pos = pos + 1
  local parsed = { servo_count = servoCount, servos = {} }
  for i = 1, servoCount do
    local servo = {}
    parsed.servos[i - 1] = servo
    for _, tuple in ipairs(SERVO_FIELDS) do
      local name, typ = tuple[1], tuple[2]
      if typ == "U16" then
        servo[name] = read_u16_le(buf, pos); pos = pos + 2
        parsed["servo_" .. i .. "_" .. name] = servo[name]
      elseif typ == "S16" then
        servo[name] = read_s16_le(buf, pos); pos = pos + 2
        parsed["servo_" .. i .. "_" .. name] = servo[name]
      else
        servo[name] = tonumber(buf[pos]) or 0; pos = pos + 1
        parsed["servo_" .. i .. "_" .. name] = servo[name]
      end
    end
  end
  return { parsed = parsed }
end

Api.simulatorResponse = SIM_RESPONSE

return Api
