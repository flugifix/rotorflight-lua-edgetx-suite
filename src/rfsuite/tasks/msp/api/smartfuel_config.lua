-- EdgeTX MSP API: SMARTFUEL_CONFIG (ported)

local Api = {
  command = 0x3006,
  writeCommand = 0x3007
}

local FIELD_SPEC = {
    {"smartfuel_source", "U8", 0, 1, 0},
    {"stabilize_delay", "U16", 0, 10000, 1500, "s", 1, 1000, 1},
    {"stable_window", "U16", 0, 100, 15, "V", 2, 100, 1},
    {"voltage_fall_limit", "U16", 0, 100, 5, "V/s", 2, 100, 1},
    {"fuel_drop_rate", "U16", 0, 500, 10, "%/s", 1, 10, 1},
    {"fuel_rise_rate", "U16", 0, 500, 2, "%/s", 1, 10, 1},
    {"sag_multiplier_percent", "U16", 0, 200, 70, "x", 2, 100, 1}
}

local SIM_RESPONSE = {0, 220,5, 15,0, 5,0, 10,0, 2,0, 70,0}

Api.fields = FIELD_SPEC
Api.simulatorResponse = SIM_RESPONSE

local function read_u16_le(buf, pos)
  local lo = tonumber(buf[pos]) or 0
  local hi = tonumber(buf[pos+1]) or 0
  return lo + hi * 256
end

local function pack_u16_le(v)
  v = tonumber(v) or 0
  local lo = v % 256
  local hi = math.floor(v / 256) % 256
  return lo, hi
end

function Api.parse(buf)
  if type(buf) == "table" then
    local parsed = {}
    local pos = 1
    parsed.smartfuel_source = tonumber(buf[pos]) or 0; pos = pos + 1
    parsed.stabilize_delay = read_u16_le(buf, pos); pos = pos + 2
    parsed.stable_window = read_u16_le(buf, pos); pos = pos + 2
    parsed.voltage_fall_limit = read_u16_le(buf, pos); pos = pos + 2
    parsed.fuel_drop_rate = read_u16_le(buf, pos); pos = pos + 2
    parsed.fuel_rise_rate = read_u16_le(buf, pos); pos = pos + 2
    parsed.sag_multiplier_percent = read_u16_le(buf, pos); pos = pos + 2
    return { parsed = parsed }
  end
  local def = {}
  for _, e in ipairs(FIELD_SPEC) do def[e[1]] = e[5] or 0 end
  return { parsed = def }
end

function Api.buildWritePayload(data)
  local payload = {}
  payload[#payload+1] = tonumber(data.smartfuel_source) or 0
  local lo,hi = pack_u16_le(tonumber(data.stabilize_delay) or 0); payload[#payload+1]=lo; payload[#payload+1]=hi
  lo,hi = pack_u16_le(tonumber(data.stable_window) or 0); payload[#payload+1]=lo; payload[#payload+1]=hi
  lo,hi = pack_u16_le(tonumber(data.voltage_fall_limit) or 0); payload[#payload+1]=lo; payload[#payload+1]=hi
  lo,hi = pack_u16_le(tonumber(data.fuel_drop_rate) or 0); payload[#payload+1]=lo; payload[#payload+1]=hi
  lo,hi = pack_u16_le(tonumber(data.fuel_rise_rate) or 0); payload[#payload+1]=lo; payload[#payload+1]=hi
  lo,hi = pack_u16_le(tonumber(data.sag_multiplier_percent) or 0); payload[#payload+1]=lo; payload[#payload+1]=hi
  return payload
end

return Api
