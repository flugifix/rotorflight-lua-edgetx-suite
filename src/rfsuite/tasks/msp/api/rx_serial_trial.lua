local Api = { command = 0x5F12, writeCommand = 0x5F12 }
function Api.parse(b)
  if type(b) ~= "table" or #b < 7 then return nil end
  return { state = b[1], combination = b[2], inverted = b[3], half_duplex = b[4], pin_swap = b[5] }
end
function Api.buildWritePayload(d) return { d.action } end
return Api
