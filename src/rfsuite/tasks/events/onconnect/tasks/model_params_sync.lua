-- OnConnect task: mirror the flight controller's three model parameters onto the radio, when the
-- "Synchronize Model Parameters" setting asks for it.
--
-- Each parameter is a (type, value) pair. The type selects what on the radio the value belongs to:
-- nothing, one of the three timers, or one of the nine global variables.

local M = {}

local done = false
local requestSent = false
local Log = nil
local PilotConfigApi = nil

local PARAM_TYPE_NONE = 0
local PARAM_TYPE_TIMER_FIRST = 1
local PARAM_TYPE_TIMER_LAST = 3
local PARAM_TYPE_GV_FIRST = 4
local PARAM_TYPE_GV_LAST = 12

-- Global variables are written for the first flight mode; the radio's own inheritance carries
-- them to the others.
local GV_FLIGHT_MODE = 0

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local function log(msg, level)
  if Log == nil then
    Log = loadModule("lib/log.lua") or false
  end
  if type(Log) == "table" and type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.tasks.model_params_sync", msg, level or "debug", true)
  end
end

local function isTruthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

local function syncEnabled()
  local root = _G and _G.rfsuite
  local prefs = type(root) == "table" and root.preferences or nil
  local general = type(prefs) == "table" and prefs.general or nil
  return isTruthy(general and general.syncparams)
end

-- The timer's start value is what the pilot configured, so that is what a parameter from the
-- flight controller sets. The running value is deliberately left alone: this task also runs on a
-- reconnect, and writing there would clear a timer that is counting a flight.
local function applyTimer(index, value)
  if type(model) ~= "table" or type(model.getTimer) ~= "function" or type(model.setTimer) ~= "function" then
    return false
  end
  local ok, timer = pcall(model.getTimer, index)
  if not ok or type(timer) ~= "table" then return false end
  if timer.start == value then return false end
  -- ONLY `start`, and never the table `getTimer` handed over. A missing key leaves its field
  -- alone (`model.setTimer`'s own contract), while the full table carries `value` back with it
  -- -- and `value` is the RUNNING count: setTimer assigns it to `timersStates[idx].val`
  -- (`radio/src/lua/api_model.cpp`). Writing the whole table therefore rewinds a running timer
  -- to whatever it read a moment earlier, by up to one tick of the timer task, which is the
  -- very thing this task takes care not to do on a reconnect.
  return pcall(model.setTimer, index, { start = value })
end

local function applyGlobalVariable(index, value)
  if type(model) ~= "table" or type(model.setGlobalVariable) ~= "function" then
    return false
  end
  if type(model.getGlobalVariable) == "function" then
    local ok, current = pcall(model.getGlobalVariable, index, GV_FLIGHT_MODE)
    if ok and current == value then return false end
  end
  return pcall(model.setGlobalVariable, index, GV_FLIGHT_MODE, value)
end

local function applyParameter(paramType, value)
  paramType = tonumber(paramType)
  value = tonumber(value)
  if paramType == nil or value == nil or paramType == PARAM_TYPE_NONE then return end

  if paramType >= PARAM_TYPE_TIMER_FIRST and paramType <= PARAM_TYPE_TIMER_LAST then
    if applyTimer(paramType - PARAM_TYPE_TIMER_FIRST, value) then
      log("timer " .. tostring(paramType) .. " set to " .. tostring(value), "info")
    end
  elseif paramType >= PARAM_TYPE_GV_FIRST and paramType <= PARAM_TYPE_GV_LAST then
    if applyGlobalVariable(paramType - PARAM_TYPE_GV_FIRST, value) then
      log("global variable " .. tostring(paramType - PARAM_TYPE_GV_FIRST + 1) .. " set to " .. tostring(value), "info")
    end
  end
end

function M.wakeup()
  if done then return end

  local root = _G and _G.rfsuite
  local session = type(root) == "table" and root.session or nil
  if type(session) ~= "table" then return end

  if not syncEnabled() then
    done = true
    return
  end

  if requestSent then return end
  requestSent = true

  if not PilotConfigApi then
    PilotConfigApi = loadModule("tasks/msp/api/pilot_config.lua")
  end
  local msp = loadModule("tasks/msp/runtime.lua")
  if not msp or not PilotConfigApi then
    done = true
    return
  end

  local mspState = type(msp.getState) == "function" and msp.getState()
  if not mspState or not mspState.queue then
    done = true
    return
  end

  mspState.queue:add({
    command = PilotConfigApi.command,
    simulatorResponse = PilotConfigApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(self, buf)
      local data = PilotConfigApi.parse(buf)
      if type(data) == "table" then
        applyParameter(data.model_param1_type, data.model_param1_value)
        applyParameter(data.model_param2_type, data.model_param2_value)
        applyParameter(data.model_param3_type, data.model_param3_value)
      end
      done = true
    end,
    errorHandler = function()
      log("pilot config read failed", "warn")
      done = true
    end
  })
end

function M.isComplete()
  return done
end

function M.reset()
  done = false
  requestSent = false
end

return M
