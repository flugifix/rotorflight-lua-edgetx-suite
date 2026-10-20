return function(w)
  local L = w.L
  w.validate = function() return w:ack("level") end
  return {
    w:cardDef(L.level, L.levelHint, {
      w:n("mixer_config", "swash_trim_0", L.servo1Trim, -1000, 1000, false, true, 10),
      w:n("mixer_config", "swash_trim_1", L.servo2Trim, -1000, 1000, false, true, 10),
      w:n("mixer_config", "swash_trim_2", L.servo3Trim, -1000, 1000, false, true, 10),
      w:button(L.reset, function()
        for i = 0, 2 do w:field("mixer_config", "swash_trim_" .. i, 0, false, true) end
      end)
    }, function() w:holdAxes(nil, 0) end, "level"),
    w:cardDef(L.levelCheck, L.levelCheckHint, { w:check("level", L.swashLevel) }, function() w:holdAxes(nil, 0) end, "level")
  }
end
