local Api = { command = 0x5F0C, writeCommand = 0x5F0C }
function Api.parse(b)
  if type(b) ~= "table" or #b < 6 then return nil end
  return { state = b[1], combination = b[2], half_duplex = b[3], pin_swap = b[4] }
end
function Api.buildWritePayload(d) return { d.action } end
return Api
