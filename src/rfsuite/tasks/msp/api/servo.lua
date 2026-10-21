-- MSP_SERVO: live PWM output pulses, in microseconds.
local Api = { command = 103, simulatorResponse = {240,5,240,5,240,5,240,5} }
function Api.parse(buf)
  if type(buf) ~= "table" or #buf == 0 or #buf % 2 ~= 0 or #buf > 64 then return nil end
  local values = {}
  for i = 1, #buf, 2 do values[#values + 1] = buf[i] + buf[i + 1] * 256 end
  return { servos = values, servo_count = #values }
end
return Api
