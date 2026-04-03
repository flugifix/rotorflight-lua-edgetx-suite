local Audio = {}

local AUDIO_PACK_BASE = "/SOUNDS/rfsuite/"
local AUDIO_DEFAULT_FALLBACK = "en"
local AUDIO_ROOT_BASE = "/audio/"
local localeModule = nil

local ARM_FILE_MAP = {
  [0] = "disarmed.wav",
  [1] = "armed.wav",
  [2] = "disarmed.wav",
  [3] = "armed.wav"
}

local GOVERNOR_FILE_MAP = {
  [0] = "off.wav",
  [1] = "idle.wav",
  [2] = "spoolup.wav",
  [3] = "recovery.wav",
  [4] = "active.wav",
  [5] = "thr-off.wav",
  [6] = "lost-hs.wav",
  [7] = "autorot.wav",
  [8] = "bailout.wav",
  [100] = "disabled.wav",
  [101] = "disarmed.wav"
}

local function nowSeconds()
  if getTime then
    local ok, value = pcall(getTime)
    if ok and type(value) == "number" then
      return value / 100
    end
  end

  if os and type(os.clock) == "function" then
    return os.clock()
  end

  return 0
end

local function isTruthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

local function prefEnabled(events, key, defaultValue)
  local value = events and events[key]
  if value == nil then return defaultValue end
  return isTruthy(value)
end

local function roundProfileValue(value)
  if type(value) ~= "number" then
    return nil
  end
  return math.floor(value + 0.5)
end

local function unitPercent()
  if type(UNIT_PERCENT) == "number" then return UNIT_PERCENT end
  return 0
end

local function emitLog(opts, msg, level)
  if opts and type(opts.log) == "function" then
    opts.log(msg, level)
  end
end

local function getLocaleModule()
  if localeModule then
    return localeModule
  end

  if type(_G) == "table" and type(_G.__rfsuiteSystemLocaleModule) == "table" then
    localeModule = _G.__rfsuiteSystemLocaleModule
    return localeModule
  end

  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/system_locale.lua", "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then
      localeModule = mod
      if type(_G) == "table" then
        _G.__rfsuiteSystemLocaleModule = mod
      end
    end
  end

  return localeModule
end

local function resolveAudioLanguage()
  local mod = getLocaleModule()
  if mod and type(mod.resolveAudioFolder) == "function" then
    local ok, folder = pcall(mod.resolveAudioFolder, AUDIO_DEFAULT_FALLBACK)
    if ok and (folder == "de" or folder == "en") then
      return folder
    end
  end

  return AUDIO_DEFAULT_FALLBACK
end

local function playResolvedEventFile(relativePath, opts)
  if type(playFile) ~= "function" or type(relativePath) ~= "string" or relativePath == "" then
    return false
  end

  local selectedFolder = resolveAudioLanguage()
  if selectedFolder ~= "de" and selectedFolder ~= "en" then
    selectedFolder = AUDIO_DEFAULT_FALLBACK
  end

  local fullPath = AUDIO_PACK_BASE .. selectedFolder .. "/" .. relativePath
  emitLog(opts, "playFile -> " .. fullPath, "info")
  playFile(fullPath)
  return true
end

local function playRawFile(path)
  if type(playFile) ~= "function" or type(path) ~= "string" or path == "" then
    return false
  end
  playFile(path)
  return true
end

local function scheduleAudioCooldown(audioState, now, seconds)
  audioState.nextAllowedAt = now + (seconds or 0.25)
end

local function tryPlayEventFile(audioState, now, relativePath, opts)
  if now < (audioState.nextAllowedAt or 0) then
    emitLog(opts, "cooldown active; skip " .. tostring(relativePath), "debug")
    return false
  end

  if not playResolvedEventFile(relativePath, opts) then
    emitLog(opts, "failed to play " .. tostring(relativePath), "warn")
    return false
  end

  scheduleAudioCooldown(audioState, now, 0.25)
  emitLog(opts, "played " .. tostring(relativePath), "info")
  return true
end

local function fuelThresholdList(selection)
  local sel = tonumber(selection) or 0
  if sel == 0 then return { 100, 10 } end
  if sel == 10 then return { 100, 90, 80, 70, 60, 50, 40, 30, 20, 10 } end
  if sel == 20 then return { 100, 80, 60, 40, 20, 10 } end
  if sel == 25 then return { 100, 75, 50, 25, 10 } end
  if sel == 50 then return { 100, 50, 10 } end
  if sel == 5 then return { 50, 5 } end
  if sel > 0 then return { sel } end
  return { 10 }
