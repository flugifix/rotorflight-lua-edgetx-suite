-- EdgeTX MSP API: gps_config (ported from Ethos)

local Api = {
  command = 132,
  writeCommand = 223,
  simulatorResponse = {0, 0, 1, 1, 0, 0}
}

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  if #buf < 4 then return nil end
  local i = 1
  local out = {}
  out.provider = tonumber(buf[i]); i = i + 1
  out.sbas_mode = tonumber(buf[i]); i = i + 1
  out.auto_config = tonumber(buf[i]); i = i + 1
  out.auto_baud = tonumber(buf[i]); i = i + 1
  if buf[i] then out.set_home_point_once = tonumber(buf[i]); i = i + 1 end
  if buf[i] then out.ublox_use_galileo = tonumber(buf[i]); i = i + 1 end
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  local function push(v) p[#p+1] = v end
  push(data.provider or 0)
  push(data.sbas_mode or 0)
  push(data.auto_config or 1)
  push(data.auto_baud or 1)
  push(data.set_home_point_once or 0)
  push(data.ublox_use_galileo or 0)
  return p
end

return Api
