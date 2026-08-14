-- EdgeTX MSP API: SELECT_SETTING (210) - Ported
local Api = {
  command = 210,
  writeCommand = 210,
  simulatorResponse = {}
}

function Api.buildWritePayload(value)
  -- Payload is usually a single byte.
  -- Rotorflight supports combined profile selection: (rateIndex << 4) | pidIndex
  return { tonumber(value) or 0 }
end

return Api
