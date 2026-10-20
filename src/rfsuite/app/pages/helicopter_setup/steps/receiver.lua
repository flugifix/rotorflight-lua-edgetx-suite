return function(w)
  local L, H = w.L, w.math
  w.commit = function()
    if w.dirty.serial_config or w.dirty.rx_config then w:feature(3, true) end
  end
  w.rx = w.rx or { low = 3000, high = 0 }
  local r = w.rx
  local keys = { "aileron", "elevator", "rudder", "collective", "throttle", "aux1", "aux2", "aux3" }
  local order = { 4, 1, 2, 3, 5 }
  local names = { L.roll, L.pitch, L.yaw, L.collective, L.throttle }
  local function detect()
    r.detect = { index = 1, found = {}, exclude = {}, peaks = {}, baseline = nil }
    w.message = L.move .. " " .. names[order[1]]
  end
  w.onLive = function(api, d)
    if api ~= "rx_channels" then return end
    local map = w.data.rx_map
    local throttle = d.channels[(map.throttle or 4) + 1]
    if r.record and throttle and throttle > 500 then r.low, r.high = math.min(r.low, throttle), math.max(r.high, throttle) end
    local s = r.detect
    if not s then return end
    if not s.baseline then s.baseline = d.channels; return end
    for i = 1, math.min(8, #d.channels) do
      s.peaks[i] = math.max(s.peaks[i] or 0, math.abs(d.channels[i] - (s.baseline[i] or d.channels[i])))
    end
    local i = H.moved(s.peaks, s.exclude)
    if not i then return end
    s.found[order[s.index]], s.exclude[i] = i - 1, true
    s.index, s.baseline, s.peaks = s.index + 1, nil, {}
    if s.index <= 5 then w.message = L.move .. " " .. names[order[s.index]]; return end
    local used = {}; for _, c in pairs(s.found) do used[c] = true end
    local nextChannel = 0
    for n = 1, 8 do
      local channel = s.found[n]
      if channel == nil then
        while used[nextChannel] do nextChannel = nextChannel + 1 end
        channel, used[nextChannel] = nextChannel, true
      end
      map[keys[n]] = channel
    end
    r.detect = nil; w:touch("rx_map"); w.message = L.detected
  end
  w.validate = function()
    local raw = w.data.rx_channels
    local ok = raw and #raw.channels >= 5 and (w.data.status.arming_disable_flags & 4) == 0
    if not ok then w.message = L.noReceiver end
    return ok and not r.detect
  end
  local function mapped(n)
    return function()
      local channels = (w.data.rx_channels or {}).channels or {}
      return channels[(w.data.rx_map[keys[n]] or n - 1) + 1] or "--"
    end
  end
  return {
    w:cardDef(L.receiver, L.receiverHint, {
      w:port(L.port, 64),
      w:c("rx_config", "serialrx_provider", L.protocol,
        { "SPEK1024", "SPEK2048", "SBUS", "SUMD", "SUMH", "XBUS1", "XBUS2", "IBUS", "JETI EX", "CRSF",
          "SRXL", "CUSTOM", "FPORT", "SRXL2", "GHST", "FPORT2", "FBUS" }, true),
      w:button(L.detectWiring, function() w:startTrial("rx_serial_trial") end),
      w:button(L.saveReboot, function() w:feature(3, true); w:reboot() end)
    }),
    w:cardDef(L.channelOrder, L.channelHint, {
      w:button(L.detect, detect),
      w:button(L.standardOrder, function()
        for i, key in ipairs(keys) do w.data.rx_map[key] = i - 1 end
        w:touch("rx_map")
      end),
      w:value(L.roll, mapped(1)), w:value(L.collective, mapped(4))
    }),
    w:cardDef(L.checkSticks, L.sticksHint, {
      w:value(L.roll, mapped(1)), w:value(L.pitch, mapped(2)), w:value(L.yaw, mapped(3)), w:value(L.collective, mapped(4))
    }),
    w:cardDef(L.throttleRange, L.throttleHint, {
      w:value(L.throttle, mapped(5)),
      w:button(L.record, function() r.low, r.high, r.record = 3000, 0, true end),
      w:value(L.range, function() return string.format("%d / %d", r.low, r.high) end),
      w:button(L.useRange, function()
        if r.high - r.low < 300 then w.message = L.travelShort; return end
        r.record = nil
        w:field("rc_config", "rc_min_throttle", r.low + 20)
        w:field("rc_config", "rc_max_throttle", r.high - 20)
      end)
    }),
    w:cardDef(L.throttleRange, L.armThrottleHint, {
      w:n("rc_config", "rc_min_throttle", L.minimum, 0, 2100),
      w:n("rc_config", "rc_max_throttle", L.maximum, 0, 2100),
      w:button(L.defaults, function()
        w:field("rc_config", "rc_min_throttle", 0); w:field("rc_config", "rc_max_throttle", 0)
      end),
      w:value(L.throttleLow, function()
        local v = mapped(5)(); local zero = w.data.rc_config.rc_min_throttle
        if zero == 0 then zero = w.data.rc_config.rc_arm_throttle end
        return type(v) == "number" and v < zero - 5 and L.yes or L.no
      end)
    })
  }
end
