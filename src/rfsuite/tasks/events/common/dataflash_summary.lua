-- Shared task: dataflash_summary auslesen
local M = {}

local done = false
local requestSent = false
local dataflashApi = nil
local Log = nil

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

function M.wakeup(args)
  if Log == nil then
    Log = loadModule("lib/log.lua") or false
  end

  if done then return end

  local root = _G and _G.rfsuite
  if type(root) ~= "table" then return end
  local session = root.session
  if type(session) ~= "table" then return end

  if requestSent then return end
  requestSent = true

  -- MSP dataflash_summary API laden
  if not dataflashApi then
    dataflashApi = loadModule("tasks/msp/api/dataflash_summary.lua")
  end
  local msp = loadModule("tasks/msp/runtime.lua")
  if not msp or not dataflashApi then return end

  local mspState = type(msp.getState) == "function" and msp.getState()
  if not mspState or not mspState.queue then
    done = true
    return
  end

  if type(Log) == "table" and type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.tasks.dataflash", "MSP request for dataflash_summary (cmd=" .. tostring(dataflashApi.command) .. ") via queue", "debug", true)
  end

  mspState.queue:add({
    command = dataflashApi.command,
    simulatorResponse = dataflashApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(self, buf)
      local stats = dataflashApi.parse(buf)
      if stats then
        session.dataflash = stats
      end
      done = true
      if type(Log) == "table" and type(Log.emit) == "function" then
        pcall(Log.emit, "rfsuite.tasks.dataflash", "dataflash_summary received: used=" .. tostring(stats and stats.used) .. " total=" .. tostring(stats and stats.total), "debug", true)
      end
    end,
    errorHandler = function()
      done = true
      if type(Log) == "table" and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.dataflash", "dataflash_summary read failed", "warn", true) end
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
