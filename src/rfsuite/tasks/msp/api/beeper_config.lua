-- EdgeTX MSP API: BEEPER_CONFIG
-- Ported from Ethos style to EdgeTX schema (Api table + parse)

local Api = {
  command = 184, -- MSP_BEEPER_CONFIG
  writeCommand = 185, -- MSP_SET_BEEPER_CONFIG
  simulatorResponse = { 
    0, 0, 0, 0, -- beeper_off_flags (U32)
    1,          -- dshotBeaconTone (U8)
    0, 0, 0, 0  -- dshotBeaconOffFlags (U32)
  }
}

local function parseU32(b1, b2, b3, b4)
  return (tonumber(b4) or 0) * 16777216 + (tonumber(b3) or 0) * 65536 + (tonumber(b2) or 0) * 256 + (tonumber(b1) or 0)
end

local function packU32(val)
  val = math.floor(tonumber(val) or 0)
  local b1 = val & 0xFF
  local b2 = (val >> 8) & 0xFF
  local b3 = (val >> 16) & 0xFF
  local b4 = (val >> 24) & 0xFF
  return b1, b2, b3, b4
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 5 then return nil end
  local beeper_off_flags = parseU32(buf[1], buf[2], buf[3], buf[4])
  local dshotBeaconTone = tonumber(buf[5]) or 1
  local dshotBeaconOffFlags = 0
  if #buf >= 9 then
    dshotBeaconOffFlags = parseU32(buf[6], buf[7], buf[8], buf[9])
  end
  return {
    beeper_off_flags = beeper_off_flags,
    dshotBeaconTone = dshotBeaconTone,
    dshotBeaconOffFlags = dshotBeaconOffFlags
  }
end

function Api.buildWritePayload(data)
  local offFlags = tonumber(data.beeper_off_flags) or 0
  local tone = tonumber(data.dshotBeaconTone) or 1
  local beaconOffFlags = tonumber(data.dshotBeaconOffFlags) or 0

  local o1, o2, o3, o4 = packU32(offFlags)
  local b1, b2, b3, b4 = packU32(beaconOffFlags)

  return { o1, o2, o3, o4, tone, b1, b2, b3, b4 }
end

return Api
