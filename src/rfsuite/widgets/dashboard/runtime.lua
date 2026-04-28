local Runtime = {}

local SYSTEM_THEME_BASE = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/"
local USER_THEME_BASE = "/SCRIPTS/TOOLS/rfsuite.user/dashboard/"
local AUDIO_LOG_FORCE = false
local POSTFLIGHT_HOLD_SECONDS = 20
local SPLASH_READY_HOLD_SECONDS = 1.0

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

local loadDashboardAudioModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/lib/audio")
local DashboardAudio = nil
if type(loadDashboardAudioModule) == "function" then
  local ok, mod = pcall(loadDashboardAudioModule)
  if ok and type(mod) == "table" and type(mod.process) == "function" then
    DashboardAudio = mod
  end
end

local loadDashboardSplashModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/splash")
local DashboardSplash = nil
if type(loadDashboardSplashModule) == "function" then
  local ok, mod = pcall(loadDashboardSplashModule)
  if ok and type(mod) == "table" and type(mod.build) == "function" then
    DashboardSplash = mod
  end
end

local loadMspRuntimeModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/tasks/msp/runtime")
local MspRuntime = nil
if type(loadMspRuntimeModule) == "function" then
  local ok, mod = pcall(loadMspRuntimeModule)
  if ok and type(mod) == "table" then
    MspRuntime = mod
  end
end

local loadI18nModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/i18n/init")
local I18nModule = nil
if type(loadI18nModule) == "function" then
  local ok, mod = pcall(loadI18nModule)
  if ok and type(mod) == "table" then
    I18nModule = mod
  end
end

local loadSensorsModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/lib/sensors")
local Sensors = nil
if type(loadSensorsModule) == "function" then
  local ok, mod = pcall(loadSensorsModule)
  if ok and type(mod) == "table" then Sensors = mod end
end

local RSS1_SOURCES = { "1RSS", "RSS1", "rssi1" }
local RSS2_SOURCES = { "2RSS", "RSS2", "rssi2" }

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
  end
end

local function audioLog(self, msg, level)
  utils.log(self, msg, level)
end

local function widgetLog(self, msg, level)
  if Log and type(Log.emit) == "function" then
    Log.emit("rfsuite.widget", msg, level or "debug", true)
  end
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

local function readValue(name, fallback)
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

local loadEventsModule = loadModuleChunk("/SCRIPTS/TOOLS/rfsuite-core/tasks/events/runtime")
local EventsRuntime = nil
if type(loadEventsModule) == "function" then
  local ok, mod = pcall(loadEventsModule)
  if ok and type(mod) == "table" then
    EventsRuntime = mod
  end
end

local function tickMspRuntime(self)
  if not MspRuntime then
    return
  end

  if not self.mspAttached and type(MspRuntime.attach) == "function" then
    MspRuntime.attach("dashboard-widget")
    self.mspAttached = true
  end

  if type(MspRuntime.tick) ~= "function" then
    return
  end

  MspRuntime.tick()
  
  if EventsRuntime and type(EventsRuntime.wakeup) == "function" then
    pcall(EventsRuntime.wakeup)
  end
end

local function buildConnectionSplash(zone, statusLine, title)
  if DashboardSplash and type(DashboardSplash.build) == "function" then
    return DashboardSplash.build(zone, statusLine, title)
  end

  local w = (zone and zone.w) or LCD_W or 320
  local h = (zone and zone.h) or LCD_H or 172
  return {
    {
      type = "rectangle",
      x = 0,
      y = 0,
      w = w,
      h = h,
      color = COLOR_THEME_PRIMARY2,
      filled = true
    }
  }
end

local function resolvePostflightHoldSeconds(prefs, fallback)
  local defaultValue = tonumber(fallback) or POSTFLIGHT_HOLD_SECONDS
  local general = type(prefs) == "table" and prefs.general or nil
  local raw = general and general.postflight_hold_seconds or defaultValue
  local value = tonumber(raw) or defaultValue
  if value < 0 then value = 0 end
  if value > 120 then value = 120 end
  return math.floor(value + 0.5)
