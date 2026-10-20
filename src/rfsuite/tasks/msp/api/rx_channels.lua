-- MSP_RX_CHANNELS: receiver wire order, before the function/channel map.
local Api = { command = 114, simulatorResponse = {220,5,220,5,220,5,220,5,232,3,232,3,220,5,208,7} }
function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 2 or #buf % 2 ~= 0 or #buf > 36 then return nil end
  local values = {}
  for i = 1, #buf, 2 do values[#values + 1] = buf[i] + buf[i + 1] * 256 end
  return { channels = values, channel_count = #values }
end
return Api
