-- MSP2_TAIL_MOTOR_OUTPUT: read, or move the tail pin in RAM before save/reboot.
local Api = { command = 0x5F14, writeCommand = 0x5F14, simulatorResponse = {0,0} }
function Api.parse(buf)
  if type(buf) ~= "table" or #buf ~= 2 or buf[1] > 3 or buf[2] > 6 then return nil end
  return { output = buf[1], result = buf[2] }
end
function Api.buildWritePayload(data)
  local action = data and data.action
  if action ~= 0 and action ~= 1 and action ~= 2 then return nil end
  return { action }
end
return Api