end

local function getModelName()
  if type(model) ~= "table" or type(model.getInfo) ~= "function" then
    return nil
  end
  local ok, info = pcall(model.getInfo)
  if not ok or type(info) ~= "table" then
    return nil
  end
  local name = info.name
  if type(name) ~= "string" or name == "" then
    return nil
  end
  return name
end

local function announceModelName(audioState)
  local modelName = getModelName()
  if not modelName then return end

  local candidates = {
    AUDIO_ROOT_BASE .. modelName .. ".wav",
    AUDIO_ROOT_BASE .. string.gsub(modelName, " ", "_") .. ".wav"
  }

  for i = 1, #candidates do
    if playRawFile(candidates[i]) then
      audioState.modelAnnounced = true
      return
    end
  end
end

local function announceProfileEvent(self, eventKey, value, soundFile, opts)
  local rounded = roundProfileValue(value)
  if rounded == nil or rounded <= 0 then
    return
  end

  local audioState = self.audioState
  if audioState.lastValues[eventKey] == rounded then
    return
  end

  local now = nowSeconds()
  if now < (audioState.nextAllowedAt or 0) then
    audioState.pendingValues[eventKey] = rounded
    return
  end

  local events = (self.preferences and self.preferences.audio_events) or nil
  if not prefEnabled(events, eventKey, true) then
    audioState.lastValues[eventKey] = rounded
    audioState.pendingValues[eventKey] = nil
    return
  end

  if audioState.initialized then
    emitLog(opts, eventKey .. " change value=" .. tostring(rounded) .. " file=" .. tostring(soundFile), "info")
    tryPlayEventFile(audioState, now, soundFile, opts)
    if type(playNumber) == "function" then
      emitLog(opts, "playNumber -> " .. tostring(rounded), "info")
      playNumber(rounded, 0)
    end
    scheduleAudioCooldown(audioState, now, 0.25)
  end

  audioState.lastValues[eventKey] = rounded
  audioState.pendingValues[eventKey] = nil
end

local function announceArmEvent(self, opts)
  local audioState = self.audioState
  local rounded = roundProfileValue(self.state.armFlags)
  if rounded == nil then return false end
  if audioState.lastValues.arming_flags == rounded then
    return false
  end

  audioState.lastValues.arming_flags = rounded
  if not audioState.initialized then
    return false
  end

  local file = ARM_FILE_MAP[rounded]
  if type(file) ~= "string" then
    local armed = false
    if bit32 and type(bit32.btest) == "function" then
      armed = bit32.btest(rounded, 1)
    else
      armed = rounded ~= 0
    end
    file = armed and "armed.wav" or "disarmed.wav"
  end

  local now = nowSeconds()
  emitLog(opts, "arming change value=" .. tostring(rounded) .. " file=" .. tostring(file), "info")
  return tryPlayEventFile(audioState, now, "events/alerts/" .. file, opts)
end

local function announceGovernorEvent(self, opts)
  local audioState = self.audioState
  local rounded = roundProfileValue(self.state.governor)
  if rounded == nil then return false end
  if audioState.lastValues.governor_state == rounded then
    return false
  end

  audioState.lastValues.governor_state = rounded
  if not audioState.initialized then
    return false
  end

  local file = GOVERNOR_FILE_MAP[rounded]
  if type(file) ~= "string" then return false end
  local now = nowSeconds()
  return tryPlayEventFile(audioState, now, "events/gov/" .. file, opts)
end

