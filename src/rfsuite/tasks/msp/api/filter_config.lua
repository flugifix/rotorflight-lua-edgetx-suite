-- EdgeTX MSP API: FILTER_CONFIG (ported from Ethos)
-- Self-contained, no core/Ethos dependencies

local Api = {
  command = 92, -- MSP_API_CMD_READ
  writeCommand = 93, -- MSP_API_CMD_WRITE
  simulatorResponse = {
    0,       -- gyro_hardware_lpf
    1,       -- gyro_lpf1_type
    100, 0,  -- gyro_lpf1_static_hz
    0,       -- gyro_lpf2_type
    0, 0,    -- gyro_lpf2_static_hz
    0, 0,    -- gyro_soft_notch_hz_1
    0, 0,    -- gyro_soft_notch_cutoff_1
    0, 0,    -- gyro_soft_notch_hz_2
    0, 0,    -- gyro_soft_notch_cutoff_2
    0, 0,    -- gyro_lpf1_dyn_min_hz
    25, 0,   -- gyro_lpf1_dyn_max_hz
    0,       -- dyn_notch_count
    100,     -- dyn_notch_q
    0, 0,    -- dyn_notch_min_hz
    0, 0,    -- dyn_notch_max_hz
    1,       -- rpm_preset
    20       -- rpm_min_hz
  }
}

local function parseU8(val) return tonumber(val) or 0 end
local function parseU16(lo, hi) return (tonumber(hi) or 0) << 8 | (tonumber(lo) or 0) end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 27 then return nil end
  local idx = 1
  local function nextU8() local v = parseU8(buf[idx]); idx = idx + 1; return v end
  local function nextU16() local lo = buf[idx]; local hi = buf[idx+1]; idx = idx + 2; return parseU16(lo, hi) end
  return {
    gyro_hardware_lpf = nextU8(),
    gyro_lpf1_type = nextU8(),
    gyro_lpf1_static_hz = nextU16(),
    gyro_lpf2_type = nextU8(),
    gyro_lpf2_static_hz = nextU16(),
    gyro_soft_notch_hz_1 = nextU16(),
    gyro_soft_notch_cutoff_1 = nextU16(),
    gyro_soft_notch_hz_2 = nextU16(),
    gyro_soft_notch_cutoff_2 = nextU16(),
    gyro_lpf1_dyn_min_hz = nextU16(),
    gyro_lpf1_dyn_max_hz = nextU16(),
    dyn_notch_count = nextU8(),
    dyn_notch_q = nextU8(),
    dyn_notch_min_hz = nextU16(),
    dyn_notch_max_hz = nextU16(),
    rpm_preset = nextU8(),
    rpm_min_hz = nextU8()
  }
end

function Api.buildWritePayload(data)
  local function toU8(val) return math.floor(tonumber(val) or 0) & 0xFF end
  local function toU16(val) val = math.floor(tonumber(val) or 0); return val & 0xFF, (val >> 8) & 0xFF end
  local payload = {}
  payload[#payload+1] = toU8(data.gyro_hardware_lpf)
  payload[#payload+1] = toU8(data.gyro_lpf1_type)
  local lo, hi = toU16(data.gyro_lpf1_static_hz); payload[#payload+1] = lo; payload[#payload+1] = hi
  payload[#payload+1] = toU8(data.gyro_lpf2_type)
  lo, hi = toU16(data.gyro_lpf2_static_hz); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.gyro_soft_notch_hz_1); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.gyro_soft_notch_cutoff_1); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.gyro_soft_notch_hz_2); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.gyro_soft_notch_cutoff_2); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.gyro_lpf1_dyn_min_hz); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.gyro_lpf1_dyn_max_hz); payload[#payload+1] = lo; payload[#payload+1] = hi
  payload[#payload+1] = toU8(data.dyn_notch_count)
  payload[#payload+1] = toU8(data.dyn_notch_q)
  lo, hi = toU16(data.dyn_notch_min_hz); payload[#payload+1] = lo; payload[#payload+1] = hi
  lo, hi = toU16(data.dyn_notch_max_hz); payload[#payload+1] = lo; payload[#payload+1] = hi
  payload[#payload+1] = toU8(data.rpm_preset)
  payload[#payload+1] = toU8(data.rpm_min_hz)
  return payload
end

return Api
