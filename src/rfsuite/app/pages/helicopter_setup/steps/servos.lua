return function(w)
  local L = w.L
  local cards = {}
  local function holdAll() for _, i in ipairs(w:servos()) do w:hold("servo", i, 0) end end
  for _, servo in ipairs(w:servos()) do
    local index = servo
    local s = w.data.servo_configurations.servos[index]
    local title = L.servo .. " " .. (index + 1)
    if index ~= 3 then
      cards[#cards + 1] = w:cardDef(title, L.servoDirectionHint, {
        w:button(function() return w.holds["servo"..index] and w.holds["servo"..index].value==400 and L.releaseTest or L.testUp end, function() w:toggleHold("servo", index, 400) end),
        w:button(L.reverse, function() s.flags = s.flags ~ 1; w.checks["servoUp"..index]=nil; w:touch("servo_configurations", false, true) end),
        { kind = "choice", label = L.movesUp, values = { L.no, L.yes },
          get = function() return w.checks["servoUp" .. index] and 2 or 1 end,
          set = function(v)
            w.checks["servoUp" .. index] = v == 2
            if v == 2 then w:hold("servo", index, 0) end
          end },
        w:value(L.output, function() return w.data.servo.servos[index + 1] or "--" end)
      }, holdAll, "servoMove")
    end
    local centre = s.mid > 860 and 1520 or 760
    cards[#cards + 1] = w:cardDef(title, L.servoCentreHint, {
      { kind = "number", label = L.centreUs, min = centre - (centre == 760 and 200 or 400),
        max = centre + (centre == 760 and 200 or 400), get = function() return s.mid end,
        set = function(v) s.mid = v; w:touch("servo_configurations", false, true) end },
      w:value(L.centreOffset, function() return math.abs(s.mid - centre) > 100 and L.checkMechanics or L.ready end),
      w:check("servoCentre" .. index, L.armCentred)
    }, holdAll, "servoCentre")
  end
  w.validate = function()
    for _, i in ipairs(w:servos()) do
      if i ~= 3 and not w:ack("servoUp" .. i) then return false end
      if not w:ack("servoCentre" .. i) then return false end
    end; return true
  end
  return cards
end
