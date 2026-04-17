-- EdgeTX MSP API: 4WIF_ESC_FWD_PROG (write-only)

local Api = {
  writeCommand = 244
}

function Api.buildWritePayload(data)
  local target = data and data.target
  if target == nil then target = 0 end
  return { tonumber(target) or 0 }
end

return Api
