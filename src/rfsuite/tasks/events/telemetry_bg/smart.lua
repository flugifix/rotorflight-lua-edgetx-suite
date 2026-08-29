-- Smart sensor bridge for EdgeTX dashboard (ported from Ethos smart.lua flow)
local Smart = {}

local APPID_SMARTFUEL = 0x5FE1
local APPID_SMARTCONSUMPTION = 0x5FE0
local SENSOR_NAME_SMARTFUEL = "SmFt"
local SENSOR_NAME_SMARTCONSUMPTION = "SmCp"
local FORCE_REFRESH_INTERVAL = 2.0

local MIRROR_FUEL_QUERIES = {
  { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5007 },
  { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0600 },
  { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1014 }
}

local MIRROR_CONSUMPTION_QUERIES = {
  { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5008 },
  { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5250 },
  { category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1013 }
}

local Sensors = nil
local MspRuntime = nil
local Log = nil
local ApiVersion = nil
local Reserve = nil

local initialized = false
local lastWake = 0
local wakeInterval = 1.0
local dischargeCurveTable = nil

local state = {
  batterySignature = nil,
  sourceMode = nil,
  stabilizeUntil = 0,
  voltageSamples = {},
  voltageStable = false,
  startFuelPercent = nil,
  startConsumptionOffset = nil,
  virtualConsumption = nil,
  lastFilteredVoltage = nil,
  lastTimestamp = nil,
  lastFuelValue = nil,
  lastFuelPush = 0,
  lastConsumptionValue = nil,
  lastConsumptionPush = 0,
  lastFirmwareFuelMissingLog = 0
}

local function loadModule(path)
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. path, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, v = pcall(getTime)
    if ok and type(v) == "number" then return v / 100 end
  end
  if type(os) == "table" and type(os.clock) == "function" then return os.clock() end
  return 0
end

local function logSmart(msg, level)
  if not Log then return end
  if type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.smart", tostring(msg), level or "debug", true)
  end
end

local function clamp(v, minv, maxv)
  if v == nil then return nil end
  if v < minv then return minv end
  if v > maxv then return maxv end
  return v
end

local function roundInt(v)
  if type(v) ~= "number" then return nil end
  return math.floor(v + 0.5)
end

local function normalizeBatteryProfileIndex(value)
  local n = tonumber(value)
  if not n then return nil end
  n = math.floor(n)
  if n >= 1 and n <= 6 then return n - 1 end
  if n >= 0 and n <= 5 then return n end
  return nil
end

local function resetVoltageTracking()
  state.voltageSamples = {}
  state.voltageStable = false
end

local function resetComputedState()
  state.startFuelPercent = nil
  state.startConsumptionOffset = nil
  state.virtualConsumption = nil
  state.lastFilteredVoltage = nil
  state.lastTimestamp = nil
  resetVoltageTracking()
end

local function ensureCurve()
  if dischargeCurveTable then return end
  dischargeCurveTable = {}
  for i = 0, 120 do
    local v = 3.00 + i * 0.01
    local a = 12
    local b = 3.7
    local percent = 100 / (1 + math.exp(-a * (v - b)))
    dischargeCurveTable[i + 1] = math.floor(clamp(percent, 0, 100) + 0.5)
  end
end

local function getSession()
  local root = _G and _G.rfsuite
  return root and root.session or nil
end

local function getSensor(name)
  if not Sensors or type(Sensors.getValue) ~= "function" then return nil end
  return Sensors.getValue(name)
end

local function readSourceValue(query)
  if type(system) ~= "table" or type(system.getSource) ~= "function" then
    return nil
  end
  local source = system.getSource(query)
  if not source then return nil end
  if source.state and source:state() == false then return nil end
  return source:value()
end

local function readFirstSourceValue(queries)
  for i = 1, #queries do
    local value = readSourceValue(queries[i])
    if type(value) == "number" then
      return value
    end
  end
  return nil
end

