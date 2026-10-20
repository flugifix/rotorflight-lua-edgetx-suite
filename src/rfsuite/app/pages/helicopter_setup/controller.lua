local M = {}
local BASE = "/SCRIPTS/TOOLS/rfsuite-core/"
local READS = { "status", "boxnames", "boxids", "mode_ranges", "mode_ranges_extra", "adjustment_ranges",
  "feature_config", "board_alignment_config", "serial_config", "rx_map", "rx_config", "rc_config",
  "motor_config", "esc_sensor_config", "governor_config", "mixer_config", "mixer_input",
  "servo_configurations", "servo", "rc_tuning", "tail_motor_output" }
local STEPS = { "sensors", "receiver", "modes", "profiles", "rates", "swash", "servoType", "governor", "motor",
  "connect", "throttle", "escTelemetry", "servos", "direction", "level", "pitch", "tail", "gyro", "finish" }
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local function now() return getTime() end

function M.new(runtime, transport, mathModule, labels)
  local w = { runtime = runtime, math = mathModule, L = labels, data = {}, saved = {}, dirty = {},
    step = 1, card = 1, ready = false, active = true, holds = {}, live = {}, checks = {},
    progress = 0, message = labels.loading, generation = 0, selectedServo = 0, percent = 10 }
  function w:session() return _G.rfsuite and _G.rfsuite.session or {} end
  function w:allowed()
    local s = self:session()
    if not s.mcu_id or s.mcu_id == "" then return false end
    if not self.identity then self.identity = s.mcu_id end
    local armed = self.runtime.armedReading()
    return self.active and s.fblConnected == true and armed ~= true and not self.statusArmed
      and (not self.identity or self.identity == s.mcu_id)
  end
  function w:fail(api, reason)
    self.bus:cancel()
    self.error = api .. ": " .. tostring(reason)
    self.message, self.transition = self.L.failed, nil
    self:release()
    -- A failed multi-profile transaction must restore the selected profile, too.
    if self.restoreProfile and self:allowed() then
      self.bus:add({ api = "set_pid_profile", write = true, payload = { self.restoreProfile }, optional = true })
      self.restoreProfile = nil
    end
  end
  w.bus = transport.new(runtime, function() return w:allowed() end, function(a, r) w:fail(a, r) end)
  function w:read(api, after, optional, payload)
    self.bus:add({ api = api, payload = payload, optional = optional, after = after })
  end
  function w:write(api, data, after, optional, decode)
    self.bus:add({ api = api, write = true, data = data, after = after, optional = optional, decode = decode })
  end
  function w:action(api, payload, after, optional)
    self.bus:add({ api = api, write = true, payload = payload, after = after, optional = optional })
  end
  function w:run(fn) self.bus:add({ run = fn }) end
  function w:rebuild() if self.requestRebuild then self.requestRebuild() end end
  function w:usable() return self.ready and self.locked and not self.error and not self.transition and self:allowed() end
  function w:acceptStatus(d)
    self.data.status, self.statusAt = d, now()
    if self.locked and (d.arming_disable_flags & (1 << 16)) == 0 then
      self.locked = false; self:fail("arming_disable", "lock lost"); return
    end
    self.statusArmed = false
    for i, id in ipairs(self.data.boxids and self.data.boxids.box_ids or {}) do
      if id == 0 then self.statusArmed = (d.flight_mode_flags & (1 << (i - 1))) ~= 0; break end
    end
    if self.calibrationAt and now() - self.calibrationAt >= 200 and (d.arming_disable_flags & (1 << 23)) == 0 then
      self.calibrationAt = nil; self.message = self.L.calibrated
    end
  end
  function w:retry()
    if not self.bus:idle() or not self:allowed() then return end
    self.error, self.transition = nil, true
    self:write("arming_disable", { disabled = true })
    self:read("status", function(d)
      if (d.arming_disable_flags & (1 << 16)) == 0 then self:fail("arming_disable", "not active"); return end
      self.locked = true; self:acceptStatus(d)
      if not self.ready then self:load() else self.transition = nil; self:rebuild() end
    end)
  end
  function w:touch(api, reboot, live)
    self.dirty[api] = true
    if reboot then self.rebootPending = true end
    if live then self.live[api] = true end
  end
  function w:field(api, key, value, reboot, live)
    if not self:usable() then return end
    if self.data[api][key] == value then return end
    self.data[api][key] = value; self:touch(api, reboot, live)
  end
  function w:sendDirty(api, from)
    local d = from or self.data
    -- Generate at most one indexed message per call. A full adjustment table
    -- must not be encoded in a button callback or an MSP reply.
    local cursor = 0
    local count = api == "servo_configurations" and math.min(8, d[api].servo_count) or
      api == "mixer_input" and 4 or api == "serial_config" and 12 or
      api == "mode_ranges" and #d[api].mode_ranges or
      api == "adjustment_ranges" and #d[api].adjustment_ranges
    if count then
      self.bus:add({ expand = function()
        cursor = cursor + 1
        if cursor > count then return nil end
        local index = cursor
        if api == "servo_configurations" then
          return { api = api, write = true, data = { index = index - 1, servo = d[api].servos[index - 1] } }
        elseif api == "mixer_input" then
          local r = d[api].inputs[index]
          return { api = api, write = true, data = { index = index, rate = r.rate, min = r.min, max = r.max } }
        elseif api == "serial_config" then
          local p = {}
          for _, key in ipairs({ "identifier", "function_mask", "msp_baud_index", "gps_baud_index", "telem_baud_index", "blackbox_baud_index" }) do
            p[key] = d[api]["port_" .. index .. "_" .. key]
          end
          if p.identifier == nil then return { run = function() end } end
          return { api = api, write = true, data = p }
        elseif api == "mode_ranges" then
          local r = d[api].mode_ranges[index]
          local extra = d.mode_ranges_extra.mode_ranges_extra[index] or {}
          return { api = "set_mode_range", write = true, payload = { index - 1, r.id, r.auxChannelIndex,
            self.math.step(r.range.start), self.math.step(r.range["end"]), extra.modeLogic or 0, extra.linkedTo or 0 } }
        else
          return { api = "set_adjustment_range", write = true,
            payload = self.math.adjustPayload(index - 1, d[api].adjustment_ranges[index]) }
        end
      end })
      return
    end
    self:write(api, function() return d[api] end)
  end
  function w:release(all)
    local held, motor = self.holds, self.motorHold
    self.holds, self.motorHold, self.listen = {}, nil, nil
    if self.rx then self.rx.detect, self.rx.record = nil, nil end
    if self.modeListen then self.modeListen.id = nil end
    if self.profile then self.profile.listen, self.profile.record = nil, nil end
    if self.stopTrial then self:stopTrial() end
    self.bus:dropOverrides()
    local q = self.bus:queue()
    if not q then return end
    q:clear("helicopter-overrides")
    if not self:allowed() then self.needsRelease = true; return end
    -- These modules are preloaded on entry. The cleanup owner survives the host's page clear.
    local apis = self.bus.apis
    local function send(api, data)
      local mod = apis[api]; if not mod then return end
      q:add({ command = mod.writeCommand, payload = mod.buildWritePayload(data), isWrite = true,
        client = "helicopter-cleanup", maxRetries = 0 })
    end
    if all or self.needsRelease then
      for i = 0, 7 do send("servo_override", { servo_id = i, action = 2001 }) end
      for i = 1, 4 do send("mixer_override", { index = i, value = 2501 }) end
      for i = 0, 3 do send("motor_override", { index = i, value = 0 }) end
    else
      for _, h in pairs(held) do
        if h.kind == "servo" then send("servo_override", { servo_id = h.index, action = 2001 })
        else send("mixer_override", { index = h.index, value = 2501 }) end
      end
      if motor then send("motor_override", { index = motor.index, value = 0 }) end
    end
    self.needsRelease = nil
  end
  function w:hold(kind, index, value)
    if not self:usable() or self.rebootPending then return end
    if not self.timed then self.message = self.L.persistent end
    self.holds[kind .. index] = { kind = kind, index = index, value = value, due = 0 }
  end
  function w:holdAxes(axis, value, passthrough)
    for _, i in ipairs({ 1, 2, 4 }) do self:hold("mixer", i, passthrough and 2502 or (i == axis and value or 0)) end
  end
  function w:spin(index, direction)
    if not self:usable() or not self.bladesOff or self.rebootPending then return end
    if index >= (self.data.status.motor_count or 0) then return end
    if index == 0 and self.data.motor_config.motor_pwm_protocol == 0 and not self.calibratedEsc then return end
    self.motorHold = { index = index, value = self.percent * 10 * direction, due = 0, untilAt = now() + 1500 }
  end
  function w:stopMotor()
    self.motorHold = nil
    self.bus:dropOverrides()
    local q = self.bus:queue()
    if q then q:clear("helicopter-overrides") end
    if self:allowed() then
      for i = 0, 1 do self:write("motor_override", { index = i, value = 0 }) end
    end
  end
  function w:profileLoop(kind, count, apply)
    local status = self.data.status
    local original = kind == "rates" and status.current_control_rate_profile_index + 128 or status.current_pid_profile_index
    local api = kind == "rates" and "rc_tuning" or "governor_profile"
    self.restoreProfile = original
    for i = 0, math.min(count, 6) - 1 do
      local index = i
      self:action("set_pid_profile", { index + (kind == "rates" and 128 or 0) })
      self:read(api, function(d)
        self.profileData = d
        self.profileOriginal = self.profileOriginal or {}
        self.profileOriginal[kind] = self.profileOriginal[kind] or {}
        self.profileOriginal[kind][index] = self.profileOriginal[kind][index] or copy(d)
      end)
      self:write(api, function() apply(self.profileData, index); return self.profileData end)
    end
    self:action("set_pid_profile", { original }, function() self.restoreProfile = nil end)
    self:read(api, function(d) self.data[api] = d end)
    self:read("status", function(d) self.data.status = d end)
  end
  function w:save(after)
    self.transition = true; self.message = self.L.saving
    self:release()
    if self.commit then self.commit() end
    for api in pairs(self.dirty) do
      if api ~= "rc_tuning" and api ~= "governor_profile" and api ~= "tail_motor_output" then self:sendDirty(api) end
    end
    self:write("eeprom_write", {}, function()
      self.dirty, self.live, self.profileOriginal = {}, {}, nil
      self.snapshotIndex = 1
    end)
    -- Snapshot one API block per wakeup; never clone the whole configuration in a reply.
    for _, api in ipairs(READS) do
      local name = api
      self:run(function() self.saved[name] = copy(self.data[name]) end)
    end
    self:run(function() self.transition = nil; self.message = self.L.saved; if after then after() end end)
  end
  function w:navigate(step, card)
    if self.transition or not self.ready then return end
    if self.step >= 10 and step <= 9 then self.checks.unplugged = nil end
    if step ~= self.step then
      local owned = ({ [1] = {"orientation", "unplugged", "blades"}, [10] = {"connected"}, [11] = {"motorDirection"},
        [13] = {"servoUp0", "servoUp1", "servoUp2", "servoCentre0", "servoCentre1", "servoCentre2", "servoCentre3"},
        [14] = {"control1", "control2", "control4"}, [15] = {"level"}, [16] = {"pitch"},
        [17] = {"tailCentre", "tailDirection"}, [18] = {"gyro1", "gyro2", "gyro3"}, [19] = {"finish"} })[step]
      for _, name in ipairs(owned or {}) do self.checks[name] = nil end
      if step == 11 or step == 17 then self.bladesOff, self.percent = false, 10 end
    end
    self:release()
    self.step, self.card, self.commit, self.cards, self.enter, self.onLive = step, card or 1, nil, nil, nil, nil
    self.buildRequested = true; self:rebuild()
  end
  function w:next()
    if not self:usable() or not self.cards then return end
    if self.step == 1 and (not self:ack("unplugged") or not self:ack("blades")) then return end
    if self.card < #self.cards then self:navigate(self.step, self.card + 1); return end
    if self.validate and not self.validate() then return end
    if self.step == 10 and self.rebootPending then self:reboot(); return end
    if self.rebootPending and self.step > 10 then self:reboot(); return end
    if not next(self.dirty) then
      if self.step == 19 then self:close() else self:navigate(self.step + 1, 1) end
      return
    end
    self:save(function()
      if self.step == 19 then self:close() else self:navigate(self.step + 1, 1) end
    end)
  end
  function w:back()
    if self.transition then return end
    if self.confirmExit then self.confirmExit = nil; self:rebuild(); return end
    if self.card > 1 then self:navigate(self.step, self.card - 1)
    elseif self.step > 1 then self:navigate(self.step - 1, 1)
    else self:release(); self.confirmExit = true; self:rebuild() end
  end
  function w:close()
    self:release()
    self:write("arming_disable", { disabled = false }, function()
      self.active = false; if self.requestClose then self.requestClose() end
    end)
  end
  function w:discard()
    self.transition = true
    for kind, profiles in pairs(self.profileOriginal or {}) do
      for index, original in pairs(profiles) do
        self:action("set_pid_profile", { index + (kind == "rates" and 128 or 0) })
        self:write(kind == "rates" and "rc_tuning" or "governor_profile", original)
      end
      local status = self.data.status
      self:action("set_pid_profile", { kind == "rates" and status.current_control_rate_profile_index + 128 or status.current_pid_profile_index })
    end
    for api in pairs(self.dirty) do
      if self.saved[api] then
        if api == "tail_motor_output" then
          self:write(api, { action = self.saved[api].output + 1 })
        else self:sendDirty(api, self.saved) end
      end
    end
    self:run(function() self:close() end)
  end
  function w:reboot()
    self:save(function()
      self.transition = true; self.message = self.L.rebooting; self.rebootAt = now(); self.rebootPhase = "sent"
      self:write("reboot", {}, function() self.rebootPhase = "wait" end, true)
    end)
  end
  function w:load()
    self.ready, self.error, self.progress, self.transition = false, nil, 0, true
    self.locked = false
    self:write("arming_disable", { disabled = true })
    self:read("status", function(d)
      if (d.arming_disable_flags & (1 << 16)) == 0 then self:fail("arming_disable", "not active"); return end
      self.locked = true; self:acceptStatus(d)
    end)
    for _, api in ipairs({ "servo_override", "mixer_override", "motor_override" }) do
      local name = api
      self:run(function() self.bus.apis[name] = assert(loadScript(BASE .. "tasks/msp/api/" .. name .. ".lua", "t"))() end)
    end
    self:run(function() self:release(true) end)
    self:write("servo_override_all", { value = 2001, timeout = 500 }, function(_, err) self.timed = err == nil end, true)
    for _, name in ipairs(READS) do
      local api = name
      self:read(api, function(d)
        if api == "board_alignment_config" and d then
          for _, key in ipairs({"roll_degrees", "pitch_degrees", "yaw_degrees"}) do d[key] = self.math.signed(d[key]) end
        end
        self.data[api], self.progress = d, self.progress + 1
        if api == "status" then
          -- The ARM box bit is identified by BOXIDS below, never assumed to be bit zero.
          self:acceptStatus(d)
        end
      end, api == "tail_motor_output")
      self:run(function() self.saved[api] = copy(self.data[api]) end)
    end
    self:run(function()
      self.identity = self:session().mcu_id
      local inputs = self.data.mixer_input.inputs
      if not inputs[4] or not self.data.status.pid_profile_count or self.data.status.pid_profile_count < 1 then
        self:fail("status", "configuration"); return
      end
      self.startTail = self.data.mixer_config.tail_rotor_mode
      self.ready, self.transition, self.buildRequested = true, nil, true
      self.message = self.timed and self.L.ready or self.L.persistent
      self:rebuild()
    end)
  end
  function w:poll()
    local time = now()
    if time - (self.lastPoll or 0) < 20 then return end
    self.lastPoll = time
    self.pollIndex = (self.pollIndex or 0) % 3 + 1
    local api = self.pollIndex == 1 and "status" or self.pollIndex == 2 and "servo" or
      ({ [1] = "attitude", [2] = "rx_channels", [3] = "rc", [4] = "rc", [10] = "motor", [11] = "motor",
        [12] = "motor_telemetry", [14] = "rc_command", [17] = self:motorised() and "motor" or "rc_command" })[self.step]
    if not api then return end
    self:read(api, function(d)
      self.data[api] = d
      if api == "status" then
        self:acceptStatus(d)
      end
      if self.onLive then self.onLive(api, d) end
    end)
  end
  function w:motorised() return self.data.mixer_config and self.data.mixer_config.tail_rotor_mode ~= 0 end
  function w:servos()
    local d = self.data.servo_configurations
    if not d then return {} end
    local swash = self.data.mixer_config.swash_type
    local cyclic = (swash == 5 or swash == 6) and 2 or 3
    local count = math.min(d.servo_count, self.data.status.servo_count or 0)
    for i = 1, 12 do
      local mask = self.data.serial_config["port_" .. i .. "_function_mask"] or 0
      if (mask & (262144 | 524288)) ~= 0 then count = math.max(0, count - 18); break end
    end
    local list = {}; for i = 0, math.min(cyclic, count, 8) - 1 do list[#list + 1] = i end
    if not self:motorised() and count >= 4 then list[#list + 1] = 3 end
    return list
  end
  function w:tick()
    if not self.active then return end
    if not self:allowed() then
      if not self.suspended then
        self.suspended = true; self.bus:cancel(); self:release(); self.message = self.L.disconnected
        self.ready = false; self:rebuild()
      end
      return
    end
    if self.suspended then
      self.suspended = nil
      if self.rebootPhase then self.rebootPhase = nil; self.rebootPending = nil; self:load()
      else self.error = "link"; self.message = self.L.reload end
      return
    end
    if self.rebootPhase and self.rebootPhase ~= "sent" then
      if now() - self.rebootAt > 3000 then self.rebootPhase = nil; self:fail("reboot", "timeout") end
      if now() - self.rebootAt >= 200 and self.bus:idle() then
        self:read("status", function(d, err)
          if err or not d or d.reboot_required ~= 0 then return end
          self.rebootPhase, self.rebootPending = nil, nil
          self:load()
        end, true)
      end
      if not self.bus:idle() then self.bus:tick() end
      return
    end
    if not self.bus:idle() then self.bus:tick(); return end
    if self.buildRequested and self.ready then
      self.buildRequested = nil
      local key = STEPS[self.step]
      self.validate, self.onLive, self.commit = nil, nil, nil
      self.cards = assert(loadScript(BASE .. "app/pages/helicopter_setup/steps/" .. key .. ".lua", "t"))()(self)
      self.card = math.min(self.card, #self.cards)
      if self.cards[self.card].enter then self.cards[self.card].enter() end
      self:rebuild(); return
    end
    if not self.ready or self.error or self.transition then return end
    if self.trialTick and self:trialTick() then return end
    if now() - (self.statusAt or 0) > 100 then
      self:read("status", function(d) self:acceptStatus(d) end); return
    end
    if now() - (self.statusAt or 0) > 300 then
      self:release(); self.message = self.L.stale
      self:read("status", function(d) self:acceptStatus(d) end)
      return
    end
    if self.live and next(self.live) then
      local api = next(self.live); self.live[api] = nil; self:sendDirty(api); return
    end
    if self.motorHold then
      local h = self.motorHold
      if now() >= h.untilAt then self:stopMotor(); return end
      if now() >= h.due then
        h.due = now() + 25
        self.bus:add({ api = "motor_override", write = true, override = true,
          data = { index = h.index, value = h.value } }); return
      end
    end
    for _, h in pairs(self.holds) do
      if now() >= h.due then
        h.due = now() + 100
        local d = h.kind == "servo" and { servo_id = h.index, action = h.value } or { index = h.index, value = h.value }
        if self.timed then d.timeout = 3000 end
        self.bus:add({ api = h.kind .. "_override", write = true, override = true, data = d }); return
      end
    end
    self:poll()
  end
  return w
end
return M
