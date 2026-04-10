if type(_G) == "table" and type(_G.__rfsuite_msp_runtime_module) == "table" then
  return _G.__rfsuite_msp_runtime_module
end

local Runtime = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then
    return nil
  end
  local ok, mod = pcall(chunk)
  if not ok then
    return nil
  end
  return mod
end

local DetectProtocol = loadModule("tasks/msp/protocols.lua")
local CommonModule = loadModule("tasks/msp/common.lua")
local QueueModule = loadModule("tasks/msp/queue.lua")
local ApiVersionApi = loadModule("tasks/msp/api/api_version.lua")
local FcVersionApi = loadModule("tasks/msp/api/fc_version.lua")
local Log = loadModule("lib/log.lua")
local Version = loadModule("lib/version.lua")

local state = {
  initialized = false,
  available = false,
  protocol = nil,
  isSimulator = false,
  queue = nil,
  clients = {},
  values = {
    apiVersion = "0",
    fcVersion = "0",
    rfVersion = "0"
  },
  unsupportedApi = false,
  unsupportedApiLogged = false,
  requestBackoffUntil = 0,
  consecutiveApiVersionFailures = 0,
  mspLastError = nil,
  mspLastErrorAt = 0,
  pendingVersionRead = true,
  lastArmed = nil,
  lastConnected = nil
}

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, v = pcall(getTime)
    if ok and type(v) == "number" then
      return v / 100
    end
  end
  if type(os) == "table" and type(os.clock) == "function" then
    return os.clock()
  end
  return 0
end

local function log(msg, level)
  if Log and type(Log.emit) == "function" then
    Log.emit("rfsuite.msp", msg, level or "debug", true)
  end
end

local function ensureRootState()
  _G.rfsuite = _G.rfsuite or {}
  _G.rfsuite.session = _G.rfsuite.session or {}
  _G.rfsuite.diagnostics = _G.rfsuite.diagnostics or {}
end

local function publish()
  ensureRootState()
  local session = _G.rfsuite.session
  local diagnostics = _G.rfsuite.diagnostics

  session.apiVersion = state.values.apiVersion
  session.fcVersion = state.values.fcVersion
  session.rfVersion = state.values.rfVersion
  session.apiSupported = not state.unsupportedApi
  session.mspLastError = state.mspLastError
  session.mspLastErrorAt = state.mspLastErrorAt

  diagnostics.apiVersion = state.values.apiVersion
  diagnostics.fcVersion = state.values.fcVersion
  diagnostics.rfVersion = state.values.rfVersion
  diagnostics.apiSupported = not state.unsupportedApi
  diagnostics.mspLastError = state.mspLastError
  diagnostics.mspLastErrorAt = state.mspLastErrorAt
end

local function setMspError(message, now)
  state.mspLastError = tostring(message or "")
  state.mspLastErrorAt = now or nowSeconds()
end

local function isApiVersionSupported(version)
  if type(version) ~= "string" or version == "" then
    return false
  end

  if not Version or type(Version.getSupportedMspApiVersions) ~= "function" then
    return true
  end

  local supported = Version.getSupportedMspApiVersions()
  if type(supported) ~= "table" then
    return true
  end

  for i = 1, #supported do
    if tostring(supported[i]) == version then
      return true
    end
  end

  return false
end

local function isSimulator()
  if type(system) == "table" and type(system.getVersion) == "function" then
    local ok, info = pcall(system.getVersion)
    if ok and type(info) == "table" then
      local sim = info.simulation
      if sim ~= nil and sim ~= false and sim ~= 0 then
        return true
      end
    end
  end
  if type(getVersion) == "function" then
    local ok, _, fw = pcall(getVersion)
    if ok and type(fw) == "string" then
      local fwl = string.lower(fw)
      if string.find(fwl, "simu", 1, true) ~= nil then
        return true
      end
    end
  end
  return false
end

local ARM_SOURCES = { "ARM", "Arm", "ARMF", "ArmF" }

local function readArmedState()
  if type(getValue) ~= "function" then
    return false
  end

  for i = 1, #ARM_SOURCES do
    local ok, value = pcall(getValue, ARM_SOURCES[i])
    if ok and value ~= nil then
      if type(value) == "number" then
        if type(bit32) == "table" and type(bit32.btest) == "function" then
          return bit32.btest(value, 1)
        end
        return value ~= 0
      end
      if type(value) == "boolean" then
        return value
      end
      if type(value) == "string" then
        local n = tonumber(value)
        if type(n) == "number" then
          return n ~= 0
        end
      end
    end
  end

  return false
end

local function isConnected()
  if state.isSimulator then
    return true
  end
  if type(getRSSI) ~= "function" then
    return true
  end
  local ok, rssi = pcall(getRSSI)
  if not ok or type(rssi) ~= "number" then
    return true
  end
  return rssi > 0
