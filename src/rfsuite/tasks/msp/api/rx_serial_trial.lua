local Api = { command = 0x5F12 }
function Api.parse(b)
  if type(b) ~= "table" or #b < 7 then return nil end
  return { state = b[1], comboIndex = b[2], inverted = b[3], half_duplex = b[4], pin_swap = b[5], elapsedMs = b[6] + b[7] * 256 }
end
function Api.buildPayload(action) return { action or 0 } end
return Api
