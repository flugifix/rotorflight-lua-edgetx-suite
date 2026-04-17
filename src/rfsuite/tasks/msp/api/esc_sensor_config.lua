-- EdgeTX MSP API: ESC_SENSOR_CONFIG (ported from Ethos)
-- Self-contained, no core/Ethos dependencies

local Api = {
  command = 123, -- MSP_API_CMD_READ
  writeCommand = 216, -- MSP_API_CMD_WRITE
  simulatorResponse = {
    0,       -- protocol
    0,       -- half_duplex
    200, 0,  -- update_hz (U16)
    0, 15,   -- current_offset (U16)
    0, 0,    -- hw4_current_offset (U16)
    0,       -- hw4_current_gain
    30,      -- hw4_voltage_gain
    0,       -- pin_swap
    0,       -- voltage_correction
    0,       -- current_correction
    0        -- consumption_correction
  }
}

local function parseU8(val) return tonumber(val) or 0 end
local function parseU16(lo, hi) return (tonumber(hi) or 0) << 8 | (tonumber(lo) or 0) end
local function parseS8(val) val = tonumber(val) or 0; if val > 127 then return val - 256 else return val end end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 7 then return nil end
  local idx = 1
  local function nextU8() local v = parseU8(buf[idx]); idx = idx + 1; return v end
  local function nextU16() local lo = buf[idx]; local hi = buf[idx+1]; idx = idx + 2; return parseU16(lo, hi) end
  local out = {
    protocol = nextU8(),
    half_duplex = nextU8(),
    update_hz = nextU16(),
    current_offset = nextU16(),
    hw4_current_offset = nextU16(),
    hw4_current_gain = nextU8(),
    hw4_voltage_gain = nextU8()
  }
  -- Optional fields (if present)
  if idx <= #buf then out.pin_swap = nextU8() end
  if idx <= #buf then out.voltage_correction = parseS8(buf[idx]); idx = idx + 1 end
  if idx <= #buf then out.current_correction = parseS8(buf[idx]); idx = idx + 1 end
  if idx <= #buf then out.consumption_correction = parseS8(buf[idx]); idx = idx + 1 end
  return out
end

function Api.buildWritePayload(data)
  local function toU8(val) return math.floor(tonumber(val) or 0) & 0xFF end
  local function toU16(val) val = math.floor(tonumber(val) or 0); return val & 0xFF, (val >> 8) & 0xFF end
  local function toS8(val) val = math.floor(tonumber(val) or 0); if val < 0 then val = 256 + val end; return val & 0xFF end
  local payload = {}
  payload[#payload+1] = toU8(data.protocol)
  payload[#payload+1] = toU8(data.half_duplex)
  local lo, hi = toU16(data.update_hz); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.current_offset); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.hw4_current_offset); payload[#payload+1] = lo; payload[#payload+1] = hi
  payload[#payload+1] = toU8(data.hw4_current_gain)
  payload[#payload+1] = toU8(data.hw4_voltage_gain)
  if data.pin_swap ~= nil then payload[#payload+1] = toU8(data.pin_swap) end
  if data.voltage_correction ~= nil then payload[#payload+1] = toS8(data.voltage_correction) end
  if data.current_correction ~= nil then payload[#payload+1] = toS8(data.current_correction) end
  if data.consumption_correction ~= nil then payload[#payload+1] = toS8(data.consumption_correction) end
  return payload
end

return Api
