local Runtime = {}

local SYSTEM_THEME_BASE = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/"
local USER_THEME_BASE = "/SCRIPTS/TOOLS/rfsuite.user/dashboard/"
local AUDIO_LOG_FORCE = false

local function scriptExists(path)
  if type(path) ~= "string" or path == "" then return false end
  local f = io.open(path, "r")
  if not f then return false end
  io.close(f)
  return true
end

local function loadModuleChunk(basePath)
  if type(loadScript) ~= "function" then return nil end

  local luaPath = basePath .. ".lua"
  if scriptExists(luaPath) then
    local chunk = loadScript(luaPath, "t")
    if type(chunk) == "function" then return chunk end
  end

  local luacPath = basePath .. ".luac"
  if scriptExists(luacPath) then
    local chunk = loadScript(luacPath)
    if type(chunk) == "function" then return chunk end
  end

  return nil
end

local loadLogModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/lib/log")
local Log = nil
if type(loadLogModule) == "function" then
  local ok, mod = pcall(loadLogModule)
  if ok and type(mod) == "table" then
    Log = mod
  end
end

local loadPreferencesModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/lib/preferences")
local PreferencesModule = nil
if type(loadPreferencesModule) == "function" then
  local ok, mod = pcall(loadPreferencesModule)
  if ok and type(mod) == "table" and type(mod.load) == "function" then
    PreferencesModule = mod
  end
end

local loadDashboardAudioModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/audio")
local DashboardAudio = nil
if type(loadDashboardAudioModule) == "function" then
  local ok, mod = pcall(loadDashboardAudioModule)
  if ok and type(mod) == "table" and type(mod.process) == "function" then
    DashboardAudio = mod
  end
end

local PID_PROFILE_SOURCES = { "PID#", "PIDP", "PidP", "PIDP1", "PID Profile", "PID" }
local RATE_PROFILE_SOURCES = { "RTE#", "RateP", "RTPR", "Rate Profile", "Rate" }
local BATTERY_PROFILE_SOURCES = { "BatP", "battery_profile", "Battery Profile", "BatProfile" }
local ARM_SOURCES = { "ARM", "Arm", "ARMF", "ArmF" }
local GOVERNOR_SOURCES = { "Gov", "Governor" }
local FUEL_SOURCES = { "Fuel", "Bat%" }
local VOLTAGE_SOURCES = { "VFAS", "Vbat", "voltage", "VBAT" }
local ESC_TEMP_SOURCES = { "ESC_TMP", "TescT", "ESC Temp" }

local SIM_SENSOR_PATHS = {
  "/SCRIPTS/TOOLS/rfsuite-core/sim/sensors/",
  "/SCRIPTS/TOOLS/rfsuite.user/sim/sensors/"
}

local simValueCache = {}
local simSensorAliases = {
  ["PIDP"] = "PID#",
  ["PID Profile"] = "PID#",
  ["PID"] = "PID#",
  ["RateP"] = "RTE#",
  ["RTPR"] = "RTE#",
  ["Rate Profile"] = "RTE#",
  ["Rate"] = "RTE#",
  ["RPM"] = "Hspd",
  ["Fuel"] = "Bat%",
  ["ESC_TMP"] = "TescT",
  ["VFAS"] = "Vbat",
  ["VBAT"] = "Vbat",
  ["Vbat"] = "voltage",
  ["voltage"] = "Vbat"
}

local function normalizeSimSensorValue(name, value)
  if type(value) ~= "number" then return value end
  if name == "Vbat" or name == "VFAS" then
    return value / 100
  end
  return value
end

local utils = {}

local function isTruthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

local function shouldLogAudio(self)
  if AUDIO_LOG_FORCE then return true end
  local prefs = self and self.preferences
  local general = prefs and prefs.general
  return isTruthy(general and general.developer_tools)
end

function utils.log(self, msg, level)
  if Log and type(Log.emit) == "function" then
    Log.emit("rfsuite.audio", msg, level, shouldLogAudio(self))
    return
  end
  if shouldLogAudio(self) and type(print) == "function" then
    print("[rfsuite.audio][" .. tostring(level or "debug") .. "] " .. tostring(msg))
  end
