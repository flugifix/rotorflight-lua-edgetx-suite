local Api = { command = 108, simulatorResponse = {0,0,0,0,0,0} }
function Api.parse(b)
  if type(b) ~= "table" or #b ~= 6 then return nil end
  local function s(p) local v = b[p] + b[p + 1] * 256; if v >= 32768 then v = v - 65536 end; return v end
  return { roll = s(1) / 10, pitch = s(3) / 10, yaw = s(5) }
end
return Api
