return function(w)
  local L = w.L
  w.commit = function() w:fixMotor() end
  -- Bidirectional DShot is an on/off setting and applies to the DShot protocols only.
  local dshot = w:c("motor_config", "use_dshot_telemetry", L.bidirectionalDshot, { L.off, L.on }, true)
  dshot.enabled = function()
    local p = w.data.motor_config.motor_pwm_protocol
    return p >= 5 and p <= 7
  end
  return {
    w:cardDef(L.motor, L.motorHint, {
      w:enum("motor_config", "motor_pwm_protocol", L.protocol, w:motorProtocols(), true),
      w:n("motor_config", "motor_pole_count_0", L.motorPoles, 2, 255, true),
      dshot,
      w:check("blades", L.bladesRemoved)
    }, nil, "heli"),
    w:cardDef(L.gearing, L.gearingHint, {
      w:n("motor_config", "main_rotor_gear_ratio_0", L.motorPinion, 1, 50000, true),
      w:n("motor_config", "main_rotor_gear_ratio_1", L.mainGear, 1, 50000, true),
      w:value(L.ratio, function()
        local d = w.data.motor_config
        return string.format("%.3f", d.main_rotor_gear_ratio_1 / math.max(1, d.main_rotor_gear_ratio_0))
      end)
    }),
    w:cardDef(L.tailDrive, L.tailDriveHint, w:motorised() and {
      w:n("motor_config", "motor_pole_count_1", L.tailMotorPoles, 2, 255, true)
    } or {
      w:n("motor_config", "tail_rotor_gear_ratio_0", L.tailInputGear, 1, 50000, true),
      w:n("motor_config", "tail_rotor_gear_ratio_1", L.tailOutputGear, 1, 50000, true)
    })
  }
end
