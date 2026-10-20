local M = {}
function M.attach(w)
  function w:fastRpm()
    local m = self.data.motor_config
    return m.motor_pole_count_0 > 0 and ((self.data.feature_config.enabledFeatures & (1 << 28)) ~= 0 or
      (m.motor_pwm_protocol >= 5 and m.motor_pwm_protocol <= 8 and m.use_dshot_telemetry ~= 0))
  end
  function w:fixMotor()
    local castle = self.data.motor_config.motor_pwm_protocol == 9
    if castle then self.data.esc_sensor_config.protocol = 0; self:touch("esc_sensor_config") end
    self:feature(27, castle or self.data.esc_sensor_config.protocol > 0)
  end
  function w:motorOutputsOk()
    local m = self.data.motor
    return m and m.motor_1 > 0 and (not self:motorised() or m.motor_2 > 0)
  end
  function w:servoLabels()
    local result = {}; for _, i in ipairs(self:servos()) do result[#result + 1] = self.L.servo .. " " .. (i + 1) end
    return result
  end
  function w:startTrial(api)
    if not self:usable() or self.trial then return end
    self.trial = { api = api, untilAt = getTime() + 6000, due = 0 }
    self:write(api, { action = 1 }, function(d, error)
      if error then self.trial = nil; self.message = self.L.unsupported
      else self:trialReply(d) end
    end, true, true)
  end
  function w:trialReply(d)
    local trial = self.trial; if not trial then return end
    if not d then self.message = self.L.unsupported; self:stopTrial(); return end
    if d.state == 1 then trial.due = getTime() + 20; self.message = self.L.detecting; return end
    if d.state ~= 2 then self.message = self.L.trialFailed .. " " .. tostring(d.state); self:stopTrial(); return end
    if trial.api == "board_auto_align" then
      local a = self.data.board_alignment_config
      a.roll_degrees, a.pitch_degrees, a.yaw_degrees = d.roll, d.pitch, d.yaw
      self:touch("board_alignment_config", true)
    elseif trial.api == "rx_serial_trial" then
      local a = self.data.rx_config
      a.serialrx_inverted, a.halfDuplex, a.pinSwap = d.inverted, d.half_duplex, d.pin_swap
      self:touch("rx_config", true)
    else
      local a = self.data.esc_sensor_config
      a.half_duplex, a.pin_swap = d.half_duplex, d.pin_swap
      self:touch("esc_sensor_config", true)
    end
    self.message = self.L.detected; self:stopTrial()
  end
  function w:stopTrial()
    local trial = self.trial; self.trial = nil
    if trial and trial.api ~= "board_auto_align" and self:allowed() then
      self:write(trial.api, { action = 2 }, nil, true)
    end
  end
  function w:trialTick()
    if not self.trial then return false end
    if getTime() > self.trial.untilAt then self.message = self.L.detectTimeout; self:stopTrial(); return true end
    if getTime() < self.trial.due then return true end
    local api = self.trial.api
    self:read(api, function(d, err)
      if err then self.message = self.L.unsupported; self:stopTrial() else self:trialReply(d) end
    end, true)
    return true
  end
end
return M