end

local function updateConnectionState(self)
  local runtimeState = nil
  if MspRuntime and type(MspRuntime.getState) == "function" then
    runtimeState = MspRuntime.getState()
  elseif Rf2Runtime and type(Rf2Runtime.getState) == "function" then
    runtimeState = Rf2Runtime.getState()
  end
  local connected = type(runtimeState) == "table" and runtimeState.lastConnected == true
  local hasVoltage = type(self.state.voltage) == "number" and self.state.voltage > 0
  local hasFuel = type(self.state.fuel) == "number" and self.state.fuel >= 0
  local hasLq = type(self.state.lq) == "number" and self.state.lq ~= 0
  local hasRss1 = type(self.state.rss1) == "number" and self.state.rss1 ~= 0
  local hasRss2 = type(self.state.rss2) == "number" and self.state.rss2 ~= 0
  local batteryReady = hasVoltage or hasFuel
  local rfReady = hasLq or hasRss1 or hasRss2
  local rawReady = connected and batteryReady and rfReady
  local now = nowSeconds()

  if rawReady then
    if not self.readySince then
      self.readySince = now
    end
  else
    self.readySince = nil
  end

  local ready = rawReady and self.readySince ~= nil and (now - self.readySince) >= SPLASH_READY_HOLD_SECONDS
  local t = (self.i18n and type(self.i18n.t) == "function") and self.i18n.t or nil

  local statusLine = nil
  if not connected then
    statusLine = (t and t("widgets.dashboard.waiting_for_msp_link")) or "Waiting for MSP link"
  elseif not rfReady then
    statusLine = (t and t("widgets.dashboard.waiting_for_receiver_telemetry")) or "Waiting for receiver telemetry (1RSS/2RSS)"
  elseif not batteryReady then
    statusLine = (t and t("widgets.dashboard.waiting_for_battery_telemetry")) or "Waiting for battery telemetry"
  elseif not ready then
    statusLine = (t and t("widgets.dashboard.connected_starting")) or "Connected, starting dashboard..."
  end

  if self.connectionReady ~= ready then
    self.connectionReady = ready
    self.built = false
    self.renderKey = nil
    if ready then
      widgetLog(self, "FBL connected and telemetry initialized", "info")
    else
      widgetLog(self, "FBL not ready yet", "info")
      if self.audioState then
        self.audioState.initialized = false
      end
    end
  end

  self.state.fblConnected = connected
  self.state.connectionReady = ready
  return ready, statusLine
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
    state.lastDisarmAt = now
    state.hadArmedFlight = true
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
  if modelValue and modelValue ~= "" and modelValue ~= "nil" then
    return modelValue
  end

  local globalValue = dashboard and dashboard[key] or nil
  if globalValue and globalValue ~= "" then
    return globalValue
  end

  return "system/default"
end

local function readTelemetry(state)
  if Sensors and type(Sensors.getValue) == "function" then
    state.rpm = Sensors.getValue("rpm") or state.rpm
    state.lq = Sensors.getValue("link") or state.lq
    state.profile = roundInt(Sensors.getValue("pid_profile") or state.profile, state.profile or 1)
    state.rateProfile = roundInt(Sensors.getValue("rate_profile") or state.rateProfile, state.rateProfile or 1)
    state.batteryProfile = roundInt(Sensors.getValue("battery_profile") or state.batteryProfile, state.batteryProfile or 1)
    state.armFlags = roundInt(Sensors.getValue("armflags") or state.armFlags, state.armFlags or 0)
    state.governor = roundInt(Sensors.getValue("governor") or state.governor, state.governor or 0)
    state.escTemp = roundInt(Sensors.getValue("temp_esc") or state.escTemp, state.escTemp or 0)

    local fuel = Sensors.getValue("fuel")
    if type(fuel) == "number" then
      if fuel < 0 then fuel = 0 end
      if fuel > 100 then fuel = 100 end
      state.fuel = fuel
    end

    local voltage = Sensors.getValue("voltage")
    if type(voltage) == "number" then
      state.voltage = voltage
    end

    local armState = Sensors.getValue("armflags")
    if type(armState) == "number" and bit32 then
      state.armed = bit32.btest(armState, 1)
    elseif type(armState) == "number" then
      state.armed = armState ~= 0
    end
  end

  state.rss1 = readFirstNumber(RSS1_SOURCES, state.rss1)
  state.rss2 = readFirstNumber(RSS2_SOURCES, state.rss2)

  updateDerivedFlightState(state)