local function readFirmwareFuelValue()
  -- Avoid feedback loops: never use SmFt (smartfuel alias) as input for SmFt calculation.
  -- Prefer direct FC fuel percentage first, then mirror appIds as fallback.
  local value = tonumber(getSensor("fuel"))
  if type(value) == "number" then
    return value, "fuel"
  end

  value = tonumber(getSensor("Bat%"))
  if type(value) == "number" then
    return value, "Bat%"
  end

  value = readFirstSourceValue(MIRROR_FUEL_QUERIES)
  if type(value) == "number" then
    return value, "mirror"
  end

  return nil, nil
end

local function resolveReservePercent(session, batteryConfig)
  -- Fix for issue #52: do not write back into batteryConfig here. The session's
  -- battery_config must keep what the flight controller reported so that
  -- loadFromSession on the Battery page can display the board's actual value
  -- rather than the substituted preference. SmartFuel only needs the resolved
  -- number locally and is not authoritative for the page's display.
  return Reserve.resolve(session, batteryConfig)
end

local function scaleField(raw, fallback, minValue, maxValue, scale)
  local value = tonumber(raw)
  if value == nil then return fallback end

  if scale and scale > 1 and maxValue and value > maxValue then
    local guard = 0
    while value > maxValue and guard < 4 do
      value = value / scale
      guard = guard + 1
    end
  end

  if minValue and value < minValue then value = minValue end
  if maxValue and value > maxValue then value = maxValue end
  return value
end

local function getSmartConfig(session)
  local cfg = session and session.smartfuel_config or nil
  local batteryPrefs = session and session.modelPreferences and session.modelPreferences.battery or nil

  local function readLegacyLocalSource()
    local source = batteryPrefs and tonumber(batteryPrefs.smartfuel_source) or nil
    if source == nil then
      source = batteryPrefs and tonumber(batteryPrefs.calc_local) or nil
    end
    return source
  end

  local function getFirmwareSource()
    local apiVersion = ApiVersion and ApiVersion.parse and ApiVersion.parse(session and session.apiVersion)
    if not (ApiVersion and ApiVersion.isAtLeast and ApiVersion.isAtLeast(apiVersion, { 12, 0, 9 })) then
      return nil
    end
    local mode = cfg and tonumber(cfg.smartfuel_mode) or nil
    if mode == nil then
      local batteryConfig = session and session.battery_config
      mode = batteryConfig and tonumber(batteryConfig.smartfuelRemoteSource) or nil
    end
    return mode
  end

  local function pick(key)
    if cfg and cfg[key] ~= nil then return cfg[key] end
    if batteryPrefs and batteryPrefs[key] ~= nil then return batteryPrefs[key] end
    return nil
  end

  local source = readLegacyLocalSource()
  if source == nil then source = 0 end

  local voltageDropRate = tonumber(pick("voltage_drop_rate"))
  local chargeDropRate = tonumber(pick("charge_drop_rate"))

  local voltageFallPerSecond = nil
  if voltageDropRate ~= nil then
    voltageFallPerSecond = voltageDropRate / 1000
  else
    voltageFallPerSecond = scaleField(pick("voltage_fall_limit"), 0.05, 0, 1, 100)
  end

  local fuelDropPerSecond = nil
  if chargeDropRate ~= nil then
    fuelDropPerSecond = chargeDropRate / 100
  else
    fuelDropPerSecond = scaleField(pick("fuel_drop_rate"), 1.0, 0, 50, 10)
  end

  return {
    firmwareSource = getFirmwareSource(),
    source = source,
    stabilizeDelaySeconds = scaleField(pick("stabilize_delay"), 1.5, 0, 10, 1000),
    stableWindowVolts = scaleField(pick("stable_window"), 0.15, 0, 1, 100),
    voltageFallPerSecond = voltageFallPerSecond,
    fuelDropPerSecond = fuelDropPerSecond
  }
end

