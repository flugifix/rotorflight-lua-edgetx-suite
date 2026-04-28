--[[
  Central sensor definition for RFSuite dashboard
  Based on RF2 telemetry sensor schema (4-character names)
  Provides unified mapping for simulator and hardware
]]--

local Sensors = {}
local Log = nil
do
  local okLoad, chunk = pcall(loadScript, "/SCRIPTS/TOOLS/rfsuite-core/lib/log.lua", "t")
  if okLoad and type(chunk) == "function" then
    local okMod, mod = pcall(chunk)
    if okMod and type(mod) == "table" and type(mod.emit) == "function" then
      Log = mod
    end
  end
end
local SIM_SENSOR_PATHS = {
  "/SCRIPTS/TOOLS/rfsuite-core/sim/sensors/",
  "/SCRIPTS/TOOLS/rfsuite.user/sim/sensors/",
}
local SIM_FILE_ALIASES = {
  ["PID#"] = "pid_profile",
  ["RTE#"] = "rate_profile",
  ["BatP"] = "battery_profile",
  ["Bat%"] = "fuel",
  ["RQly"] = "link",
  ["Vbat"] = "voltage",
  ["Hspd"] = "rpm",
  ["TescT"] = "temp_esc",
  ["TmcuT"] = "temp_mcu",
  ["Thr%"] = "throttle_percent",
  ["Cel#"] = "cell_count",
  ["Alt"] = "altitude",
}

local debugEnabled = false
local loggedSimulatorState = false
local loggedSources = {}
local simValueCache = {}

local function nowSeconds()
  if type(getTime) == "function" then
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

local function debugLog(key, msg)
  if not debugEnabled then return end
  if key and loggedSources[key] then return end
  if key then loggedSources[key] = true end
  if Log then
    Log.emit("rfsuite.sensors", tostring(msg), "debug", true)
  end
end

local fieldInfoCache = {}
local fieldInfoMisses = {}

local function readTelemetryValue(name)
  if type(name) ~= "string" or type(getValue) ~= "function" then return nil end
  if getFieldInfo then
    local info = fieldInfoCache[name]
    if not info then
      local now = nowSeconds()
      if now - (fieldInfoMisses[name] or 0) < 2.0 then return nil end
      info = getFieldInfo(name)
      if info and info.id ~= nil then
        fieldInfoCache[name] = info
      else
        fieldInfoMisses[name] = now
        return nil
      end
    end
  end
  local ok, value = pcall(getValue, name)
  if ok and type(value) == "number" then
    return value
  end
  return nil
end

