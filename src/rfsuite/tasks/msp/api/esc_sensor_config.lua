-- EdgeTX MSP API: ESC_SENSOR_CONFIG
local Api = {
  command = 123,      -- MSP_API_CMD_READ
  writeCommand = 216, -- MSP_API_CMD_WRITE
  simulatorResponse = {
    1,       -- protocol (1 = AM32/BLHeli/Bluejay)
    0,       -- half_duplex
    200, 0,  -- update_hz (U16)
    0, 15,   -- current_offset (U16)
    0, 0,    -- hw4_current_offset (U16)
    0,       -- hw4_current_gain (U8)
    30,      -- hw4_voltage_gain (U8)
    0,       -- pin_swap (U8)
    0,       -- voltage_correction (S8)
    0,       -- current_correction (S8)
    0        -- consumption_correction (S8)
  }
}

local function to_u16(lo, hi)
  lo = tonumber(lo) or 0
  hi = tonumber(hi) or 0
  return ((hi & 0xFF) << 8) | (lo & 0xFF)
end

local function from_u16(v)
  v = tonumber(v) or 0
  v = v & 0xFFFF
  return v & 0xFF, (v >> 8) & 0xFF
end

local function parseS8(b)
  local n = tonumber(b) or 0
  if n >= 128 then n = n - 256 end
  return n
end

local function packS8(v)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = v + 256 end
  return v & 0xFF
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 10 then return nil end
  local out = {
    protocol = tonumber(buf[1]) or 0,
    half_duplex = tonumber(buf[2]) or 0,
    update_hz = to_u16(buf[3], buf[4]),
    current_offset = to_u16(buf[5], buf[6]),
    hw4_current_offset = to_u16(buf[7], buf[8]),
    hw4_current_gain = tonumber(buf[9]) or 0,
    hw4_voltage_gain = tonumber(buf[10]) or 0
  }

  if #buf >= 11 then
    out.pin_swap = tonumber(buf[11]) or 0
  end

  if #buf >= 14 then
    out.voltage_correction = parseS8(buf[12])
    out.current_correction = parseS8(buf[13])
    out.consumption_correction = parseS8(buf[14])
  end

  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  p[1] = (tonumber(data.protocol) or 0) & 0xFF
  p[2] = (tonumber(data.half_duplex) or 0) & 0xFF
  
  local lo, hi = from_u16(data.update_hz or 200)
  p[3] = lo
  p[4] = hi

  lo, hi = from_u16(data.current_offset or 0)
  p[5] = lo
  p[6] = hi

  lo, hi = from_u16(data.hw4_current_offset or 0)
  p[7] = lo
  p[8] = hi

  p[9] = (tonumber(data.hw4_current_gain) or 0) & 0xFF
  p[10] = (tonumber(data.hw4_voltage_gain) or 30) & 0xFF

  if data.pin_swap ~= nil then
    p[11] = (tonumber(data.pin_swap) or 0) & 0xFF
  end

  if data.voltage_correction ~= nil or data.current_correction ~= nil or data.consumption_correction ~= nil then
    -- Make sure we have slot 11 packed even if data.pin_swap is nil
    if #p < 11 then p[11] = 0 end
    p[12] = packS8(data.voltage_correction or 0)
    p[13] = packS8(data.current_correction or 0)
    p[14] = packS8(data.consumption_correction or 0)
  end

  return p
end

return Api
