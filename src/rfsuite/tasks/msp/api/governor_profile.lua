-- EdgeTX MSP API: governor_profile (ported from Ethos)

local Api = {
  command = 148,
  writeCommand = 149,
  simulatorResponse = {
    -- Rotorflight Ethos >=12.0.9 layout
    208, 7, -- governor_headspeed (2000)
    100,    -- governor_gain
    10,     -- governor_p_gain
    125,    -- governor_i_gain
    5,      -- governor_d_gain
    20,     -- governor_f_gain
    0,      -- governor_tta_gain
    20,     -- governor_tta_limit
    10,     -- governor_yaw_weight
    40,     -- governor_cyclic_weight
    100,    -- governor_collective_weight
    100,    -- governor_max_throttle
    10,     -- governor_min_throttle
    10,     -- governor_fallback_drop
    251, 3  -- governor_flags (U16)
  }
}

local function to_u16(lo, hi)
  lo = tonumber(lo) or 0
  hi = tonumber(hi) or 0
  return ((hi & 0xFF) << 8) | (lo & 0xFF)
end

local function from_u16(v)
  v = math.floor(tonumber(v) or 0) & 0xFFFF
  return v & 0xFF, (v >> 8) & 0xFF
end

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local n = #buf
  local i = 1
  local out = {}

  if n >= 17 then
    out.governor_headspeed = to_u16(buf[i], buf[i+1]); i = i + 2
    out.governor_gain = tonumber(buf[i]); i = i + 1
    out.governor_p_gain = tonumber(buf[i]); i = i + 1
    out.governor_i_gain = tonumber(buf[i]); i = i + 1
    out.governor_d_gain = tonumber(buf[i]); i = i + 1
    out.governor_f_gain = tonumber(buf[i]); i = i + 1
    out.governor_tta_gain = tonumber(buf[i]); i = i + 1
    out.governor_tta_limit = tonumber(buf[i]); i = i + 1
    out.governor_yaw_weight = tonumber(buf[i]); i = i + 1
    out.governor_cyclic_weight = tonumber(buf[i]); i = i + 1
    out.governor_collective_weight = tonumber(buf[i]); i = i + 1
    out.governor_max_throttle = tonumber(buf[i]); i = i + 1
    out.governor_min_throttle = tonumber(buf[i]); i = i + 1
    out.governor_fallback_drop = tonumber(buf[i]); i = i + 1
    out.governor_flags = to_u16(buf[i], buf[i+1]); i = i + 2

  elseif n >= 13 then
    -- older layout
    out.governor_headspeed = to_u16(buf[i], buf[i+1]); i = i + 2
    out.governor_gain = tonumber(buf[i]); i = i + 1
    out.governor_p_gain = tonumber(buf[i]); i = i + 1
    out.governor_i_gain = tonumber(buf[i]); i = i + 1
    out.governor_d_gain = tonumber(buf[i]); i = i + 1
    out.governor_f_gain = tonumber(buf[i]); i = i + 1
    out.governor_tta_gain = tonumber(buf[i]); i = i + 1
    out.governor_tta_limit = tonumber(buf[i]); i = i + 1
    out.governor_yaw_ff_weight = tonumber(buf[i]); i = i + 1
    out.governor_cyclic_ff_weight = tonumber(buf[i]); i = i + 1
    out.governor_collective_ff_weight = tonumber(buf[i]); i = i + 1
    out.governor_max_throttle = tonumber(buf[i]); i = i + 1
    out.governor_min_throttle = tonumber(buf[i]); i = i + 1
  else
    return nil
  end

  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  local function push(v) p[#p+1] = v end

  -- build >=12.0.9 layout by default
  local lo, hi = from_u16(data.governor_headspeed or 2000)
  push(lo); push(hi)
  push(data.governor_gain or 100)
  push(data.governor_p_gain or 10)
  push(data.governor_i_gain or 125)
  push(data.governor_d_gain or 5)
  push(data.governor_f_gain or 20)
  push(data.governor_tta_gain or 0)
  push(data.governor_tta_limit or 20)
  push(data.governor_yaw_weight or 10)
  push(data.governor_cyclic_weight or 40)
  push(data.governor_collective_weight or 100)
  push(data.governor_max_throttle or 100)
  push(data.governor_min_throttle or 10)
  push(data.governor_fallback_drop or 10)
  lo, hi = from_u16(data.governor_flags or 1019)
  push(lo); push(hi)

  return p
end

return Api
