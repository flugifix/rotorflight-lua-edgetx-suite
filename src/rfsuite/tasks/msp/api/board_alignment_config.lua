-- EdgeTX MSP API: BOARD_ALIGNMENT_CONFIG
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 38, -- MSP_BOARD_ALIGNMENT_CONFIG
  writeCommand = 39, -- MSP_SET_BOARD_ALIGNMENT_CONFIG
  simulatorResponse = {
    0, 0, -- roll_degrees
    0, 0, -- pitch_degrees
    0, 0  -- yaw_degrees
  },
}

local function parseU16(lo, hi)
  return (tonumber(hi) or 0) << 8 | (tonumber(lo) or 0)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 6 then return nil end
  return {
    roll_degrees = parseU16(buf[1], buf[2]),
    pitch_degrees = parseU16(buf[3], buf[4]),
    yaw_degrees = parseU16(buf[5], buf[6])
  }
end

function Api.buildWritePayload(data)
  local function toU16(val)
    val = tonumber(val) or 0
    return val & 0xFF, (val >> 8) & 0xFF
  end
  local rLo, rHi = toU16(data.roll_degrees)
  local pLo, pHi = toU16(data.pitch_degrees)
  local yLo, yHi = toU16(data.yaw_degrees)
  return { rLo, rHi, pLo, pHi, yLo, yHi }
end

return Api
