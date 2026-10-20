return function(w)
  local L = w.L
  local initial = w.data.tail_motor_output
  if initial and initial.output ~= (w:motorised() and 1 or 0) and initial.output ~= 3 then
    w.dirty.tail_motor_output = true
  end
  w.commit = function()
    local tail = w.data.tail_motor_output
    local expected = w:motorised() and 1 or 0
    if tail and tail.output ~= expected and tail.output ~= 3 then
      w:write("tail_motor_output", { action = expected + 1 }, function(d)
        if not d or d.result ~= 0 or d.output ~= expected then w:fail("tail_motor_output", d and d.result or "reply")
        else w.data.tail_motor_output = d; w.rebootPending = true end
      end, false, true)
    end
    if w.startTail ~= w.data.mixer_config.tail_rotor_mode then
      w:profileLoop("pid", w.data.status.pid_profile_count, function(d)
        d.governor_tta_gain = w:motorised() and 100 or 0
      end)
      w:run(function() w.startTail = w.data.mixer_config.tail_rotor_mode end)
    end
  end
  local tail = w:c("mixer_config", "tail_rotor_mode", L.tailType, { L.servoTail, L.motorTail, L.bidirectional }, true, true)
  local set = tail.set
  tail.set = function(v)
    local old = w.data.mixer_config.tail_rotor_mode; set(v)
    if old ~= w.data.mixer_config.tail_rotor_mode then
      local input = w.data.mixer_input.inputs[3]
      input.rate = (input.rate < 0 and -1 or 1) * (w:motorised() and 1000 or 250)
      w:touch("mixer_input", false, true)
    end
  end
  return { w:cardDef(L.swash, L.swashHint, {
    w:c("mixer_config", "swash_type", L.swashType, { L.direct, "120", "135", "140", "90L", "90V" }, true, true, 1),
    w:c("mixer_config", "main_rotor_dir", L.rotorDirection, { L.clockwise, L.counterclockwise }, false, true),
    tail,
    w:value(L.tailPin, function()
      local d = w.data.tail_motor_output
      if not d then return L.unsupported end
      return ({ L.servo4, L.motor2, L.both, L.noPin })[d.output + 1]
    end)
  }, nil, "swash") }
end
