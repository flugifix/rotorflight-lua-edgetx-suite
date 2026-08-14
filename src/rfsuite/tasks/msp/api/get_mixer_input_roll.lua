-- EdgeTX MSP API: GET_MIXER_INPUT_ROLL (ported from Ethos)
-- Self-contained, no core/Ethos dependencies

local Api = {
  command = 174, -- MSP_API_CMD_READ
  writeCommand = 171, -- MSP_API_CMD_WRITE
  simulatorResponse = {
    250, 0, -- rate_stabilized_roll (U16)
    30, 251, -- min_stabilized_roll (U16)
    226, 4  -- max_stabilized_roll (U16)
  }
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 6 then return nil end
  local function parseU16(lo, hi) return (tonumber(hi) or 0) << 8 | (tonumber(lo) or 0) end
  return {
    rate_stabilized_roll = parseU16(buf[1], buf[2]),
    min_stabilized_roll = parseU16(buf[3], buf[4]),
    max_stabilized_roll = parseU16(buf[5], buf[6])
  }
end

function Api.buildWritePayload(data)
  local function toU16(val) val = math.floor(tonumber(val) or 0); return val & 0xFF, (val >> 8) & 0xFF end
  local payload = { 1 }
  local lo, hi = toU16(data.rate_stabilized_roll); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.min_stabilized_roll); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.max_stabilized_roll); payload[#payload+1] = lo; payload[#payload+1] = hi
  return payload
end

return Api
