-- EdgeTX MSP API: DEBUG_CONFIG
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 59, -- MSP_DEBUG_CONFIG
  writeCommand = 60, -- MSP_SET_DEBUG_CONFIG
  simulatorResponse = {
    8,  -- debug_count
    8,  -- debug_value_count
    0,  -- debug_mode
    0   -- debug_axis
  },
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 4 then return nil end
  return {
    debug_count = buf[1] or 0,
    debug_value_count = buf[2] or 0,
    debug_mode = buf[3] or 0,
    debug_axis = buf[4] or 0
  }
end

function Api.buildWritePayload(data)
  local debug_mode = tonumber(data.debug_mode) or 0
  local debug_axis = tonumber(data.debug_axis) or 0
  return { debug_mode, debug_axis }
end

return Api
