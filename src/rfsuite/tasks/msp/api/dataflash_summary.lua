-- EdgeTX MSP API: DATAFLASH_SUMMARY
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 70, -- MSP_DATAFLASH_SUMMARY
  simulatorResponse = {
    3,             -- flags
    235, 3, 0, 0,  -- sectors
    0, 0, 214, 7,  -- total
    0, 112, 13, 0  -- used
  },
}

local function parseU32(b1, b2, b3, b4)
  return (tonumber(b4) or 0) << 24 | (tonumber(b3) or 0) << 16 | (tonumber(b2) or 0) << 8 | (tonumber(b1) or 0)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 13 then return nil end
  return {
    flags = buf[1] or 0,
    sectors = parseU32(buf[2], buf[3], buf[4], buf[5]),
    total = parseU32(buf[6], buf[7], buf[8], buf[9]),
    used = parseU32(buf[10], buf[11], buf[12], buf[13])
  }
end

return Api
