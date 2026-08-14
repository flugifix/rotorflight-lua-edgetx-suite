-- EdgeTX MSP API: motor_override (ported from Ethos)

local Api = {
  command = 194,
  writeCommand = 195,
  simulatorResponse = {0,0, 0,0, 0,0, 0,0}
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
  if #buf < 8 then return nil end
  local out = {}
  local i = 1
  for idx = 1, 4 do
    out["motor_"..idx] = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  end
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  for idx = 1, 4 do
    local lo, hi = bytes_from_u16(data["motor_"..idx] or 0)
    p[#p+1] = lo; p[#p+1] = hi
  end
  return p
end

return Api
