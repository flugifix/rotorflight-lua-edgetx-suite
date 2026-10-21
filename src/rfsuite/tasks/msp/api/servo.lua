-- EdgeTX MSP API: SERVO (MSP_SERVO, 103, read only)
--
-- One U16 live output pulse per servo, in microseconds, in the order MSP_SERVO_CONFIGURATIONS
-- lists the servos: with bus servos configured, the configured PWM servos and then every bus
-- servo. servos[1] is the servo that MSP_SERVO_CONFIGURATIONS reports at index 0.

local Api = { command = 103, simulatorResponse = { 240, 5, 240, 5, 240, 5, 240, 5 } }

function Api.parse(buf)
  if type(buf) ~= "table" or #buf == 0 or #buf % 2 ~= 0 or #buf > 64 then return nil end
  local values = {}
  for i = 1, #buf, 2 do values[#values + 1] = buf[i] + buf[i + 1] * 256 end
  return { servos = values, servo_count = #values }
end

return Api
