-- EdgeTX MSP API: BLACKBOX_CONFIG
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 80, -- MSP_BLACKBOX_CONFIG
  writeCommand = 81, -- MSP_SET_BLACKBOX_CONFIG
  simulatorResponse = {
    1,          -- blackbox_supported
    1,          -- device
    1,          -- mode
    8, 0,       -- denom
    127, 238, 7, 0, -- fields
    0, 0,       -- initialEraseFreeSpaceKiB
    0,          -- rollingErase
    5           -- gracePeriod
  },
}

local function parseU16(lo, hi)
  return (tonumber(hi) or 0) << 8 | (tonumber(lo) or 0)
end
local function parseU32(b1, b2, b3, b4)
  return (tonumber(b4) or 0) << 24 | (tonumber(b3) or 0) << 16 | (tonumber(b2) or 0) << 8 | (tonumber(b1) or 0)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 13 then return nil end
  local idx = 1
  local blackbox_supported = buf[idx] or 0
  idx = idx + 1
  local device = buf[idx] or 0
  idx = idx + 1
  local mode = buf[idx] or 0
  idx = idx + 1
  local denom = parseU16(buf[idx], buf[idx+1])
  idx = idx + 2
  local fields = parseU32(buf[idx], buf[idx+1], buf[idx+2], buf[idx+3])
  idx = idx + 4
  local initialEraseFreeSpaceKiB = parseU16(buf[idx], buf[idx+1])
  idx = idx + 2
  local rollingErase = buf[idx] or 0
  idx = idx + 1
  local gracePeriod = buf[idx] or 0
  return {
    blackbox_supported = blackbox_supported,
    device = device,
    mode = mode,
    denom = denom,
    fields = fields,
    initialEraseFreeSpaceKiB = initialEraseFreeSpaceKiB,
    rollingErase = rollingErase,
    gracePeriod = gracePeriod
  }
end

function Api.buildWritePayload(data)
  local function toU16(val)
    val = tonumber(val) or 0
    return val & 0xFF, (val >> 8) & 0xFF
  end
  local function toU32(val)
    val = tonumber(val) or 0
    return val & 0xFF, (val >> 8) & 0xFF, (val >> 16) & 0xFF, (val >> 24) & 0xFF
  end
  local payload = {}
  payload[#payload+1] = tonumber(data.device) or 0
  payload[#payload+1] = tonumber(data.mode) or 0
  local dLo, dHi = toU16(data.denom)
  payload[#payload+1] = dLo
  payload[#payload+1] = dHi
  local f1, f2, f3, f4 = toU32(data.fields)
  payload[#payload+1] = f1
  payload[#payload+1] = f2
  payload[#payload+1] = f3
  payload[#payload+1] = f4
  local eLo, eHi = toU16(data.initialEraseFreeSpaceKiB)
  payload[#payload+1] = eLo
  payload[#payload+1] = eHi
  payload[#payload+1] = tonumber(data.rollingErase) or 0
  payload[#payload+1] = tonumber(data.gracePeriod) or 0
  return payload
end

return Api
