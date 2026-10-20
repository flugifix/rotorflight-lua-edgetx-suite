return function(w)
  local L = w.L
  if w:motorised() then
    local rows = {
      { kind = "choice", label = L.bladesRemoved, values = { L.no, L.yes },
        get = function() return w.bladesOff and 2 or 1 end, set = function(v) w.bladesOff = v == 2; if v == 1 then w:stopMotor() end end },
      { kind = "number", label = L.powerPercent, min = 5, max = 50, get = function() return w.percent end,
        set = function(v) w.percent = v end },
      { kind = "hold", label = L.holdForward, press = function() w:spin(1, 1) end, release = function() w:stopMotor() end }
    }
    if w.data.mixer_config.tail_rotor_mode == 2 then
      rows[#rows + 1] = { kind = "hold", label = L.holdReverse, press = function() w:spin(1, -1) end,
        release = function() w:stopMotor() end }
    end
    return {
      w:cardDef(L.tail, L.tailMotorHint, rows, nil, "heli"),
      w:cardDef(L.tailIdle, L.tailIdleHint, {
        w:n("mixer_config", "tail_motor_idle", L.idlePercent, 0, 255, false, true, 10),
        w:button(L.usePower, function() w:field("mixer_config", "tail_motor_idle", math.min(w.percent * 10, 255), false, true) end),
        { kind = "hold", label = L.testIdle, press = function()
          if not w.bladesOff then return end
          w.motorHold = { index = 1, value = w.data.mixer_config.tail_motor_idle, due = 0, untilAt = getTime() + 1500 }
        end, release = function() w:stopMotor() end }
      })
    }
  end
  local function hold(value) w:hold("mixer", 3, value) end
  return {
    w:cardDef(L.tailCentre, L.tailCentreHint, {
      w:n("mixer_config", "tail_center_trim", L.centreTrim, -1042, 1042, false, true),
      w:check("tailCentre", L.tailCentred)
    }, function() hold(0) end, "servo"),
    w:cardDef(L.tailDirection, L.tailDirectionHint, {
      w:value(L.stick, function() return w.data.rc_command and w.data.rc_command.commands[3] or "--" end),
      w:button(L.wrongReverse, function() w:invertInput(3); w.checks.tailDirection = nil end),
      w:check("tailDirection", L.directionCorrect)
    }, function() hold(2502) end),
    w:cardDef(L.tailCalibration, L.tailCalibrationHint, {
      w:button(L.holdPositive22, function() hold(917) end),
      w:button(L.holdNegative22, function() hold(-917) end),
      w:input(3, "rate", L.ratePercent, -5000, 5000, 10)
    }, function() hold(0) end, "pitch"),
    w:cardDef(L.tailLimits, L.tailLimitHint, {
      w:button(L.holdPositive60, function() hold(2500) end),
      w:button(L.holdNegative60, function() hold(-2500) end),
      w:input(3, "min", L.clockwiseLimit, -2500, 0), w:input(3, "max", L.counterclockwiseLimit, 0, 2500)
    }, function() hold(0) end)
  }
end
