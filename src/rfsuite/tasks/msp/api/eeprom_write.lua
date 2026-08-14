-- EdgeTX MSP API: EEPROM_WRITE
-- Ported to EdgeTX schema (Api table + buildWritePayload)

local Api = {
  command = 250, -- MSP_EEPROM_WRITE
  writeCommand = 250, -- MSP_EEPROM_WRITE
}

function Api.buildWritePayload(_)
  return {}
end

return Api
