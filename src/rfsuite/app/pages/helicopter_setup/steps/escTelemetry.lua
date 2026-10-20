return function(w)
  local L = w.L
  local function motor() return w.data.motor_telemetry and w.data.motor_telemetry.motors[1] end
  w.commit = function() w:fixMotor() end
  return {
    w:cardDef(L.escTelemetry, L.telemetryHint, {
      w:c("esc_sensor_config", "protocol", L.protocol,
        { L.off, "BLHeli32", "Hobbywing V4", "Hobbywing V5", "Scorpion", "Kontronik", "OMPHobby", "ZTW", "APD",
          "OpenYGE", "FLYROTOR", "Graupner", "XDFLY", "FrSky F.BUS", "SRXL2" }, true),
      w:port(L.port, 1024),
      w:button(L.detectWiring, function() w:startTrial("esc_sensor_trial") end,
        function() return w.data.esc_sensor_config.protocol > 0 end),
      w:button(L.saveReboot, function() w:reboot() end)
    }),
    w:cardDef(L.telemetryCheck, L.telemetryCheckHint, {
      w:value(L.voltage, function() local m = motor(); return m and string.format("%.2f V", m.voltage / 1000) or "--" end),
      w:value(L.current, function() local m = motor(); return m and string.format("%.2f A", m.current / 1000) or "--" end),
      w:value(L.temperature, function() local m = motor(); return m and string.format("%.1f C", m.temperature / 10) or "--" end),
      w:value(L.rpm, function() local m = motor(); return m and m.rpm or "--" end)
    })
  }
end