end

local function enqueueVersionReads(now)
  if not state.pendingVersionRead then
    return
  end
  if not state.queue or not state.queue:isProcessed() then
    return
  end
  if state.requestBackoffUntil and now < state.requestBackoffUntil then
    return
  end

  state.pendingVersionRead = false
  state.queue:add({
    command = ApiVersionApi.command,
    simulatorResponse = ApiVersionApi.simulatorResponse,
    processReply = function(_, buf)
      local parsed = ApiVersionApi.parse(buf)
      if parsed and parsed.version then
        state.consecutiveApiVersionFailures = 0
        state.requestBackoffUntil = 0
        state.mspLastError = nil
        state.mspLastErrorAt = 0
        state.values.apiVersion = parsed.version
        state.unsupportedApi = not isApiVersionSupported(parsed.version)
        if state.unsupportedApi and not state.unsupportedApiLogged then
          state.unsupportedApiLogged = true
          log("Unsupported MSP API version " .. tostring(parsed.version) .. " (supported: " .. tostring(Version and Version.getSupportedMspApiVersionsString and Version.getSupportedMspApiVersionsString() or "-") .. ")", "warn")
          state.queue:clear()
        end
      end
      publish()
    end,
    errorHandler = function()
      state.consecutiveApiVersionFailures = (state.consecutiveApiVersionFailures or 0) + 1
      local backoff = math.min(30, 2 + state.consecutiveApiVersionFailures * 2)
      state.requestBackoffUntil = nowSeconds() + backoff
      setMspError("API_VERSION read failed (cmd=1)", nowSeconds())
      log("API_VERSION read failed repeatedly; backoff " .. tostring(backoff) .. "s", "warn")
      publish()
    end
  })

  state.queue:add({
    command = FcVersionApi.command,
    simulatorResponse = FcVersionApi.simulatorResponse,
    processReply = function(_, buf)
      local parsed = FcVersionApi.parse(buf)
      if parsed then
        state.values.fcVersion = parsed.fcVersion or state.values.fcVersion
        state.values.rfVersion = parsed.rfVersion or state.values.rfVersion
      end
      publish()
    end
  })
end

local function initIfNeeded()
  if state.initialized then
    return state.available
  end

  state.isSimulator = isSimulator()
  state.protocol = type(DetectProtocol) == "function" and DetectProtocol() or nil

  local common = nil
  if state.protocol and CommonModule and type(CommonModule.new) == "function" then
    common = CommonModule.new(state.protocol)
  end

  if not common and not state.isSimulator then
    state.available = false
    state.initialized = true
    log("MSP transport unavailable (no CRSF/GHST/SP)", "warn")
    return false
  end

  if not common then
    common = {
      sendRequest = function() end,
      processTxQ = function() end,
      pollReply = function() return nil end,
      clearTxBuf = function() end,
    }
  end

  if not QueueModule or type(QueueModule.new) ~= "function" then
    state.available = false
    state.initialized = true
    log("MSP queue module unavailable", "error")
    return false
  end

  state.queue = QueueModule.new(common, {
    log = log,
    isSimulator = state.isSimulator,
    maxRetries = state.protocol == "crsf" and 5 or 3,
    commandInterval = state.protocol == "crsf" and 0.15 or 0.25,
  })

  state.available = true
  state.initialized = true

  local proto = state.protocol or (state.isSimulator and "simulator") or "none"
  log("MSP runtime initialized via " .. tostring(proto), "info")
  publish()
  return true
end

function Runtime.attach(clientId)
  local id = tostring(clientId or "unknown")
  state.clients[id] = true
  initIfNeeded()
end

function Runtime.detach(clientId)
  local id = tostring(clientId or "unknown")
  state.clients[id] = nil
end

function Runtime.tick()
  if not initIfNeeded() then
    return false
  end

  local now = nowSeconds()

  local connected = isConnected()
  if state.lastConnected ~= connected then
    state.lastConnected = connected
    if connected then
      log("MSP link connected", "info")
      state.pendingVersionRead = true
    else
      log("MSP link disconnected", "info")
      state.queue:clear()
      state.pendingVersionRead = true
    end
  end

  if not connected then
    return false
  end

  local armed = readArmedState()
  if armed then
    if state.lastArmed ~= true then
      state.lastArmed = true
      state.queue:clear()
      log("MSP paused while ARMED", "info")
    end
    return true
  end

  if state.unsupportedApi then
    return false
  end

  if state.lastArmed == true then
    state.lastArmed = false
    log("MSP resumed after DISARM", "info")
  end

  enqueueVersionReads(now)
  state.queue:processQueue(now)
  publish()
  return true
end

function Runtime.getState()
  return state
end

if type(_G) == "table" then
  _G.__rfsuite_msp_runtime_module = Runtime
end

return Runtime
