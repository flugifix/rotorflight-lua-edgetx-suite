return function(w)
  local L = w.L
  w.commit = function() w:fixMotor() end
  -- Bidirectional DShot is an on/off setting and applies to the DShot protocols that send RPM
  -- (not DSHOT150).
  local dshot = w:c("motor_config", "use_dshot_telemetry", L.bidirectionalDshot, { L.off, L.on }, true)
  dshot.enabled = function() return w:bidirDshot(w.data.motor_config.motor_pwm_protocol) end
  local setDshot = dshot.set
  dshot.set = function(v)
    if v == 2 and not dshot.enabled() then return end
    setDshot(v)
  end
  -- PWM, DSHOT150 and DSHOT300 lead the list. Everything else, DSHOT600 included (it is
  -- sensitive to noise on long ESC leads), follows under Other, so the current protocol is
  -- always shown and still selectable.
  local entries, quick, rest = {}, { [0] = 1, [5] = 2, [6] = 3 }, {}
  for _, e in ipairs(w:motorProtocols()) do
    if quick[e[1]] then entries[quick[e[1]]] = e
    else rest[#rest + 1] = { e[1], string.format(L.otherProtocol, e[2]) } end
  end
  for _, e in ipairs(rest) do entries[#entries + 1] = e end
  local protocol = w:enum("motor_config", "motor_pwm_protocol", L.protocol, entries, true)
  local setProtocol = protocol.set
  protocol.set = function(v)
    setProtocol(v)
    -- DSHOT150 has no bidirectional DShot, and an ESC that does not answer the request may
    -- not arm: turn it off in the same motor_config write.
    if entries[v] and entries[v][1] == 5 and w.data.motor_config.motor_pwm_protocol == 5 then
      w:field("motor_config", "use_dshot_telemetry", 0, true)
    end
  end
  local cards = {
    w:cardDef(L.throttleProtocol, L.motorHint, {
      protocol,
      dshot,
      w:check("blades", L.bladesRemoved)
    }, nil, "heliBladesOff"),
    w:cardDef(L.motorGearing, L.motorGearingHint, {
      w:n("motor_config", "motor_pole_count_0", L.motorPoles, 2, 255, true),
      w:n("motor_config", "main_rotor_gear_ratio_0", L.motorPinion, 1, 50000, true),
      w:n("motor_config", "main_rotor_gear_ratio_1", L.mainGear, 1, 50000, true),
      w:value(L.ratio, function()
        local d = w.data.motor_config
        return string.format("%.3f", d.main_rotor_gear_ratio_1 / math.max(1, d.main_rotor_gear_ratio_0))
      end)
    }, nil, "motorGears"),
    w:cardDef(L.motorGearingTail, L.tailDriveHint, w:motorised() and {
      w:n("motor_config", "motor_pole_count_1", L.tailMotorPoles, 2, 255, true)
    } or {
      w:n("motor_config", "tail_rotor_gear_ratio_0", L.tailInputGear, 1, 50000, true),
      w:n("motor_config", "tail_rotor_gear_ratio_1", L.tailOutputGear, 1, 50000, true)
    })
  }
  -- A new ESC is set up first in the Suite's ESC Tools; with a host that can open pages, one press.
  if type(w.openPage) == "function" then
    table.insert(cards[1].rows, w:button(L.openEscTools, function() w:openSuitePage("esc_tools_menu") end))
  end
  local function dshot150() return w.data.motor_config.motor_pwm_protocol == 5 end
  cards[1].summary=function() return dshot150() and L.dshot150NoRpm or L.motorQuick end
  cards[1].summaryColor=function() return dshot150() and "warning" or nil end
  cards[2].summary=L.motorGearingShort
  return cards
end
