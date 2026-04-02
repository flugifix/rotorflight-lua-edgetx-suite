local Runtime = {}

local SYSTEM_THEME_BASE = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/"
local USER_THEME_BASE = "/SCRIPTS/TOOLS/rfsuite.user/dashboard/"

local function readValue(name, fallback)
  if not getValue then return fallback end
  local ok, value = pcall(getValue, name)
  if not ok or value == nil then return fallback end
  return value
end

local function loadDashboardLib()
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/dashboard/lib.lua", "t")
  if not chunk then return nil end
  local ok, lib = pcall(chunk)
  if not ok or type(lib) ~= "table" then return nil end
  return lib
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
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/preferences.lua", "t")
  if not chunk then return nil end
  local ok, mod = pcall(chunk)
  if not ok or type(mod) ~= "table" or type(mod.load) ~= "function" then
    return nil
  end
  local loadedOk, prefs = pcall(mod.load)
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
    if ok and type(theme) == "table" and type(theme.build) == "function" then
      return theme
    end
  end

  local fallbackChunk = loadScript(SYSTEM_THEME_BASE .. "default/widget.lua", "t")
  if not fallbackChunk then return nil end
  local ok, theme = pcall(fallbackChunk)
  if ok and type(theme) == "table" and type(theme.build) == "function" then
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

  local fuel = readValue("Fuel", state.fuel)
  if type(fuel) == "number" then
    if fuel < 0 then fuel = 0 end
    if fuel > 100 then fuel = 100 end
    state.fuel = fuel
  end

  local voltage = readValue("VFAS", state.voltage)
  if type(voltage) == "number" then
    state.voltage = voltage
  end

  local armState = readValue("ARM", 0)
  if type(armState) == "number" and bit32 then
    state.armed = bit32.btest(armState, 1)
  end
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

function Runtime.new(zone, options)
  local dashboardLib = loadDashboardLib()
  local prefs = loadPreferences() or {}
  local dashboard = (prefs and prefs.dashboard) or {}

  local widget = {
    zone = zone,
    options = options,
    dashboardLib = dashboardLib,
    preferences = prefs,
    themePath = "system/default",
    flightMode = "preflight",
    theme = nil,
    built = false,
    state = {
      armed = false,
      hadArmedFlight = false,
      rpm = 0,
      profile = 1,
      flights = 0,
      lq = 0,
      fuel = 100,
      voltage = 0,
      themeConfig = { v_min = 18.0, v_max = 25.2 }
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
  end

  function widget.update(self, newOptions)
    self.options = newOptions
    self.built = false
  end

  function widget.refresh(self)
    readTelemetry(self.state)
    local nextMode = computeFlightMode(self.state)
    if nextMode ~= self.flightMode then
      self.flightMode = nextMode
      reloadActiveTheme(self)
    elseif not self.theme then
      reloadActiveTheme(self)
    end

    if not self.theme then return end
    if not self.built then
      lvgl.clear()
      local children = self.theme.build(self.zone, self.state)
      if type(children) ~= "table" then return end
      lvgl.build(children)
      self.built = true
    end
  end

  function widget.background(self)
    readTelemetry(self.state)
    local nextMode = computeFlightMode(self.state)
    if nextMode ~= self.flightMode then
      self.flightMode = nextMode
      reloadActiveTheme(self)
    end
    return 0
  end

  reloadActiveTheme(widget)
  return widget
end

return Runtime
