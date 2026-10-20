local Api = { command = 0x5F13, writeCommand = 0x5F13 }
function Api.parse(b)
  if type(b) ~= "table" or #b < 8 then return nil end
  local function s(p) local v = b[p] + b[p + 1] * 256; if v >= 32768 then v = v - 65536 end; return v end
  return { state = b[1], roll = s(2), pitch = s(4), yaw = s(6) }
end
function Api.buildWritePayload(d) return { d.action } end
return Api
