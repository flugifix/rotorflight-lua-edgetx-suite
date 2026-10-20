return function(w)
  local L = w.L
  w.validate = function() return w:ack("finish") end
  return {
    w:cardDef(L.finish, L.finishHint, {
      w:value(L.swashType, function() return w.data.mixer_config.swash_type end),
      w:value(L.rotorDirection, function() return w.data.mixer_config.main_rotor_dir == 0 and L.clockwise or L.counterclockwise end),
      w:value(L.tailType, function() return w:motorised() and L.motorTail or L.servoTail end),
      w:value(L.totalLimit, function() return string.format("%.1f", w.data.mixer_config.swash_pitch_limit * 0.012) end)
    }, nil, "heli"),
    w:cardDef(L.finish, L.finishSafetyHint, {
      w:value(L.escTelemetry, function() return w.data.esc_sensor_config.protocol > 0 and L.on or L.off end),
      w:value(L.governor, function() return w.data.governor_config.gov_mode end),
      w:value(L.fastRpm, function() return w:fastRpm() and L.available or L.rpmMissing end),
      w:check("finish", L.finalCheck)
    })
  }
end