end

local function computeFlightMode(state)
  if state.armed == true then
    state.hadArmedFlight = true
    return "inflight"
  end
  if state.hadArmedFlight == true then
    local disarmAt = tonumber(state.lastDisarmAt)
    local now = nowSeconds()
    if disarmAt and (now - disarmAt) <= (tonumber(state.postflightHoldSeconds) or POSTFLIGHT_HOLD_SECONDS) then
      return "postflight"
    end
    state.hadArmedFlight = false
    return "preflight"
  end
  return "preflight"
end

local function publishPreferencesToGlobal(prefs)
  if type(_G) ~= "table" then return end
  _G.rfsuite = _G.rfsuite or {}
  _G.rfsuite.preferences = prefs or {}
end

local function reloadPreferencesIfNeeded(self, force)
  local now = nowSeconds()
  if not force and (now - (self.preferencesLastLoadedAt or 0)) < 0.5 then
    return
  end

  local prefs = loadPreferences()
  if type(prefs) == "table" then
    local prevLang = self.preferences and self.preferences.general and self.preferences.general.language
    local newLang = prefs.general and prefs.general.language
    if prevLang ~= newLang then
      self.built = false
    end
    self.preferences = prefs
    publishPreferencesToGlobal(prefs)
    -- Update i18n context when language changes
    if I18nModule and prevLang ~= newLang then
      if self.i18n and type(self.i18n.setLocale) == "function" then
        pcall(self.i18n.setLocale, newLang)
      else
        local ok, ctx = pcall(I18nModule.new, newLang)
        if ok and type(ctx) == "table" then self.i18n = ctx end
      end
    end
      -- expose i18n on the runtime state so theme renderers can access it
      if self.i18n then
        if type(self.state) ~= "table" then self.state = {} end
        self.state.i18n = self.i18n
      end
    if self.state then
      self.state.postflightHoldSeconds = resolvePostflightHoldSeconds(prefs, self.state.postflightHoldSeconds)
    end
  end

  self.preferencesLastLoadedAt = now
end

