-- MSP_RC_COMMAND: signed roll, pitch, yaw, collective and throttle commands.
local Api = { command = 113, simulatorResponse = {0,0,0,0,0,0,0,0,0,0} }
function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 10 or #buf % 2 ~= 0 or #buf > 36 then return nil end
  local values = {}
  for i = 1, #buf, 2 do
    local v = buf[i] + buf[i + 1] * 256
    if v >= 32768 then v = v - 65536 end
    values[#values + 1] = v
  end
  return { commands = values }
end
return Api
