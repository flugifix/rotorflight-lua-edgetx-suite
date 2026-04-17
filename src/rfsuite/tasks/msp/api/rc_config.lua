-- EdgeTX MSP API: rc_config (ported from Ethos)

local Api = {
  command = 66,
  writeCommand = 67,
  simulatorResponse = {
    220, 5, -- rc_center (1500)
    254, 1, -- rc_deflection (510)
    232, 3, -- rc_arm_throttle (1000)
    242, 3, -- rc_min_throttle (1100)
    208, 7, -- rc_max_throttle (1900)
    4,      -- rc_deadband
    4       -- rc_yaw_deadband
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
  if #buf < 7 then return nil end
  local i = 1
  local out = {}
  out.rc_center = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rc_deflection = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rc_arm_throttle = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rc_min_throttle = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rc_max_throttle = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.rc_deadband = tonumber(buf[i]); i = i + 1
  out.rc_yaw_deadband = tonumber(buf[i]); i = i + 1
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  local function push(v) p[#p+1] = v end
  local lo, hi = bytes_from_u16(data.rc_center or 1500); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rc_deflection or 510); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rc_arm_throttle or 1000); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rc_min_throttle or 1100); push(lo); push(hi)
  lo, hi = bytes_from_u16(data.rc_max_throttle or 1900); push(lo); push(hi)
  push(data.rc_deadband or 4)
  push(data.rc_yaw_deadband or 4)
  return p
end

return Api
