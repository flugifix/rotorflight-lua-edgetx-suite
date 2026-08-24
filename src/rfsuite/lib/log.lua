local Log = {}

local function isTruthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

-- The severity ladder, ordered from quietest to most verbose. This table is the single
-- definition of it: the rank comparison below and the Debug Level selector on the developer
-- settings page both derive from it, so a level is added in one place instead of several.
--
-- The names are the ones GEMINI.md documents for Log.emit and the ones
-- app/pages/tools/diagnostics/session_logs/page.lua gives a colour of its own.
local LEVELS = { "off", "error", "warn", "info", "debug" }

local RANK = {}
for index, name in ipairs(LEVELS) do
  RANK[name] = index - 1
end

local function normalizeLevel(value)
  local text = string.lower(tostring(value or "debug"))
  if text == "warning" then return "warn" end
  if RANK[text] then return text end
  return "debug"
end

local function debugLevelRank(level)
  return RANK[normalizeLevel(level)]
end

local function configuredDebugLevel()
  local root = _G and _G.rfsuite
  local prefs = root and root.preferences
  local general = prefs and prefs.general
  local value = general and general.debug_level
  if value == nil then
    return "off"
  end
  local text = string.lower(tostring(value))
  if text == "warning" then text = "warn" end
  -- A value this build does not know stays off. normalizeLevel falls back to "debug", which is
  -- right for a message whose level is mistyped and wrong for the switch deciding whether
  -- anything is written at all -- there it would turn an unreadable setting into the loudest one.
  if RANK[text] == nil then
    return "off"
  end
  return text
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

  -- The history entry already carries a timestamp and session_logs/page.lua renders it, but
  -- the console and serial line was built without one, so the same message could be read with
  -- a time on the radio and without a time everywhere else. Same clock and same format as that
  -- page, and left out when the clock is unavailable, which is what the page does too.
  local now = getTime and getTime() or 0
  local stamp = ""
  if now > 0 then
    stamp = "[" .. string.format("%0.1f", now / 100) .. "]"
  end

  local line = "[" .. tostring(t) .. "][" .. tostring(lvl) .. "]" .. stamp .. " " .. tostring(msg)

  if emitConsole and type(print) == "function" then
    print(line)
  end

  if emitSerial then
    pcall(serialWrite, line .. "\n")
  end
end

-- Exported so the Debug Level selector on the developer settings page can offer exactly the
-- levels this module understands, instead of carrying a second list that drifts away from it.
Log.LEVELS = LEVELS

if type(_G) == "table" then
  _G.rfsuite = _G.rfsuite or {}
  _G.rfsuite.Log = Log
end

return Log
