return function(w)
  local L = w.L
  w.commit = function() w:fixMotor() end
  return {
    w:cardDef(L.motor, L.motorHint, {
      w:c("motor_config", "motor_pwm_protocol", L.protocol,
        { "PWM", "ONESHOT125", "ONESHOT42", "MULTISHOT", L.unknown, "DSHOT150", "DSHOT300", "DSHOT600", "PROSHOT", "CASTLE", "SRXL2", L.off }, true),
      w:n("motor_config", "motor_pole_count_0", L.motorPoles, 2, 100, true),
      w:n("motor_config", "use_dshot_telemetry", L.bidirectionalDshot, 0, 1, true),
      w:check("blades", L.bladesRemoved)
    }, nil, "heli"),
    w:cardDef(L.gearing, L.gearingHint, {
      w:n("motor_config", "main_rotor_gear_ratio_0", L.motorPinion, 1, 65535, true),
      w:n("motor_config", "main_rotor_gear_ratio_1", L.mainGear, 1, 65535, true),
      w:value(L.ratio, function()
        local d = w.data.motor_config
        return string.format("%.3f", d.main_rotor_gear_ratio_1 / math.max(1, d.main_rotor_gear_ratio_0))
      end)
    }),
    w:cardDef(L.tailDrive, L.tailDriveHint, w:motorised() and {
      w:n("motor_config", "motor_pole_count_1", L.tailMotorPoles, 2, 100, true)
    } or {
      w:n("motor_config", "tail_rotor_gear_ratio_0", L.tailInputGear, 1, 65535, true),
      w:n("motor_config", "tail_rotor_gear_ratio_1", L.tailOutputGear, 1, 65535, true)
    })
  }
end
