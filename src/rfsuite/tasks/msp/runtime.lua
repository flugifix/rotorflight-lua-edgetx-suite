if type(_G) == "table" and type(_G.__rfsuite_msp_runtime_module) == "table" then
  return _G.__rfsuite_msp_runtime_module
end

local Runtime = {}

local function loadModule(path)
  if _G.rfsuite and _G.rfsuite.require then
    return _G.rfsuite.require(path)
  end
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

local DetectProtocol = nil
local CommonModule = nil
local QueueModule = nil
local ApiVersionApi = nil
local FcVersionApi = nil
local UidApi = nil
local Log = nil
local Version = nil
local ApiVersion = nil
local ModelPreferences = nil

local state = {
  initialized = false,
  available = false,
  protocol = nil,
  isSimulator = false,
  queue = nil,
  clients = {},
  values = {
    apiVersion = "",
    fcVersion = "",
    rfVersion = "",
    mcuId = nil,
    modelPreferences = nil,
    modelPreferencesFile = nil
  },
  unsupportedApi = false,
  limitedApi = false,
  unsupportedApiLogged = false,
  _disconnectHandled = false,
  requestBackoffUntil = 0,
  consecutiveApiVersionFailures = 0,
  mspLastError = nil,
  mspLastErrorAt = 0,
  pendingVersionRead = true,
  pendingUidRead = true,
  versionReadCompleted = false,
  lastArmed = nil,
  lastConnected = nil
}

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, value = pcall(getTime)
    if ok and type(value) == "number" then
      return value / 100
    end
  end
  if type(os) == "table" and type(os.clock) == "function" then
    return os.clock()
  end
  return 0
end

local function log(msg, level)
  if not Log then
    Log = loadModule("lib/log.lua")
  end
  if Log and type(Log.emit) == "function" then
    Log.emit("rfsuite.msp", msg, level or "debug", true)
  end
end

local function ensureBaseDeps()
  if not DetectProtocol then
    DetectProtocol = loadModule("tasks/msp/protocols.lua")
  end
  if not CommonModule then
    CommonModule = loadModule("tasks/msp/common.lua")
  end
  if not QueueModule then
    QueueModule = loadModule("tasks/msp/queue.lua")
  end
end

local function ensureVersionDeps()
  if not ApiVersionApi then
    ApiVersionApi = loadModule("tasks/msp/api/api_version.lua")
    return false
  end
  if not FcVersionApi then
    FcVersionApi = loadModule("tasks/msp/api/fc_version.lua")
    return false
  end
  if not Version then
    Version = loadModule("lib/version.lua")
    return false
  end
  if not ApiVersion then
    ApiVersion = loadModule("lib/api_version.lua")
    return false
  end
  return true
end

local function ensureUidDep()
  if not UidApi then
    UidApi = loadModule("tasks/msp/api/uid.lua")
    return false
  end
  if not ModelPreferences then
    ModelPreferences = loadModule("lib/model_preferences.lua")
    return false
  end
  return true
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
  session.mcu_id = state.values.mcuId
  session.modelPreferences = state.values.modelPreferences
  session.modelPreferencesFile = state.values.modelPreferencesFile
  session.apiSupported = not state.unsupportedApi
  session.apiLimited = state.limitedApi == true
  session.mspLastError = state.mspLastError
  session.mspLastErrorAt = state.mspLastErrorAt
  session.telemetryType = state.protocol
  diagnostics.apiVersion = state.values.apiVersion
  diagnostics.fcVersion = state.values.fcVersion
  diagnostics.rfVersion = state.values.rfVersion
  diagnostics.mcu_id = state.values.mcuId
  diagnostics.apiSupported = not state.unsupportedApi
  diagnostics.apiLimited = state.limitedApi == true
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

  if not Version then
    Version = loadModule("lib/version.lua")
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

local function getOldestSupportedApiVersionParsed()
  if not Version then
    Version = loadModule("lib/version.lua")
  end
  if not ApiVersion then
    ApiVersion = loadModule("lib/api_version.lua")
  end
  if not Version or not ApiVersion then
    return nil
  end
  if type(Version.getSupportedMspApiVersions) ~= "function" or type(ApiVersion.parse) ~= "function" then
    return nil
  end

  local supported = Version.getSupportedMspApiVersions()
  if type(supported) ~= "table" or #supported == 0 then
    return nil
  end

  local oldest = nil
  for i = 1, #supported do
    local parsed = ApiVersion.parse(supported[i])
    if type(parsed) == "table" then
      if not oldest then
        oldest = parsed
      elseif ApiVersion.isAtLeast and ApiVersion.isAtLeast(oldest, parsed) then
        oldest = parsed
      end
    end
  end

  return oldest
