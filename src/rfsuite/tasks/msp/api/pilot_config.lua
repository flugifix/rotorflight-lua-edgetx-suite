-- EdgeTX MSP API: pilot_config (ported from Ethos)

local Api = {
  command = 12,
  writeCommand = 13,
  simulatorResponse = {3, 0, 44, 1, 0, 20, 0, 20, 0, 0, 30}
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
  out.model_id = tonumber(buf[i]); i = i + 1
  out.model_param1_type = tonumber(buf[i]); i = i + 1
  out.model_param1_value = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.model_param2_type = tonumber(buf[i]); i = i + 1
  out.model_param2_value = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.model_param3_type = tonumber(buf[i]); i = i + 1
  out.model_param3_value = u16_from_bytes(buf[i], buf[i+1]); i = i + 2
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  local function push(v) p[#p+1] = v end
  push(data.model_id or 0)
  push(data.model_param1_type or 0)
  local lo, hi = bytes_from_u16(data.model_param1_value or 300)
  push(lo); push(hi)
  push(data.model_param2_type or 0)
  lo, hi = bytes_from_u16(data.model_param2_value or 20)
  push(lo); push(hi)
  push(data.model_param3_type or 0)
  lo, hi = bytes_from_u16(data.model_param3_value or 7680)
  push(lo); push(hi)
  return p
end

return Api
