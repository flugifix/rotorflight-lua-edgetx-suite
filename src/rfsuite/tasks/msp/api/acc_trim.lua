-- EdgeTX MSP API: ACC_TRIM
-- Ported from Ethos style to EdgeTX schema (Api table + parse)

local Api = {
  command = 240, -- MSP_ACC_TRIM
  writeCommand = 239, -- MSP_SET_ACC_TRIM
  simulatorResponse = { 0, 0, 0, 0 }, -- pitch (2 bytes), roll (2 bytes)
}

-- Helper to parse signed 16-bit int from two bytes
local function parseS16(lo, hi)
  local v = (hi << 8) | lo
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 4 then return nil end
  local pitch = parseS16(buf[1] or 0, buf[2] or 0)
  local roll  = parseS16(buf[3] or 0, buf[4] or 0)
  return {
    pitch = pitch,
    roll = roll
  }
end

-- Optional: buildWritePayload for writing new values
function Api.buildWritePayload(data)
  local pitch = math.floor(tonumber(data.pitch) or 0)
  local roll  = math.floor(tonumber(data.roll) or 0)
  local function toBytes(val)
    if val < 0 then val = val + 0x10000 end
    return val & 0xFF, (val >> 8) & 0xFF
  end
  local pLo, pHi = toBytes(pitch)
  local rLo, rHi = toBytes(roll)
  return { pLo, pHi, rLo, rHi }
end

return Api
