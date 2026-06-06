-- EdgeTX MSP API: RAW_IMU (ported)
local Api = {
  command = 102,
  simulatorResponse = {
    0x00, 0x00, -- ax
    0x00, 0x00, -- ay
    0x10, 0x27, -- az (1.0g approx)
    0x00, 0x00, -- gx
    0x00, 0x00, -- gy
    0x00, 0x00, -- gz
    0x00, 0x00, -- mx
    0x00, 0x00, -- my
    0x00, 0x00  -- mz
  }
}

local function s16le(buf, pos)
  local lo = tonumber(buf[pos]) or 0
  local hi = tonumber(buf[pos+1]) or 0
  if hi >= 128 then
    return (lo + hi * 256) - 65536
  else
    return lo + hi * 256
  end
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 12 then return nil end
  return {
    ax = s16le(buf, 1),
    ay = s16le(buf, 3),
    az = s16le(buf, 5),
    gx = s16le(buf, 7),
    gy = s16le(buf, 9),
    gz = s16le(buf, 11),
    mx = #buf >= 18 and s16le(buf, 13) or nil,
    my = #buf >= 18 and s16le(buf, 15) or nil,
    mz = #buf >= 18 and s16le(buf, 17) or nil
  }
end

return Api
