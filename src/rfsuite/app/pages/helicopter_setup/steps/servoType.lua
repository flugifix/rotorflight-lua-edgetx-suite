return function(w)
  local L = w.L
  local function apply(tail, kind)
    if not w.checks.unplugged then w.message = L.confirmCheck; return end
    local rate = ({50,333,560})[kind]
    for _, index in ipairs(w:servos()) do
      if (index == 3) == tail then
        local servo = w.data.servo_configurations.servos[index]
        local narrow = kind == 3
        if (servo.mid <= 860) ~= narrow then
          servo.mid, servo.min, servo.max = narrow and 760 or 1520, narrow and -250 or -700, narrow and 250 or 700
          servo.rneg, servo.rpos = narrow and 250 or 500, narrow and 250 or 500
        end
        if servo.rate ~= rate then w.rebootPending = true end
        servo.rate = rate
      end
    end
    w:touch("servo_configurations", false, true)
  end
  local function current(tail)
    local result
    for _, index in ipairs(w:servos()) do
      if (index == 3) == tail then
        local s = w.data.servo_configurations.servos[index]
        local kind = s.rate == 50 and s.mid > 860 and 1 or s.rate == 333 and s.mid > 860 and 2 or
          s.rate == 560 and s.mid <= 860 and 3 or 0
        if result and result ~= kind then return 0 end
        result = kind
      end
    end
    return result or 0
  end
  local function row(tail, label)
    return { kind = "choice", label = label, values = { L.analog, L.digital, L.narrow },
      get = function() return current(tail) end, set = function(v) apply(tail, v) end }
  end
  local rows = { w:check("unplugged", L.servosUnplugged), row(false, L.cyclicServos) }
  if not w:motorised() then rows[#rows + 1] = row(true, L.tailServo) end
  return { w:cardDef(L.servoType, L.servoTypeHint, rows, nil, "servo") }
end
