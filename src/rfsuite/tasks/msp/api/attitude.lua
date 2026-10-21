-- EdgeTX MSP API: ATTITUDE (MSP_ATTITUDE, 108, read only)
--
-- Three 16-bit values that do not share a unit: roll and pitch in tenths of a degree, yaw in
-- whole degrees. The firmware holds them signed and writes them unsigned, so each is converted
-- back. The parsed roll and pitch are in degrees.

local Api = { command = 108, simulatorResponse = { 0, 0, 0, 0, 0, 0 } }

local function s16(buf, pos)
  local v = buf[pos] + buf[pos + 1] * 256
  if v >= 32768 then v = v - 65536 end
  return v
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf ~= 6 then return nil end
  return { roll = s16(buf, 1) / 10, pitch = s16(buf, 3) / 10, yaw = s16(buf, 5) }
end

return Api