end

local function isApiVersionLimitedCompatible(version)
  if type(version) ~= "string" or version == "" then
    return false
  end
  if not Version then
    Version = loadModule("lib/version.lua")
  end
  if not ApiVersion then
    ApiVersion = loadModule("lib/api_version.lua")
  end
  if not Version or not ApiVersion then
    return false
  end
  if type(ApiVersion.parse) ~= "function" or type(ApiVersion.isAtLeast) ~= "function" then
    return false
  end
  if type(Version.getLatestSupportedMspApiVersion) ~= "function" then
    return false
  end

  local current = ApiVersion.parse(version)
  local latest = ApiVersion.parse(Version.getLatestSupportedMspApiVersion())
  if type(current) ~= "table" or type(latest) ~= "table" then
    return false
  end

  local oldest = getOldestSupportedApiVersionParsed() or latest

  local currentMajor = tonumber(current[1]) or -1
  local latestMajor = tonumber(latest[1]) or -2
  return currentMajor == latestMajor
    and ApiVersion.isAtLeast(current, oldest)
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

local function applyModelPreferencesForMcu(mcuId)
  if type(mcuId) ~= "string" or mcuId == "" then
    state.values.modelPreferences = nil
    state.values.modelPreferencesFile = nil
    return
  end

  if not ModelPreferences then
    ModelPreferences = loadModule("lib/model_preferences.lua")
  end

  if not ModelPreferences or type(ModelPreferences.loadByMcuId) ~= "function" then
    state.values.modelPreferences = nil
    state.values.modelPreferencesFile = nil
    return
  end

  local prefs, filePath = ModelPreferences.loadByMcuId(mcuId)
  state.values.modelPreferences = prefs
  state.values.modelPreferencesFile = filePath
end

local function enqueueVersionReads(now)
  if not state.pendingVersionRead then
    return true
  end
  if not state.queue or not state.queue:isProcessed() then
    return true
  end
  if state.requestBackoffUntil and now < state.requestBackoffUntil then
    return true
  end

  if not ensureVersionDeps() then
    return false
  end
  state.pendingVersionRead = false
  state.queue:add({
    command = ApiVersionApi.command,
    simulatorResponse = ApiVersionApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(_, buf)
      local parsed = ApiVersionApi.parse(buf)
      if parsed and parsed.version then
        state.consecutiveApiVersionFailures = 0
        state.requestBackoffUntil = 0
        state.mspLastError = nil
        state.mspLastErrorAt = 0
        state.values.apiVersion = parsed.version
        local fullySupported = isApiVersionSupported(parsed.version)
        local limitedCompatible = (not fullySupported) and isApiVersionLimitedCompatible(parsed.version)
        state.unsupportedApi = not (fullySupported or limitedCompatible)
        state.limitedApi = limitedCompatible
        if limitedCompatible then
          log("MSP API version " .. tostring(parsed.version) .. " accepted in limited compatibility mode", "warn")
        end
        if state.unsupportedApi and not state.unsupportedApiLogged then
          state.unsupportedApiLogged = true
          log("Unsupported MSP API version " .. tostring(parsed.version) .. " (supported: " .. tostring(Version and Version.getSupportedMspApiVersionsString and Version.getSupportedMspApiVersionsString() or "-") .. ")", "warn")
          state.queue:clear()
        end
      end
      state.versionReadCompleted = true
      publish()
    end,
    errorHandler = function()
      state.consecutiveApiVersionFailures = (state.consecutiveApiVersionFailures or 0) + 1
      local backoff = math.min(30, 2 + state.consecutiveApiVersionFailures * 2)
      state.requestBackoffUntil = nowSeconds() + backoff
      setMspError("API_VERSION read failed (cmd=1)", nowSeconds())
      log("API_VERSION read failed repeatedly; backoff " .. tostring(backoff) .. "s", "warn")
      state.pendingVersionRead = true
      publish()
    end
  })

  state.queue:add({
    command = FcVersionApi.command,
    simulatorResponse = FcVersionApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(_, buf)
      local parsed = FcVersionApi.parse(buf)
      if parsed then
        state.values.fcVersion = parsed.fcVersion or state.values.fcVersion
        state.values.rfVersion = parsed.rfVersion or state.values.rfVersion
      end
      publish()
    end
  })
  
  return true
