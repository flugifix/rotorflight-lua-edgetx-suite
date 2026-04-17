-- EdgeTX MSP API: rescue_profile (ported from Ethos)

local Api = {
  command = 146,
  writeCommand = 147,
  simulatorResponse = {
    1,        -- rescue_mode
    0,        -- rescue_flip_mode
    200,      -- rescue_flip_gain
    100,      -- rescue_level_gain
    5,        -- rescue_pull_up_time
    3,        -- rescue_climb_time
    10,       -- rescue_flip_time
    5,        -- rescue_exit_time
    182, 3,   -- rescue_pull_up_collective
    188, 2,   -- rescue_climb_collective
    194, 1,   -- rescue_hover_collective
    244, 1,   -- rescue_hover_altitude
    20, 0,    -- rescue_alt_p_gain
    20, 0,    -- rescue_alt_i_gain
    10, 0,    -- rescue_alt_d_gain
    232, 3,   -- rescue_max_collective
    44, 1,    -- rescue_max_setpoint_rate
    184, 11   -- rescue_max_setpoint_accel
  }
}

local function u16_from_bytes(lo, hi)
  lo = tonumber(lo) or 0
  hi = tonumber(hi) or 0
  return ((hi & 0xFF) << 8) | (lo & 0xFF)
end

local function bytes_from_u16(v)
  v = math.floor(tonumber(v) or 0) & 0xFFFF
  return v & 0xFF, (v >> 8) & 0xFF
end

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local i = 1
  local out = {}
  out.rescue_mode = tonumber(buf[i]); i = i + 1
  out.rescue_flip_mode = tonumber(buf[i]); i = i + 1
  out.rescue_flip_gain = tonumber(buf[i]); i = i + 1
  out.rescue_level_gain = tonumber(buf[i]); i = i + 1
  out.rescue_pull_up_time = tonumber(buf[i]); i = i + 1
  out.rescue_climb_time = tonumber(buf[i]); i = i + 1
  out.rescue_flip_time = tonumber(buf[i]); i = i + 1
  out.rescue_exit_time = tonumber(buf[i]); i = i + 1
  out.rescue_pull_up_collective = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_climb_collective = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_hover_collective = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_hover_altitude = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_alt_p_gain = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_alt_i_gain = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_alt_d_gain = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_max_collective = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_max_setpoint_rate = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rescue_max_setpoint_accel = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  local function push(v) p[#p+1] = v end
  push(data.rescue_mode or 0)
  push(data.rescue_flip_mode or 0)
  push(data.rescue_flip_gain or 200)
  push(data.rescue_level_gain or 100)
  push(data.rescue_pull_up_time or 5)
  push(data.rescue_climb_time or 3)
  push(data.rescue_flip_time or 10)
  push(data.rescue_exit_time or 5)
  local lo, hi = bytes_from_u16(data.rescue_pull_up_collective or 966); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_climb_collective or 556); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_hover_collective or 450); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_hover_altitude or 500); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_alt_p_gain or 20); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_alt_i_gain or 20); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_alt_d_gain or 10); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_max_collective or 1000); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_max_setpoint_rate or 300); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rescue_max_setpoint_accel or 3000); push(lo); push(hi)
  return p
end

return Api