local function getActivePackCapacity(session, batteryConfig)
  local packCapacity = tonumber(batteryConfig and batteryConfig.batteryCapacity) or 0
  local profile = normalizeBatteryProfileIndex(getSensor("battery_profile"))
  if session then
    session.activeBatteryType = profile
  end

  if profile ~= nil and batteryConfig then
    local profileCapacity = tonumber(batteryConfig["batteryCapacity_" .. tostring(profile)])
    if profileCapacity and profileCapacity > 0 then
      packCapacity = profileCapacity
    end
  end

  return packCapacity
end

local function getUsableCapacity(packCapacity, reserve)
  local safeReserve = Reserve.sanitize(reserve)
  local usable = packCapacity * (1 - safeReserve / 100)
  if usable < 10 then usable = packCapacity end
  return usable, safeReserve
end

local function fuelPercentageFromVoltage(voltage, cellCount, batteryConfig, reserve)
  if not cellCount or cellCount <= 0 then return nil end
  ensureCurve()

  local minV = (tonumber(batteryConfig and batteryConfig.vbatmincellvoltage) or 330) / 100
  local fullV = (tonumber(batteryConfig and batteryConfig.vbatfullcellvoltage) or 410) / 100
  local safeReserve = Reserve.sanitize(reserve)

  local voltagePerCell = voltage / cellCount
  if voltagePerCell >= fullV then return 100 end
  if voltagePerCell <= minV then return 0 end

  local sigmoidMin = 3.00
  local sigmoidMax = 4.20
  local scaledV = sigmoidMin + (voltagePerCell - minV) / (fullV - minV) * (sigmoidMax - sigmoidMin)
  scaledV = clamp(scaledV, sigmoidMin, sigmoidMax)
  local index = math.floor((scaledV - sigmoidMin) / 0.01) + 1
  index = clamp(index, 1, #dischargeCurveTable)

  local rawPercent = dischargeCurveTable[index]
  return Reserve.applyPercent(rawPercent, safeReserve)
end

local function isArmed()
  if MspRuntime and type(MspRuntime.getState) == "function" then
    local mspState = MspRuntime.getState()
    if type(mspState) == "table" and mspState.lastArmed ~= nil then
      return mspState.lastArmed == true
    end
  end

  local armFlags = tonumber(getSensor("armflags"))
  if type(armFlags) == "number" then
    if bit32 and type(bit32.btest) == "function" then
      return bit32.btest(armFlags, 1)
    end
    return armFlags ~= 0
  end
  return false
end

local function updateVoltageStability(voltage, now, stableWindowVolts)
  if now < state.stabilizeUntil then
    return false
  end

  local samples = state.voltageSamples
  samples[#samples + 1] = voltage
  if #samples > 5 then
    table.remove(samples, 1)
  end

  if #samples < 5 then
    return false
  end

  local vmin = samples[1]
  local vmax = samples[1]
  for i = 2, #samples do
    local v = samples[i]
    if v < vmin then vmin = v end
    if v > vmax then vmax = v end
  end

  state.voltageStable = (vmax - vmin) <= stableWindowVolts
  return state.voltageStable
end

local function computeCurrentMode(voltage, cellCount, batteryConfig, usableCapacity, stabilized, reserve)
  local consumption = tonumber(getSensor("consumption"))
  if not consumption then
    if not stabilized then return nil, nil end
    return fuelPercentageFromVoltage(voltage, cellCount, batteryConfig, reserve), nil
  end

  if state.startConsumptionOffset == nil then
    -- Wait for stable voltage before estimating starting capacity
    if not stabilized then
       return nil, consumption
    end
    
    local startPercent = fuelPercentageFromVoltage(voltage, cellCount, batteryConfig, reserve) or 100
    state.startFuelPercent = startPercent
    local estimatedUsed = usableCapacity * (1 - startPercent / 100)
    state.startConsumptionOffset = consumption - estimatedUsed
    logSmart("smart capture: voltage=" .. string.format("%.2f", voltage) .. " (cell=" .. string.format("%.2f", voltage/cellCount) .. ") start=" .. tostring(roundInt(startPercent)) .. "% offset=" .. tostring(roundInt(state.startConsumptionOffset)), "info")
  end

  if usableCapacity <= 0 then
    return nil, consumption
  end

  local used = consumption - state.startConsumptionOffset
  local percentUsed = (used / usableCapacity) * 100
  local remaining = clamp(100 - percentUsed, 0, 100)
  return remaining, consumption
end

local function computeVoltageMode(now, voltage, cellCount, batteryConfig, usableCapacity, cfg, armed, reserve)
  if not state.voltageStable then return nil, nil end

  local previousVoltage = state.lastFilteredVoltage
  local dt = 0
  if state.lastTimestamp then
    dt = now - state.lastTimestamp
    if dt < 0 then dt = 0 end
  end

  local filteredVoltage = voltage
  if previousVoltage then
    local maxDrop = dt * cfg.voltageFallPerSecond
    if voltage < previousVoltage then
      filteredVoltage = math.max(voltage, previousVoltage - maxDrop)
    end
  end

  local targetPercent = fuelPercentageFromVoltage(filteredVoltage, cellCount, batteryConfig, reserve)
  if type(targetPercent) ~= "number" then
    return nil, nil
  end

  local targetConsumption = usableCapacity * (100 - targetPercent) / 100
  if state.virtualConsumption == nil then
    state.virtualConsumption = targetConsumption
  elseif armed and dt > 0 then
    local maxIncrease = dt * cfg.fuelDropPerSecond * usableCapacity / 100
    if targetConsumption > state.virtualConsumption then
      state.virtualConsumption = math.min(targetConsumption, state.virtualConsumption + maxIncrease)
    end
  end

  local percent = 100 - (state.virtualConsumption / usableCapacity * 100)
  percent = clamp(percent, 0, 100)

  state.lastFilteredVoltage = filteredVoltage
  state.lastTimestamp = now
  return percent, state.virtualConsumption
end

local function publishTelemetryValue(sid, value, unit, sensorName, cacheValueKey, cachePushKey)
  if type(setTelemetryValue) ~= "function" then return end
  if type(value) ~= "number" then return end

  local now = nowSeconds()
  local stale = (now - (state[cachePushKey] or 0)) >= FORCE_REFRESH_INTERVAL
  local rounded = roundInt(value)
  local previous = state[cacheValueKey]

  if previous ~= rounded or stale then
    setTelemetryValue(sid, 0, 0, rounded, unit, 0, sensorName)
    state[cacheValueKey] = rounded
    state[cachePushKey] = now
  end
end

function Smart.wakeup()
  if not initialized then
    Sensors = loadModule("lib/sensors.lua")
    MspRuntime = loadModule("tasks/msp/runtime.lua")
    Log = loadModule("lib/log.lua")
    ApiVersion = loadModule("lib/api_version.lua")
    Reserve = loadModule("lib/smartfuel_reserve.lua")
    initialized = true
  end
  if not Sensors then return end
  if not Reserve then return end

  local session = getSession()
  if type(session) ~= "table" or session.isConnected ~= true then
    Smart.reset()
    return
  end

  local now = nowSeconds()
  if (now - lastWake) < wakeInterval then
    return
  end
  lastWake = now

  local batteryConfig = session.battery_config
  if type(batteryConfig) ~= "table" then
    return
  end

  local cfg = getSmartConfig(session)
  local sourceMode = tonumber(cfg.source) or 0
  local firmwareSource = tonumber(cfg.firmwareSource)
  local firmwareActive = type(firmwareSource) == "number" and firmwareSource > 0
  local packCapacity = getActivePackCapacity(session, batteryConfig)
  local cellCount = tonumber(batteryConfig.batteryCellCount) or tonumber(getSensor("battery_cell_count")) or 0

  local voltage = tonumber(getSensor("voltage"))
  
  -- Auto-detect cell count if missing
  if not firmwareActive and cellCount <= 0 and voltage and voltage > 2 then
    local maxCellV = (tonumber(batteryConfig.vbatmaxcellvoltage) or 410) / 100
    cellCount = math.max(1, math.floor((voltage / maxCellV) + 0.5))
  end

  local reserve = resolveReservePercent(session, batteryConfig)
  local usableCapacity = getUsableCapacity(packCapacity, reserve)

  if not firmwareActive and (usableCapacity <= 0 or cellCount <= 0) then
    return
  end

  local signature = table.concat({
    tostring(firmwareSource or "nil"),
    tostring(sourceMode),
    tostring(cellCount),
    tostring(packCapacity),
    tostring(reserve),
    tostring((tonumber(batteryConfig.vbatmincellvoltage) or 0)),
    tostring((tonumber(batteryConfig.vbatfullcellvoltage) or 0))
  }, ":")

  if state.batterySignature ~= signature or state.sourceMode ~= sourceMode then
    state.batterySignature = signature
    state.sourceMode = sourceMode
    state.stabilizeUntil = now + cfg.stabilizeDelaySeconds
    resetComputedState()
    logSmart("smart reset source=" .. tostring(sourceMode) .. " cap=" .. tostring(packCapacity), "info")
  end

  local voltage = tonumber(getSensor("voltage"))
  if not firmwareActive then
    if not voltage or voltage <= 2 then
      resetComputedState()
      return
    end
  end

  local stabilized = false
  local armed = false
  if not firmwareActive then
    stabilized = updateVoltageStability(voltage, now, cfg.stableWindowVolts)
    armed = isArmed()
  end

  local fuelPercent = nil
  local smartConsumption = nil
  if firmwareActive then
    local rawFuel, rawFuelSource = readFirmwareFuelValue()
    local rawConsumption = readFirstSourceValue(MIRROR_CONSUMPTION_QUERIES)
    fuelPercent = Reserve.applyPercent(rawFuel, reserve)
    smartConsumption = rawConsumption
    if type(fuelPercent) ~= "number" then
      if (now - (state.lastFirmwareFuelMissingLog or 0)) >= 5.0 then
        state.lastFirmwareFuelMissingLog = now
        logSmart("smart firmware fuel missing mirror/sensor fallback (reserve=" .. tostring(reserve) .. ")", "warn")
      end
    elseif (state.lastFirmwareFuelMissingLog or 0) ~= 0 then
      logSmart("smart firmware fuel recovered from " .. tostring(rawFuelSource) .. " raw=" .. tostring(rawFuel), "info")
      state.lastFirmwareFuelMissingLog = 0
    end
  else
    if sourceMode == 1 then
      fuelPercent, smartConsumption = computeVoltageMode(now, voltage, cellCount, batteryConfig, usableCapacity, cfg, armed, reserve)
    else
      fuelPercent, smartConsumption = computeCurrentMode(voltage, cellCount, batteryConfig, usableCapacity, stabilized, reserve)
    end
  end

  if type(fuelPercent) == "number" then
    publishTelemetryValue(APPID_SMARTFUEL, clamp(fuelPercent, 0, 100), UNIT_PERCENT or 0, SENSOR_NAME_SMARTFUEL, "lastFuelValue", "lastFuelPush")
  end

  if type(smartConsumption) ~= "number" then
    smartConsumption = tonumber(getSensor("consumption"))
  end
  if type(smartConsumption) == "number" and smartConsumption >= 0 then
    publishTelemetryValue(APPID_SMARTCONSUMPTION, math.max(0, smartConsumption), UNIT_MAH or 0, SENSOR_NAME_SMARTCONSUMPTION, "lastConsumptionValue", "lastConsumptionPush")
  end
end

function Smart.reset()
  state.batterySignature = nil
  state.sourceMode = nil
  state.stabilizeUntil = 0
  state.lastFuelValue = nil
  state.lastFuelPush = 0
  state.lastConsumptionValue = nil
  state.lastConsumptionPush = 0
  state.lastFirmwareFuelMissingLog = 0
  resetComputedState()
end

return Smart