function Audio.process(self, opts)
  if type(self) ~= "table" or type(self.audioState) ~= "table" then
    return
  end

  local audioState = self.audioState
  local events = (self.preferences and self.preferences.audio_events) or {}
  local now = nowSeconds()

  local governorEnabled = prefEnabled(events, "governor_state", true)
  if audioState.lastEnabled.governor_state ~= governorEnabled then
    audioState.lastEnabled.governor_state = governorEnabled
    emitLog(opts, "governor_state enabled=" .. tostring(governorEnabled), "info")
  end

  if not audioState.modelAnnounced and prefEnabled(events, "model_announcement", false) then
    announceModelName(audioState)
  end

  if prefEnabled(events, "arming_flags", true) then
    announceArmEvent(self, opts)
  end

  if governorEnabled and audioState.initialized then
    announceGovernorEvent(self, opts)
  end

  announceProfileEvent(self, "pid_profile", self.state.profile, "events/alerts/profile.wav", opts)
  announceProfileEvent(self, "rate_profile", self.state.rateProfile, "events/alerts/rates.wav", opts)
  announceProfileEvent(self, "battery_profile", self.state.batteryProfile, "events/alerts/battery.wav", opts)

  if prefEnabled(events, "voltage_alert", true) then
    local warnBase = (self.state.themeConfig and tonumber(self.state.themeConfig.v_min)) or 18.0
    local warn = warnBase + 0.3
    local reset = warn + 0.2
    local voltage = tonumber(self.state.voltage)
    if type(voltage) == "number" and voltage > 0 then
      if voltage <= warn then
        local lastAt = audioState.lastAlertAt.voltage or 0
        if now - lastAt >= 10 then
          if tryPlayEventFile(audioState, now, "events/alerts/lowvoltage.wav", opts) then
            audioState.lastAlertAt.voltage = now
          end
        end
      elseif voltage >= reset then
        audioState.lastAlertAt.voltage = 0
      end
    end
  else
    audioState.lastAlertAt.voltage = 0
  end

  if prefEnabled(events, "esc_temperature", false) then
    local threshold = tonumber(events.esc_threshold) or 90
    local escTemp = tonumber(self.state.escTemp)
    if type(escTemp) == "number" then
      if escTemp >= threshold then
        local lastAt = audioState.lastAlertAt.esc_temperature or 0
        if now - lastAt >= 10 then
          if tryPlayEventFile(audioState, now, "events/alerts/esctemp.wav", opts) then
            if type(playHaptic) == "function" then
              playHaptic(15, 10, 3)
            end
            audioState.lastAlertAt.esc_temperature = now
          end
        end
      else
        audioState.lastAlertAt.esc_temperature = 0
      end
    end
  else
    audioState.lastAlertAt.esc_temperature = 0
  end

  if prefEnabled(events, "fuel_alerts", true) then
    local fuelValue = tonumber(self.state.fuel)
    if type(fuelValue) == "number" then
      if fuelValue < 0 then fuelValue = 0 end
      if fuelValue > 100 then fuelValue = 100 end

      local repeats = tonumber(events.fuel_repeat_below_zero) or 1
      if repeats < 1 then repeats = 1 end
      if repeats > 10 then repeats = 10 end

      if fuelValue <= 0 then
        local canRepeat = (now - (audioState.lowFuelLastAt or 0)) >= 10
        if (not audioState.lowFuelActive) or (audioState.lowFuelRepeatCount < repeats and canRepeat) then
          if tryPlayEventFile(audioState, now, "status/alerts/lowfuel.wav", opts) then
            if events.fuel_haptic_below_zero == true and type(playHaptic) == "function" then
              playHaptic(15, 10, 3)
            end
            audioState.lowFuelActive = true
            audioState.lowFuelLastAt = now
            audioState.lowFuelRepeatCount = (audioState.lowFuelRepeatCount or 0) + 1
          end
        end
      else
        audioState.lowFuelActive = false
        audioState.lowFuelLastAt = 0
        audioState.lowFuelRepeatCount = 0

        local currentRounded = roundProfileValue(fuelValue)
        if currentRounded and currentRounded >= 0 then
          local lastCallout = audioState.lastFuelCallout
          if lastCallout == nil then
            audioState.lastFuelCallout = currentRounded
          else
            local thresholds = fuelThresholdList(events.fuel_callout_percent)
            for i = 1, #thresholds do
              local threshold = thresholds[i]
              if currentRounded <= threshold and lastCallout > threshold then
                if tryPlayEventFile(audioState, now, "status/alerts/fuel.wav", opts) then
                  if type(playNumber) == "function" then
                    emitLog(opts, "fuel callout playNumber -> " .. tostring(threshold), "info")
                    playNumber(threshold, unitPercent())
                  end
                  audioState.lastFuelCallout = threshold
                end
                break
              end
            end
            if currentRounded > lastCallout then
              audioState.lastFuelCallout = currentRounded
            end
          end
        end
      end
    end
  else
    audioState.lowFuelActive = false
    audioState.lowFuelLastAt = 0
    audioState.lowFuelRepeatCount = 0
    audioState.lastFuelCallout = nil
  end

  if not audioState.initialized then
    audioState.initialized = true
  end
end

return Audio
