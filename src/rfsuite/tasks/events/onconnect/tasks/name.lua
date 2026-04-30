-- OnConnect task: Modellname via MSP auslesen
local M = {}

local done = false
local requestSent = false
local NameApi = nil
local Log = nil

local function ensureLog()
  if not Log then
    local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/log.lua", "t")
    if type(chunk) == "function" then
      local ok, mod = pcall(chunk)
      if ok and type(mod) == "table" then Log = mod end
    end
  end
end

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

function M.wakeup(args)
  ensureLog()
  if done then return end

  local root = _G and _G.rfsuite
  if type(root) ~= "table" then return end
  local session = root.session
  if type(session) ~= "table" then return end

  if requestSent then return end
  requestSent = true

  -- MSP name API laden
  if not NameApi then
    NameApi = loadModule("tasks/msp/api/name.lua")
  end
  local msp = loadModule("tasks/msp/runtime.lua")
  if not msp or not NameApi then return end

  local mspState = type(msp.getState) == "function" and msp.getState()
  if not mspState or not mspState.queue then
    done = true
    return
  end

  if Log and type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.tasks.name", "MSP request for name (cmd=" .. tostring(NameApi.command) .. ") via queue", "debug", true)
  end

  mspState.queue:add({
    command = NameApi.command,
    simulatorResponse = NameApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(self, buf)
      local data = NameApi.parse(buf)
      if data and data.name then
        session.modelName = data.name
      end
      done = true
      if Log and type(Log.emit) == "function" then
        pcall(Log.emit, "rfsuite.tasks.name", "model name received: " .. tostring(data and data.name), "debug", true)
      end
    end,
    errorHandler = function()
      done = true
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.name", "model name read failed", "warn", true) end
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
