-- EdgeTX MSP API: SET_MODE_RANGE (write-only)

local Api = {
  writeCommand = 35
}

function Api.buildWritePayload(payloadData)
  local payload = payloadData and payloadData.payload
  if type(payload) ~= "table" then return nil end
  return payload
end

return Api
