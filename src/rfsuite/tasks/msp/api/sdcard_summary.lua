-- EdgeTX MSP API: SDCARD_SUMMARY
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 79, -- MSP_SDCARD_SUMMARY
  simulatorResponse = {
    0,            -- flags
    0,            -- state
    0,            -- filesystemLastError
    0, 0, 0, 0,   -- freeSizeKB
    0, 0, 0, 0    -- totalSizeKB
  },
}

local function parseU32(b1, b2, b3, b4)
  return (tonumber(b4) or 0) << 24 | (tonumber(b3) or 0) << 16 | (tonumber(b2) or 0) << 8 | (tonumber(b1) or 0)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 11 then return nil end
  return {
    supported = (buf[1] and ((buf[1] & 0x01) ~= 0)) or false,
    state = buf[2] or 0,
    filesystemLastError = buf[3] or 0,
    freeSizeKB = parseU32(buf[4], buf[5], buf[6], buf[7]),
    totalSizeKB = parseU32(buf[8], buf[9], buf[10], buf[11])
  }
end

return Api
