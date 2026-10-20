return function(w)
  local L = w.L
  local acc = (w.data.status.sensor_status & 1) ~= 0
  w.validate = function() return w:ack("orientation") end
  return {
    w:cardDef(L.sensors, L.prepare, {
      w:check("unplugged", L.servosUnplugged), w:check("blades", L.bladesRemoved),
      w:button(L.calibrate, function()
        if not acc or not w.checks.unplugged or not w.checks.blades then w.message = L.confirmCheck; return end
        w:write("acc_calibration", {}, function() w.message = L.calibrating; w.calibrationAt = getTime() end)
      end, function() return acc and not w.calibrationAt end),
      w:value(L.accelerometer, function() return acc and L.available or L.unavailable end)
    }, nil, "heli"),
    w:cardDef(L.orientation, L.alignHint, {
      w:button(L.autoAlign, function() w:startTrial("board_auto_align") end, function() return acc end),
      w:n("board_alignment_config", "roll_degrees", L.roll, -180, 180, true),
      w:n("board_alignment_config", "pitch_degrees", L.pitch, -180, 180, true),
      w:n("board_alignment_config", "yaw_degrees", L.yaw, -180, 180, true)
    }, nil, "heliLift"),
    w:cardDef(L.checkOrientation, L.orientationHint, {
      w:value(L.roll, function() return (w.data.attitude or {}).roll or "--" end),
      w:value(L.pitch, function() return (w.data.attitude or {}).pitch or "--" end),
      w:check("orientation", L.directionCorrect)
    }, nil, "board")
  }
end
