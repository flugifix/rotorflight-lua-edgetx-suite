-- EdgeTX MSP API: mixer_override (ported from Ethos)
-- Reads all inputs; writes exactly one input, optionally with a proven timeout capability.

local Api = {
  command = 190,
  writeCommand = 191,
  simulatorResponse = (function()
    local t = {}
    for i = 1, 29 do t[#t+1] = 0; t[#t+1] = 0 end
    return t
  end)()
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
  if #buf < 58 then return nil end
  local out = {}
  local i = 1
  for idx = 1, 29 do
    out["override_"..idx] = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  end
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local index = tonumber(data.index)
  if not index or index < 0 or index > 28 then return nil end
  local lo, hi = bytes_from_u16(data.value or 2501)
  local p = { math.floor(index), lo, hi }
  if data.timeout ~= nil then
    lo, hi = bytes_from_u16(math.max(500, math.min(30000, data.timeout)))
    p[4], p[5] = lo, hi
  end
  return p
end

return Api