end

local function enqueueUidRead(now)
  if not state.pendingUidRead then
    return true
  end
  if not state.queue or not state.queue:isProcessed() then
    return true
  end
  if state.requestBackoffUntil and now < state.requestBackoffUntil then
    return true
  end
  if not ensureUidDep() then
    return false
  end
  if not UidApi or type(UidApi.parse) ~= "function" then
    state.pendingUidRead = false
    return true
  end

  state.pendingUidRead = false
  state.queue:add({
    command = UidApi.command,
    simulatorResponse = UidApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(_, buf)
      local parsed = UidApi.parse(buf)
      if parsed and parsed.mcuId and parsed.mcuId ~= "" then
        state.values.mcuId = tostring(parsed.mcuId)
        applyModelPreferencesForMcu(state.values.mcuId)
      end
      publish()
    end,
    errorHandler = function()
      state.pendingUidRead = true
      publish()
    end
  })
  
  return true
end

local function doDisconnect(now, reason)
  -- Make disconnect idempotent to avoid log spam when called repeatedly.
  if state._disconnectHandled then
    return
  end
  state._disconnectHandled = true
  -- Ensure runtime reflects disconnected state.
  state.lastConnected = false

  if type(reason) == "string" and reason ~= "" then
    log("MSP link disconnected (" .. tostring(reason) .. ")", "info")
  else
    log("MSP link disconnected", "info")
  end
  if state.queue and type(state.queue.clear) == "function" then
    state.queue:clear()
  end
  state.pendingVersionRead = true
  state.pendingUidRead = true
  state.versionReadCompleted = false
  state.limitedApi = false
  state.values.apiVersion = "0"
  state.values.fcVersion = "0"
  state.values.rfVersion = "0"
  state.values.mcuId = nil
  state.values.modelPreferences = nil
  state.values.modelPreferencesFile = nil
  publish()
end

local function initIfNeeded()
  if state.initialized then
    return state.available
  end

  ensureBaseDeps()

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
      -- Reset disconnect guard when link becomes active again
      state._disconnectHandled = false
      -- Re-negotiate API support on each fresh connect.
      state.unsupportedApi = false
      state.limitedApi = false
      state.unsupportedApiLogged = false
      log("MSP link connected", "info")
      state.pendingVersionRead = true
      state.pendingUidRead = true
    else
      doDisconnect(now, state.unsupportedApi and "unsupported API" or nil)
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
    state.queue:clear()
  else
    if state.lastArmed == true then
      state.lastArmed = false
      log("MSP resumed after DISARM", "info")
    end
  end

  if state.unsupportedApi then
    -- If API unsupported and we still consider the link connected, treat as disconnected.
    if state.lastConnected == true then
      doDisconnect(now, "unsupported API")
    end
    return false
  end

  -- Core startup reads (API version + UID).
  if not armed then
    enqueueVersionReads(now)
    enqueueUidRead(now)
  end

  state.queue:processQueue(now)
  publish()
  -- If the version read cleared/marked unsupported during processing, ensure we
  -- treat the runtime as disconnected so callers see a consistent state.
  if state.unsupportedApi and state.lastConnected == true then
    doDisconnect(now, "unsupported API")
    return false
  end

  return true
end

function Runtime.getState()
  return state
end

function Runtime.getProgress()
  local total = 0
  local done = 0

  -- Core startup reads (API version + UID) are always tracked.
  total = total + 1
  if state.versionReadCompleted == true then
    done = done + 1
  end

  total = total + 1
  if state.values.mcuId ~= nil then
    done = done + 1
  end

  local queueIdle = true
  if state.queue and type(state.queue.isProcessed) == "function" then
    queueIdle = state.queue:isProcessed() == true
  end

  local active = (state.available == true) and ((done < total) or (queueIdle == false))
  return {
    active = active,
    done = done,
    total = total,
    queueIdle = queueIdle,
  }
end

if type(_G) == "table" then
  _G.__rfsuite_msp_runtime_module = Runtime
end

return Runtime
