-- OnDisarm task: flight_stats auslesen (nur fuer Widget-Kontext)
local M = {}


local done = false
local requestSent = false
local flightStats = nil
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
  if done then
    if Log and type(Log.emit) == "function" then
      pcall(Log.emit, "rfsuite.tasks.flight_stats", "wakeup: already done", "debug", true)
    end
    return
  end

  -- Kontext pruefen: Nur fuer Widget-Kontext ausfuehren
  local context = args and args.context or "tool"
  local origContext = context
  local sessionContext = (_G and _G.rfsuite and _G.rfsuite.session and _G.rfsuite.session.event_context) or nil
  if not context or context == "tool" then
    context = sessionContext or context
  end
  if Log and type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.tasks.flight_stats", "ondisarm flight_stats.wakeup called, context=" .. tostring(context) .. ", origContext=" .. tostring(origContext) .. ", sessionContext=" .. tostring(sessionContext), "debug", true)
  end
  if context ~= "widget" and context ~= "both" then
    done = true
    if Log and type(Log.emit) == "function" then
      pcall(Log.emit, "rfsuite.tasks.flight_stats", "flight_stats.wakeup skipped (context)", "debug", true)
    end
    return
  end

  local root = _G and _G.rfsuite
  if type(root) ~= "table" then return end
  local session = root.session
  if type(session) ~= "table" then return end

  if requestSent then
    if Log and type(Log.emit) == "function" then
      pcall(Log.emit, "rfsuite.tasks.flight_stats", "wakeup: already requestSent", "debug", true)
    end
    return
  end
  requestSent = true

  -- MSP flight_stats API laden
  if not flightStats then
    flightStats = loadModule("tasks/msp/api/flight_stats.lua")
  end
  local msp = loadModule("tasks/msp/runtime.lua")
  if not msp or not flightStats then
    if Log and type(Log.emit) == "function" then
      pcall(Log.emit, "rfsuite.tasks.flight_stats", "flight_stats or msp runtime not loaded", "warn", true)
    end
    return
  end

  local mspState = type(msp.getState) == "function" and msp.getState()
  if not mspState or not mspState.queue then
    done = true
    if Log and type(Log.emit) == "function" then
      pcall(Log.emit, "rfsuite.tasks.flight_stats", "mspState or queue missing", "warn", true)
    end
    return
  end

  if Log and type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.tasks.flight_stats", "MSP request for flight_stats (cmd=" .. tostring(flightStats.command) .. ") via queue", "debug", true)
  end

  mspState.queue:add({
    command = flightStats.command,
    simulatorResponse = flightStats.simulatorResponse,
    timeout = 5.0,
    processReply = function(self, buf)
      local stats = flightStats.parse(buf)
      if stats and stats.flightcount then
        session.flightcount = stats.flightcount
      end
      done = true
      if Log and type(Log.emit) == "function" then
        pcall(Log.emit, "rfsuite.tasks.flight_stats", "flight_stats received: " .. tostring(stats and stats.flightcount), "debug", true)
      end
    end,
    errorHandler = function()
      done = true
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.flight_stats", "flight_stats read failed", "warn", true) end
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
