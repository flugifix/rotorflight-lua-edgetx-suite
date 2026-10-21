-- EdgeTX MSP API: MSP2_ESC_SENSOR_TRIAL (Rotorflight MSP API 12.0.10+)
local Api = {
  command = 0x5F0C,
  ACTION_POLL = 0,
  ACTION_START = 1,
  ACTION_CANCEL = 2
}

local function u16(lo, hi)
  return ((tonumber(hi) or 0) & 0xFF) << 8 | ((tonumber(lo) or 0) & 0xFF)
end

function Api.buildPayload(action)
  return { (tonumber(action) or 0) & 0xFF }
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 6 then return nil end
  local out = {
    state = tonumber(buf[1]) or 0,
    comboIndex = tonumber(buf[2]) or 0,
    half_duplex = tonumber(buf[3]) or 0,
    pin_swap = tonumber(buf[4]) or 0,
    elapsedMs = u16(buf[5], buf[6])
  }
  if #buf >= 8 then out.frameDelta = u16(buf[7], buf[8]) end
  if #buf >= 9 then out.comboCount = tonumber(buf[9]) or 0 end
  if #buf >= 10 then out.portOpen = tonumber(buf[10]) or 0 end
  return out
end

return Api