local function readSimSensorFile(name)
  if type(name) ~= "string" or name == "" then return nil end
  local candidates = {}
  local function addCandidate(value)
    if type(value) ~= "string" or value == "" then return end
    for i = 1, #candidates do
      if candidates[i] == value then return end
    end
    candidates[#candidates + 1] = value
  end

  addCandidate(name)
  addCandidate(string.lower(name))
  addCandidate(SIM_FILE_ALIASES[name])

  for p = 1, #SIM_SENSOR_PATHS do
    local base = SIM_SENSOR_PATHS[p]
    for i = 1, #candidates do
      local filePath = base .. candidates[i] .. ".lua"
      local cached = simValueCache[filePath]
      local now = nowSeconds()
      if cached and (now - (cached.t or 0)) <= 0.25 then
        if cached.v ~= nil then
          debugLog("sim-hit:" .. name, "sim cache hit " .. filePath .. " = " .. tostring(cached.v))
          return cached.v
        end
      else
        local f = io.open(filePath, "r")
        local v = nil
        if f then
          local content = io.read(f, 64)
          io.close(f)
          if type(content) == "string" then
            local n = string.match(content, "return%s+([%+%-]?%d+%.?%d*)")
            if n then
              v = tonumber(n)
            end
          end
        end

        simValueCache[filePath] = { t = now, v = v }
        if v ~= nil then
          debugLog("sim-hit:" .. name, "sim file hit " .. filePath .. " = " .. tostring(v))
          return v
        end
      end
    end
  end

  debugLog("sim-miss:" .. name, "sim file miss for source " .. tostring(name))
  return nil
end

local function normalizeSimValue(name, value)
  if type(value) ~= "number" then return value end
  local meta = Sensors.map and Sensors.map[name] or nil
  local prec = meta and tonumber(meta.prec) or 0
  if prec and prec > 0 then
    local div = 10 ^ prec
    if div > 0 then
      return value / div
    end
  end
  return value
end

-- Sensor definitions: 4-char name → metadata
Sensors.map = {
  -- Flight Control
  ARM  = { label = "Arm Flags", unit = "raw", prec = 0, fallback = 0 },
  Gov  = { label = "Governor", unit = "raw", prec = 0, fallback = 0 },

  -- Power System
  Vbat = { label = "Main Voltage", unit = "V", prec = 2, fallback = 24.2 },
  Curr = { label = "Current", unit = "A", prec = 2, fallback = 0 },
  Capa = { label = "Consumption", unit = "mAh", prec = 0, fallback = 0 },
  ["Bat%"] = { label = "Fuel", unit = "%", prec = 0, fallback = 100 },
  Vbec = { label = "BEC Voltage", unit = "V", prec = 2, fallback = 8.0 },

  -- Flight Profiles
  ["PID#"] = { label = "PID Profile", unit = "raw", prec = 0, fallback = 1 },
  ["RTE#"] = { label = "Rate Profile", unit = "raw", prec = 0, fallback = 1 },
  BatP = { label = "Battery Profile", unit = "raw", prec = 0, fallback = 1 },

  -- Speeds / RPM
  Hspd = { label = "Headspeed", unit = "rpm", prec = 0, fallback = 0 },
  Tspd = { label = "Tailspeed", unit = "rpm", prec = 0, fallback = 0 },
  RQly = { label = "Link Quality", unit = "dB", prec = 0, fallback = 0 },

  -- Attitude
  Ptch = { label = "Pitch", unit = "°", prec = 1, fallback = 0 },
  Roll = { label = "Roll", unit = "°", prec = 1, fallback = 0 },
  Yaw  = { label = "Yaw", unit = "°", prec = 1, fallback = 0 },

  -- Temperature
  TescT = { label = "ESC Temp", unit = "°C", prec = 0, fallback = 25 },
  TmcuT = { label = "MCU Temp", unit = "°C", prec = 0, fallback = 25 },

  -- Other
  ["Thr%"] = { label = "Throttle %", unit = "%", prec = 0, fallback = 0 },
  Alt  = { label = "Altitude", unit = "m", prec = 1, fallback = 0 },
  ["Cel#"] = { label = "Cell Count", unit = "raw", prec = 0, fallback = 6 },
}

-- Aliases: dashboard/internal names → 4-char sensor names
Sensors.aliases = {
  voltage = "Vbat",
  rpm = "Hspd",
  link = "RQly",
  fuel = "Bat%",
  current = "Curr",
  pid_profile = "PID#",
  rate_profile = "RTE#",
  battery_profile = "BatP",
  throttle = "Thr%",
  altitude = "Alt",
  pitch = "Ptch",
  roll = "Roll",
  yaw = "Yaw",
  armflags = "ARM",
  governor = "Gov",
}

Sensors.search_paths = {
  voltage = { "Vbat", "VFAS", "voltage", "VBAT" },
  fuel = { "Bat%", "Fuel", "fuel" },
  rpm = { "Hspd", "RPM", "rpm" },
  link = { "RQly", "LQ", "Link", "link_quality", "1RSS", "2RSS" },
  current = { "Curr", "Current", "current" },
  pid_profile = { "PID#", "PIDP", "PidP", "PID Profile", "PID" },
  rate_profile = { "RTE#", "RateP", "RTPR", "Rate Profile", "Rate" },
  battery_profile = { "BAT#", "BatP", "BatProfile", "Battery Profile" },
  throttle = { "Thr%", "Throttle", "throttle" },
  altitude = { "Alt", "Altitude", "altitude" },
  pitch = { "Ptch", "Pitch", "pitch" },
  roll = { "Roll", "roll" },
  yaw = { "Yaw", "yaw" },
  armflags = { "ARM", "Arm", "ARMF", "ArmF", "armflags" },
  governor = { "Gov", "Governor", "governor" },
  temp_esc = { "Tesc", "ESC_TMP", "TescT", "ESC Temp", "temp_esc" },
  temp_mcu = { "Tmcu", "TmcuT", "temp_mcu" }
}

-- Detect if running in simulator
function Sensors.isSimulator()
  if getVersion then
    local ok, _, fw = pcall(getVersion)
    if ok and type(fw) == "string" then
      return string.sub(fw, -4) == "simu"
    end
  end
  return false
end

-- Resolve alias to 4-char sensor name
function Sensors.resolveName(source)
  if type(source) ~= "string" then return nil end
  if Sensors.aliases[source] then
    return Sensors.aliases[source]
  end
  if Sensors.map[source] then
    return source
  end
  return nil
end

-- Get sensor metadata by 4-char name or alias
function Sensors.getMetadata(source)
  local name = Sensors.resolveName(source)
  if name then
    return Sensors.map[name]
  end
  return nil
end

function Sensors.getValue(source)
  if type(source) ~= "string" then return nil end

  if not loggedSimulatorState then
    loggedSimulatorState = true
    debugLog(nil, "simulator detected = " .. tostring(Sensors.isSimulator()))
  end

  local resolved = Sensors.resolveName(source)

  -- In simulator mode we prefer file-based values so widget updates follow the sensor tool.
  if Sensors.isSimulator() then
    if resolved then
      local simValue = readSimSensorFile(resolved)
      if type(simValue) == "number" then
        local normalized = normalizeSimValue(resolved, simValue)
        debugLog("sim-use:" .. source, "using sim value " .. resolved .. " = " .. tostring(normalized))
        return normalized
      end
    end

    local simDirect = readSimSensorFile(source)
    if type(simDirect) == "number" then
      local normalized = normalizeSimValue(source, simDirect)
      debugLog("sim-direct-use:" .. source, "using sim direct value " .. source .. " = " .. tostring(normalized))
      return normalized
    end
  end

  local activePath = Sensors.active_paths and Sensors.active_paths[source]
  if activePath then
    local val = readTelemetryValue(activePath)
    if type(val) == "number" then
      debugLog("telemetry-hit-cached:" .. source, "hit " .. activePath .. " = " .. tostring(val))
      return val
    end
  end

  local paths = Sensors.search_paths[source]
  if paths then
    for i = 1, #paths do
      local val = readTelemetryValue(paths[i])
      if type(val) == "number" then
        Sensors.active_paths = Sensors.active_paths or {}
        Sensors.active_paths[source] = paths[i]
        debugLog("telemetry-hit:" .. source, "hit " .. paths[i] .. " = " .. tostring(val))
        return val
      end
    end
  end

  if resolved then
    local value = readTelemetryValue(resolved)
    if type(value) == "number" then
      Sensors.active_paths = Sensors.active_paths or {}
      Sensors.active_paths[source] = resolved
      debugLog("telemetry-hit:" .. source, "telemetry hit " .. resolved .. " = " .. tostring(value))
      return value
    end
  end

  local direct = readTelemetryValue(source)
  if type(direct) == "number" then
    Sensors.active_paths = Sensors.active_paths or {}
    Sensors.active_paths[source] = source
    debugLog("telemetry-direct-hit:" .. source, "telemetry direct hit " .. source .. " = " .. tostring(direct))
    return direct
  end

  return nil
end

-- Get all 4-char sensor names (for tool enumeration)
function Sensors.getAllNames()
  local names = {}
  for name, _ in pairs(Sensors.map) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

return Sensors
