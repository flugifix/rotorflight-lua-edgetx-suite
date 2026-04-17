-- EdgeTX MSP API: reboot (write-only)

local Api = {
  writeCommand = 68
}

function Api.buildWritePayload(data)
  local rebootMode = tonumber(data and data.rebootMode) or 0
  return {rebootMode}
end

return Api