function Runtime.new(zone, options)
  local dashboardLib = loadDashboardLib()
  local dashboardEngine = loadDashboardEngine()
  local prefs = loadPreferences() or {}
  publishPreferencesToGlobal(prefs)
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
      fblConnected = false,
      connectionReady = false,
      rpm = 0,
      profile = 1,
      rateProfile = 1,
      batteryProfile = 1,
      armFlags = 0,
      governor = 0,
      escTemp = 0,
      flights = 0,
      lq = 0,
      rss1 = 0,
      rss2 = 0,
      fuel = 100,
      voltage = 0,
      flightSeconds = 0,
      lastFlightSeconds = 0,
      totalFlightSeconds = 0,
      lastMinVoltage = nil,
      lastMinLq = nil,
      lastDisarmAt = nil,
      postflightHoldSeconds = resolvePostflightHoldSeconds(prefs, POSTFLIGHT_HOLD_SECONDS),
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
      -- lastAlertAt wird nicht mehr hier initialisiert, sondern nur noch lazy in Audio
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
    },
    connectionReady = false,
    statusLine = "Waiting for MSP link",
    readySince = nil,
    mspAttached = false,
    mspLastTick = 0
  }

  -- Initialize i18n context for the widget using loaded preferences
  if I18nModule and type(I18nModule.new) == "function" then
    local locale = (prefs and prefs.general and prefs.general.language) or nil
    local ok, ctx = pcall(I18nModule.new, locale)
    if ok and type(ctx) == "table" then
      widget.i18n = ctx
    end
  end
  -- ensure renderers can access the same i18n via state
  if widget.i18n then
    widget.state.i18n = widget.i18n
  end

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
    local now = nowSeconds()
    if not self._lastRefreshTick then self._lastRefreshTick = 0 end
    if (now - self._lastRefreshTick) < 0.1 then return end
    self._lastRefreshTick = now

    -- Set event context to 'widget' before events wakeup
    if type(_G) == "table" then
      _G.rfsuite = _G.rfsuite or {}
      _G.rfsuite.session = _G.rfsuite.session or {}
      _G.rfsuite.session.event_context = "widget"
    end
    tickMspRuntime(self)
    -- Clear event_context immediately after events
    if type(_G) == "table" and _G.rfsuite and _G.rfsuite.session then
      _G.rfsuite.session.event_context = nil
    end
    reloadPreferencesIfNeeded(self, false)
    self.state.zoneW = self.zone and self.zone.w or 0
    self.state.zoneH = self.zone and self.zone.h or 0
    readTelemetry(self.state)
    -- Update flightcount from session if available (from MSP)
    if type(_G) == "table" and _G.rfsuite and _G.rfsuite.session and type(_G.rfsuite.session.flightcount) == "number" then
      self.state.flights = _G.rfsuite.session.flightcount
    end
    local nextMode = computeFlightMode(self.state)
    local ready, statusLine = updateConnectionState(self)

    if ready then
      processAudioEvents(self)
    end

    if not ready and nextMode ~= "postflight" then
      local splashKey = "splash|" .. tostring(statusLine or "") .. "|" .. tostring(self.state.zoneW) .. "x" .. tostring(self.state.zoneH)
      if self.renderKey ~= splashKey then
        self.renderKey = splashKey
        self.built = false
      end

      if not self.built then
        local t = (self.i18n and type(self.i18n.t) == "function") and self.i18n.t or nil
        local title = (t and t("widgets.dashboard.connecting_fbl")) or "Connecting FBL..."
        lvgl.clear()
        lvgl.build(buildConnectionSplash(self.zone, statusLine, title))
        self.built = true
      end
      return
    end

    local selectedTheme = resolveThemePathForState((self.preferences and self.preferences.dashboard) or {}, nextMode)

    if nextMode ~= self.flightMode then
      self.flightMode = nextMode
      reloadActiveTheme(self)
      return
    elseif selectedTheme ~= self.themePath then
      reloadActiveTheme(self)
      return
    elseif not self.theme then
      reloadActiveTheme(self)
      return
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
      -- Ausführung auf den nächsten Tick verschieben, um das CPU Limit beim Zeichnen zu umgehen
      return
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
    local now = nowSeconds()
    if not self._lastBgTick then self._lastBgTick = 0 end
    if (now - self._lastBgTick) < 0.1 then return 0 end
    self._lastBgTick = now

    -- Set event context to 'widget' before events wakeup
    if type(_G) == "table" then
      _G.rfsuite = _G.rfsuite or {}
      _G.rfsuite.session = _G.rfsuite.session or {}
      _G.rfsuite.session.event_context = "widget"
    end
    tickMspRuntime(self)
    -- Clear event_context immediately after events
    if type(_G) == "table" and _G.rfsuite and _G.rfsuite.session then
      _G.rfsuite.session.event_context = nil
    end
    reloadPreferencesIfNeeded(self, false)
    readTelemetry(self.state)
    local ready = updateConnectionState(self)
    if ready then
      processAudioEvents(self)
    end
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
