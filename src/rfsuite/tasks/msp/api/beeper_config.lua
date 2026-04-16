-- EdgeTX MSP API: BEEPER_CONFIG
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 184, -- MSP_BEEPER_CONFIG
  writeCommand = 185, -- MSP_SET_BEEPER_CONFIG
  simulatorResponse = {
    0, 0, 0, 0, -- beeper_off_flags
    1,          -- dshotBeaconTone
    0, 0, 0, 0  -- dshotBeaconOffFlags
  },
}

local function parseU32(b1, b2, b3, b4)
  return (tonumber(b4) or 0) << 24 | (tonumber(b3) or 0) << 16 | (tonumber(b2) or 0) << 8 | (tonumber(b1) or 0)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 9 then return nil end
  local beeper_off_flags = parseU32(buf[1], buf[2], buf[3], buf[4])
  local dshotBeaconTone = buf[5] or 0
  local dshotBeaconOffFlags = parseU32(buf[6], buf[7], buf[8], buf[9])
  return {
    beeper_off_flags = beeper_off_flags,
    dshotBeaconTone = dshotBeaconTone,
    dshotBeaconOffFlags = dshotBeaconOffFlags
  }
end

function Api.buildWritePayload(data)
  local function toU32(val)
    val = tonumber(val) or 0
    return val & 0xFF, (val >> 8) & 0xFF, (val >> 16) & 0xFF, (val >> 24) & 0xFF
  end
  local b1, b2, b3, b4 = toU32(data.beeper_off_flags)
  local dshotBeaconTone = tonumber(data.dshotBeaconTone) or 0
  local db1, db2, db3, db4 = toU32(data.dshotBeaconOffFlags)
  return { b1, b2, b3, b4, dshotBeaconTone, db1, db2, db3, db4 }
end

return Api