end

local function audioLog(self, msg, level)
  utils.log(self, msg, level)
end

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

local function isSimulator()
  if type(getVersion) ~= "function" then return false end
  local ok, _, fw = pcall(getVersion)
  if not ok or type(fw) ~= "string" then return false end
  return string.sub(string.lower(fw), -4) == "simu"
end

local function readSimSensorValue(name)
  if type(name) ~= "string" or name == "" then return nil end

  local candidates = { name }
  local alias = simSensorAliases[name]
  if type(alias) == "string" and alias ~= "" and alias ~= name then
    candidates[#candidates + 1] = alias
  end

  for p = 1, #SIM_SENSOR_PATHS do
    local base = SIM_SENSOR_PATHS[p]
    for i = 1, #candidates do
      local filePath = base .. candidates[i] .. ".lua"
      local now = nowSeconds()
      local cached = simValueCache[filePath]
      if cached and (now - (cached.t or 0)) <= 0.05 then
        if cached.v ~= nil then
          return normalizeSimSensorValue(candidates[i], cached.v)
        end
      else
        local value = nil
        local f = io.open(filePath, "r")
        if f then
          local content = io.read(f, 64)
          io.close(f)
          if type(content) == "string" then
            local num = string.match(content, "return%s+([%+%-]?%d+%.?%d*)")
            if not num then
              num = string.match(content, "([%+%-]?%d+%.?%d*)")
            end
            if num then
              value = tonumber(num)
            end
          end
        end
        simValueCache[filePath] = { t = now, v = value }
        if value ~= nil then
          return normalizeSimSensorValue(candidates[i], value)
        end
      end
    end
  end

  return nil
end

local function readValue(name, fallback)
  if isSimulator() then
    local simValue = readSimSensorValue(name)
    if simValue ~= nil then
      return simValue
    end
  end

  if not getValue then return fallback end
  local ok, value = pcall(getValue, name)
  if not ok or value == nil then return fallback end
  return value
end

local function processAudioEvents(self)
  if DashboardAudio and type(DashboardAudio.process) == "function" then
    DashboardAudio.process(self, {
      log = function(msg, level)
        audioLog(self, msg, level)
      end
    })
    return
  end

  if self and self.audioState and not self.audioState.initialized then
    self.audioState.initialized = true
  end
end

local function readFirstValue(names, fallback)
  if type(names) ~= "table" then
    return fallback
  end

  for i = 1, #names do
    local value = readValue(names[i], nil)
    if value ~= nil then
      return value
    end
  end

  return fallback
end

local function readFirstNumber(names, fallback)
  if type(names) ~= "table" then
    return fallback
  end

  for i = 1, #names do
    local value = readValue(names[i], nil)
    if type(value) == "number" then
      return value
    end
    if type(value) == "string" then
      local numeric = tonumber(value)
      if type(numeric) == "number" then
        return numeric
      end
    end
  end

  return fallback
end

local function roundInt(value, fallback)
  if type(value) ~= "number" then
    return fallback
  end
  return math.floor(value + 0.5)
end

local function updateDerivedFlightState(state)
  local now = nowSeconds()
  local lastTick = state.lastTickAt or now
  local delta = now - lastTick
  if delta < 0 or delta > 5 then
    delta = 0
  end
  state.lastTickAt = now

  local wasArmed = state.wasArmed == true
  local isArmed = state.armed == true

  if isArmed and not wasArmed then
    state.currentFlightSeconds = 0
    state.currentFlightMinVoltage = nil
    state.currentFlightMinLq = nil
    state.hadArmedFlight = true
  end

  if isArmed then
    state.currentFlightSeconds = (state.currentFlightSeconds or 0) + delta
    state.totalFlightSeconds = (state.totalFlightSeconds or 0) + delta

    if type(state.voltage) == "number" and state.voltage > 0 then
      local currentMinVoltage = state.currentFlightMinVoltage
      if currentMinVoltage == nil or state.voltage < currentMinVoltage then
        state.currentFlightMinVoltage = state.voltage
      end
    end

    if type(state.lq) == "number" and state.lq > 0 then
      local currentMinLq = state.currentFlightMinLq
      if currentMinLq == nil or state.lq < currentMinLq then
        state.currentFlightMinLq = state.lq
      end
    end
  elseif wasArmed then
    state.lastFlightSeconds = state.currentFlightSeconds or 0
    if (state.currentFlightSeconds or 0) >= 1 then
      state.flights = (state.flights or 0) + 1
    end
    state.lastMinVoltage = state.currentFlightMinVoltage
    state.lastMinLq = state.currentFlightMinLq
    state.currentFlightSeconds = 0
    state.currentFlightMinVoltage = nil
    state.currentFlightMinLq = nil
  end

  if isArmed then
    state.flightSeconds = state.currentFlightSeconds or 0
  else
    state.flightSeconds = state.lastFlightSeconds or 0
  end

  state.wasArmed = isArmed
end

local function loadDashboardLib()
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/dashboard/lib.lua", "t")
  if not chunk then return nil end
  local ok, lib = pcall(chunk)
  if not ok or type(lib) ~= "table" then return nil end
  return lib
end

local function loadDashboardEngine()
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/engine.lua", "t")
  if not chunk then return nil end
  local ok, engine = pcall(chunk)
  if not ok or type(engine) ~= "table" then return nil end
  return engine
end

local function parseThemePath(raw)
  if type(raw) ~= "string" or raw == "" then
    return "system", "default"
  end
  local slash = string.find(raw, "/", 1, true)
  if not slash then
    return "system", "default"
  end
  local source = string.sub(raw, 1, slash - 1)
  local folder = string.sub(raw, slash + 1)
  if source == "" or folder == "" then
    return "system", "default"
  end
  return source, folder
end

local function loadPreferences()
  if not PreferencesModule or type(PreferencesModule.load) ~= "function" then
    return nil
  end
  local loadedOk, prefs = pcall(PreferencesModule.load)
  if not loadedOk or type(prefs) ~= "table" then
    return nil
  end
  return prefs
end

local function loadThemeInit(themePath)
  local source, folder = parseThemePath(themePath)
  local base = source == "user" and USER_THEME_BASE or SYSTEM_THEME_BASE
  local initChunk = loadScript(base .. folder .. "/init.lua", "t")
  if not initChunk then return nil, base, folder end
  local ok, initTable = pcall(initChunk)
  if not ok or type(initTable) ~= "table" then return nil, base, folder end
  return initTable, base, folder
end

local function loadThemeModuleForState(themePath, flightMode)
  local initTable, base, folder = loadThemeInit(themePath)
  local stateKey = (flightMode == "inflight" or flightMode == "postflight") and flightMode or "preflight"

  local stateScript = nil
  if initTable and type(initTable[stateKey]) == "string" and initTable[stateKey] ~= "" then
    stateScript = initTable[stateKey]
  end

  local scriptPath = nil
  if stateScript then
    scriptPath = base .. folder .. "/" .. stateScript
  else
    scriptPath = base .. folder .. "/widget.lua"
  end

  local chunk = loadScript(scriptPath, "t")
  if chunk then
    local ok, theme = pcall(chunk)
    if ok and type(theme) == "table" and (
      type(theme.build) == "function" or
      type(theme.layout) == "table" or
      type(theme.boxes) == "table" or
      type(theme.boxes) == "function"
    ) then
      return theme
    end
  end

  local fallbackChunk = loadScript(SYSTEM_THEME_BASE .. "default/widget.lua", "t")
  if not fallbackChunk then return nil end
  local ok, theme = pcall(fallbackChunk)
  if ok and type(theme) == "table" and (
    type(theme.build) == "function" or
    type(theme.layout) == "table" or
    type(theme.boxes) == "table" or
    type(theme.boxes) == "function"
  ) then
    return theme
  end
  return nil
end

local function resolveThemePathForState(dashboard, flightMode)
  local modelOverride = dashboard and dashboard.model_override == true
  local key = "theme_preflight"
  local modelKey = "model_theme_preflight"

  if flightMode == "inflight" then
    key = "theme_inflight"
    modelKey = "model_theme_inflight"
  elseif flightMode == "postflight" then
    key = "theme_postflight"
    modelKey = "model_theme_postflight"
  end

  local modelValue = modelOverride and dashboard and dashboard[modelKey] or nil
  if type(modelValue) == "string" and modelValue ~= "" and modelValue ~= "nil" then
    return modelValue
  end

  local globalValue = dashboard and dashboard[key] or nil
  if type(globalValue) == "string" and globalValue ~= "" then
    return globalValue
  end

  return "system/default"
end

local function readTelemetry(state)
  state.rpm = readValue("RPM", state.rpm)
  state.lq = readValue("RQly", state.lq)
  state.profile = roundInt(readFirstValue(PID_PROFILE_SOURCES, state.profile), state.profile or 1)
  state.rateProfile = roundInt(readFirstValue(RATE_PROFILE_SOURCES, state.rateProfile), state.rateProfile or 1)
  state.batteryProfile = roundInt(readFirstValue(BATTERY_PROFILE_SOURCES, state.batteryProfile), state.batteryProfile or 1)
  state.armFlags = roundInt(readFirstValue(ARM_SOURCES, state.armFlags), state.armFlags or 0)
  state.governor = roundInt(readFirstValue(GOVERNOR_SOURCES, state.governor), state.governor or 0)
  state.escTemp = roundInt(readFirstValue(ESC_TEMP_SOURCES, state.escTemp), state.escTemp or 0)

  local fuel = readFirstValue(FUEL_SOURCES, state.fuel)
  if type(fuel) == "number" then
    if fuel < 0 then fuel = 0 end
    if fuel > 100 then fuel = 100 end
    state.fuel = fuel
  end

  local voltage = readFirstNumber(VOLTAGE_SOURCES, state.voltage)
  if type(voltage) == "number" then
    state.voltage = voltage
  end

  local armState = readFirstValue(ARM_SOURCES, state.armFlags or 0)
  if type(armState) == "number" and bit32 then
    state.armed = bit32.btest(armState, 1)
  elseif type(armState) == "number" then
    state.armed = armState ~= 0
  end

  updateDerivedFlightState(state)
end

local function computeFlightMode(state)
  if state.armed == true then
    state.hadArmedFlight = true
    return "inflight"
  end
  if state.hadArmedFlight == true then
    return "postflight"
  end
  return "preflight"
end

local function reloadPreferencesIfNeeded(self, force)
  local now = nowSeconds()
  if not force and (now - (self.preferencesLastLoadedAt or 0)) < 0.5 then
    return
  end

  local prefs = loadPreferences()
  if type(prefs) == "table" then
    self.preferences = prefs
  end

  self.preferencesLastLoadedAt = now
end

function Runtime.new(zone, options)
  local dashboardLib = loadDashboardLib()
  local dashboardEngine = loadDashboardEngine()
  local prefs = loadPreferences() or {}
  local dashboard = (prefs and prefs.dashboard) or {}

  local widget = {
    zone = zone,
    options = options,
    dashboardLib = dashboardLib,
    dashboardEngine = dashboardEngine,
    preferences = prefs,
    preferencesLastLoadedAt = 0,
    themePath = "system/default",
    flightMode = "preflight",
    theme = nil,
    built = false,
    renderKey = nil,
    boxSources = {},
    state = {
      armed = false,
      hadArmedFlight = false,
      rpm = 0,
      profile = 1,
      rateProfile = 1,
      batteryProfile = 1,
      armFlags = 0,
      governor = 0,
      escTemp = 0,
      flights = 0,
      lq = 0,
      fuel = 100,
      voltage = 0,
      flightSeconds = 0,
      lastFlightSeconds = 0,
      totalFlightSeconds = 0,
      lastMinVoltage = nil,
      lastMinLq = nil,
      themeConfig = { v_min = 18.0, v_max = 25.2 }
    },
    audioState = {
      initialized = false,
      nextAllowedAt = 0,
      modelAnnounced = false,
      lastFuelCallout = nil,
      lowFuelActive = false,
      lowFuelLastAt = 0,
      lowFuelRepeatCount = 0,
      lastAlertAt = {
        voltage = 0,
        esc_temperature = 0
      },
      lastValues = {
        arming_flags = nil,
        governor_state = nil,
        pid_profile = nil,
        rate_profile = nil,
        battery_profile = nil
      },
      pendingValues = {
        pid_profile = nil,
        rate_profile = nil,
        battery_profile = nil
      },
      lastEnabled = {
        governor_state = nil
      }
    }
  }

  local function reloadActiveTheme(self)
    local selectedTheme = resolveThemePathForState((self.preferences and self.preferences.dashboard) or {}, self.flightMode)
    local nextConfig = { v_min = 18.0, v_max = 25.2 }
    if self.dashboardLib and self.dashboardLib.getThemeConfig then
      nextConfig = self.dashboardLib.getThemeConfig(self.preferences, selectedTheme, nextConfig)
    end

    self.themePath = selectedTheme
    self.state.themeConfig = nextConfig
    self.theme = loadThemeModuleForState(selectedTheme, self.flightMode)
    self.built = false
    self.renderKey = nil

    local sources = {}
    if self.theme then
      local parsedBoxes = nil
      if type(self.theme.boxes) == "function" then
        local ok, b = pcall(self.theme.boxes, nil, self.state)
        if ok and type(b) == "table" then parsedBoxes = b end
      elseif type(self.theme.boxes) == "table" then
        parsedBoxes = self.theme.boxes
      end
      if parsedBoxes then
        local seen = {}
        for i = 1, #parsedBoxes do
          local src = parsedBoxes[i].source
          if type(src) == "string" and not seen[src] then
            seen[src] = true
            sources[#sources + 1] = src
          end
        end
      end
    end
    self.boxSources = sources
  end

  function widget.update(self, newOptions)
    self.options = newOptions
    self.built = false
  end

  function widget.refresh(self)
    reloadPreferencesIfNeeded(self, false)
    self.state.zoneW = self.zone and self.zone.w or 0
    self.state.zoneH = self.zone and self.zone.h or 0
    readTelemetry(self.state)
    processAudioEvents(self)
    local nextMode = computeFlightMode(self.state)
    local selectedTheme = resolveThemePathForState((self.preferences and self.preferences.dashboard) or {}, nextMode)

    if nextMode ~= self.flightMode then
      self.flightMode = nextMode
      reloadActiveTheme(self)
    elseif selectedTheme ~= self.themePath then
      reloadActiveTheme(self)
    elseif not self.theme then
      reloadActiveTheme(self)
    end

    if not self.theme then return end

    local nextRenderKey = nil
    if type(self.theme.renderKey) == "function" then
      nextRenderKey = self.theme.renderKey(self.zone, self.state)
    elseif self.dashboardEngine and (type(self.theme.layout) == "table" or type(self.theme.boxes) == "table" or type(self.theme.boxes) == "function") then
      nextRenderKey = self.dashboardEngine.renderKey(self.state, self.boxSources)
    end

    if nextRenderKey ~= self.renderKey then
      self.renderKey = nextRenderKey
      self.built = false
    end

    if not self.built then
      lvgl.clear()
      local children = nil
      if type(self.theme.build) == "function" then
        children = self.theme.build(self.zone, self.state)
      elseif self.dashboardEngine and (type(self.theme.layout) == "table" or type(self.theme.boxes) == "table" or type(self.theme.boxes) == "function") then
        children = self.dashboardEngine.build(self.zone, self.state, self.theme)
      end
      if type(children) ~= "table" then return end
      lvgl.build(children)
      self.built = true
    end
  end

  function widget.background(self)
    reloadPreferencesIfNeeded(self, false)
    readTelemetry(self.state)
    processAudioEvents(self)
    local nextMode = computeFlightMode(self.state)
    local selectedTheme = resolveThemePathForState((self.preferences and self.preferences.dashboard) or {}, nextMode)

    if nextMode ~= self.flightMode then
      self.flightMode = nextMode
      reloadActiveTheme(self)
    elseif selectedTheme ~= self.themePath then
      reloadActiveTheme(self)
    end
    return 0
  end

  reloadActiveTheme(widget)
  return widget
end

return Runtime
