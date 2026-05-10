-- Shared task: smartfuel_config read
local M = {}

local done = false
local requestSent = false
local smartfuelConfigApi = nil
local Log = nil

local function parseVersionString(value)
  if type(value) ~= "string" then return nil end
  local major, minor, patch = string.match(value, "^(%d+)%.(%d+)%.(%d+)$")
  if not major then return nil end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function isVersionAtLeast(current, required)
  if type(current) ~= "table" or type(required) ~= "table" then return false end
  for i = 1, 3 do
    local a = tonumber(current[i]) or 0
    local b = tonumber(required[i]) or 0
    if a > b then return true end
    if a < b then return false end
  end
  return true
end

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

function M.wakeup()
  if Log == nil then
    Log = loadModule("lib/log.lua") or false
  end

  if done or requestSent then return end

  local root = _G and _G.rfsuite
  if type(root) ~= "table" then return end
  local session = root.session
  if type(session) ~= "table" then return end

  -- Ethos parity: SMARTFUEL_CONFIG is available only from API >= 12.0.10.
  local apiVersion = parseVersionString(session.apiVersion)
  if not isVersionAtLeast(apiVersion, { 12, 0, 10 }) then
    done = true
    if type(Log) == "table" and type(Log.emit) == "function" then
      pcall(Log.emit, "rfsuite.tasks.smartfuel", "skip smartfuel_config (api < 12.0.10)", "debug", true)
    end
    return
  end

  requestSent = true

  if not smartfuelConfigApi then
    smartfuelConfigApi = loadModule("tasks/msp/api/smartfuel_config.lua")
  end
  local msp = loadModule("tasks/msp/runtime.lua")
  if not msp or not smartfuelConfigApi then
    done = true
    return
  end

  local mspState = type(msp.getState) == "function" and msp.getState()
  if not mspState or not mspState.queue then
    done = true
    return
  end

  mspState.queue:add({
    command = smartfuelConfigApi.command,
    simulatorResponse = smartfuelConfigApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(self, buf)
      local data = smartfuelConfigApi.parse(buf)
      if type(data) == "table" then
        session.smartfuel_config = data.parsed or data
      end
      done = true
      if type(Log) == "table" and type(Log.emit) == "function" then
        pcall(Log.emit, "rfsuite.tasks.smartfuel", "smartfuel_config received", "debug", true)
      end
    end,
    errorHandler = function()
      done = true
      if type(Log) == "table" and type(Log.emit) == "function" then
        pcall(Log.emit, "rfsuite.tasks.smartfuel", "smartfuel_config read failed", "warn", true)
      end
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
