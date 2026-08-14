local Log = {}

local function isTruthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

local function normalizeLevel(value)
  local text = string.lower(tostring(value or "debug"))
  if text == "off" then return "off" end
  if text == "info" then return "info" end
  if text == "debug" then return "debug" end
  if text == "warn" or text == "warning" then return "warn" end
  if text == "error" then return "error" end
  return "debug"
end

local function debugLevelRank(level)
  local normalized = normalizeLevel(level)
  if normalized == "off" then return 0 end
  if normalized == "error" or normalized == "warn" or normalized == "info" then return 1 end
  return 2
end

local function configuredDebugLevel()
  local root = _G and _G.rfsuite
  local prefs = root and root.preferences
  local general = prefs and prefs.general
  local value = general and general.debug_level
  if value == nil then
    return "off"
  end
  local normalized = normalizeLevel(value)
  if normalized == "warn" or normalized == "error" then
    return "info"
  end
  if normalized ~= "off" and normalized ~= "info" and normalized ~= "debug" then
    return "off"
  end
  return normalized
end

local function shouldEmitByLevel(messageLevel)
  local configured = configuredDebugLevel()
  if configured == "off" then
    return false
  end
  return debugLevelRank(messageLevel) <= debugLevelRank(configured)
end

local function isSerialDebugEnabled()
  local root = _G and _G.rfsuite
  local prefs = root and root.preferences
  local general = prefs and prefs.general
  return isTruthy(general and general.enable_serial_debug)
end

local MAX_HISTORY = 60
local MAX_MSG_LEN = 100

-- Initialize global state once
if type(_G) == "table" then
  _G.rfsuite = _G.rfsuite or {}
  _G.rfsuite.log_history = _G.rfsuite.log_history or {}
  _G.rfsuite.log_history_seq = _G.rfsuite.log_history_seq or 0
end

local function addToHistory(tag, msg, level)
  local t = tostring(tag or "rfsuite")
  local lvl = tostring(level or "debug")
  local m = tostring(msg or "")
  
  if string.len(m) > MAX_MSG_LEN then
    m = string.sub(m, 1, MAX_MSG_LEN - 3) .. "..."
  end

  local history = _G.rfsuite.log_history
  table.insert(history, {
    tag = t,
    msg = m,
    level = lvl,
    time = getTime and getTime() or 0
  })

  if #history > MAX_HISTORY then
    table.remove(history, 1)
  end
  
  _G.rfsuite.log_history_seq = _G.rfsuite.log_history_seq + 1
end

function Log.emit(tag, msg, level, enabled)
  local emitByLevel = shouldEmitByLevel(level)
  
  -- Always buffer important logs (info/warn/error) or if debug is enabled
  if emitByLevel or normalizeLevel(level) ~= "debug" then
    addToHistory(tag, msg, level)
  end

  local emitConsole = isTruthy(enabled) and emitByLevel
  local emitSerial = isSerialDebugEnabled() and type(serialWrite) == "function" and emitByLevel

  if not emitConsole and not emitSerial then
    return
  end

  local t = tag or "rfsuite"
  local lvl = level or "debug"
  local line = "[" .. tostring(t) .. "][" .. tostring(lvl) .. "] " .. tostring(msg)

  if emitConsole and type(print) == "function" then
    print(line)
  end

  if emitSerial then
    pcall(serialWrite, line .. "\n")
  end
end

if type(_G) == "table" then
  _G.rfsuite = _G.rfsuite or {}
  _G.rfsuite.Log = Log
end

return Log
