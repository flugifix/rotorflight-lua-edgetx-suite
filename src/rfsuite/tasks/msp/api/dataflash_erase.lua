-- EdgeTX MSP API: DATAFLASH_ERASE
-- Ported to EdgeTX schema (Api table + buildWritePayload)

local Api = {
  writeCommand = 72, -- MSP_DATAFLASH_ERASE
  simulatorResponse = {},
}

function Api.buildWritePayload(_)
  return {}
end

return Api