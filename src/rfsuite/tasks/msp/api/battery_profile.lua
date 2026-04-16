-- EdgeTX MSP API: BATTERY_PROFILE
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 175, -- MSP_BATTERY_PROFILE
  writeCommand = 176, -- MSP_SET_BATTERY_PROFILE
  simulatorResponse = { 0 }, -- batteryProfile
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 1 then return nil end
  return {
    batteryProfile = buf[1] or 0
  }
end

function Api.buildWritePayload(data)
  local profile = tonumber(data.batteryProfile) or 0
  return { profile }
end

return Api
