-- EdgeTX MSP API: FEATURE_CONFIG (ported from Ethos)
-- Self-contained, no core/Ethos dependencies

local Api = {
  command = 36, -- MSP_API_CMD_READ
  writeCommand = 37, -- MSP_API_CMD_WRITE
  simulatorResponse = {0, 0, 0, 0} -- enabledFeatures (U32)
}

local function parseU32(b1, b2, b3, b4)
  return (tonumber(b4) or 0) << 24 | (tonumber(b3) or 0) << 16 | (tonumber(b2) or 0) << 8 | (tonumber(b1) or 0)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 4 then return nil end
  return {
    enabledFeatures = parseU32(buf[1], buf[2], buf[3], buf[4])
  }
end

function Api.buildWritePayload(data)
  local val = tonumber(data.enabledFeatures) or 0
  return {
    val & 0xFF,
    (val >> 8) & 0xFF,
    (val >> 16) & 0xFF,
    (val >> 24) & 0xFF
  }
end

return Api
