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

function Log.emit(tag, msg, level, enabled)
  local emitByLevel = shouldEmitByLevel(level)
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

return Log
