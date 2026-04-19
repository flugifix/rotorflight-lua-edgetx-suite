--[[
  Lightweight events manager for RFSuite (EdgeTX port)
  - Monitors MSP runtime and sets `rfsuite.session.isConnected` with hysteresis
  - Minimal dependency set to avoid heavy startup costs
]]

if type(_G) == "table" and type(_G.__rfsuite_events_module) == "table" then
  return _G.__rfsuite_events_module
end

local Events = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local MspRuntime = nil
local Log = nil

-- Per-category task runners cache will be stored at `_G.rfsuite.tasks.events`
local function ensureEventRunner(name)
  if type(name) ~= "string" then return nil end
  _G.rfsuite = _G.rfsuite or {}
  _G.rfsuite.tasks = _G.rfsuite.tasks or {}
  _G.rfsuite.tasks.events = _G.rfsuite.tasks.events or {}
  local cached = _G.rfsuite.tasks.events[name]
  if type(cached) == "table" then return cached end
  if cached == false then return nil end

  local ok, mod = pcall(function()
    return loadModule("tasks/events/" .. name .. "/tasks.lua")
  end)
  if not ok or type(mod) ~= "table" then
    if Log and type(Log.emit) == "function" then
      pcall(Log.emit, "rfsuite.events", "no runner for events/" .. tostring(name), "debug", true)
    end
    _G.rfsuite.tasks.events[name] = false
    return nil
  end

  _G.rfsuite.tasks.events[name] = mod
  return mod
end

local CONNECT_STABLE_SECONDS = 0.6
local DISCONNECT_STABLE_SECONDS = 0.8

local state = {
  linkUpSince = nil,
  linkDownSince = nil,
  linkStableUp = false,
  lastArmed = nil,
}

local function ensureDeps()
  if not MspRuntime then MspRuntime = loadModule("tasks/msp/runtime.lua") end
  if not Log then Log = loadModule("lib/log.lua") end
end

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, v = pcall(getTime)
    if ok and type(v) == "number" then return v / 100 end
  end
  if type(os) == "table" and type(os.clock) == "function" then return os.clock() end
  return 0
end

local function ensureSession()
  _G.rfsuite = _G.rfsuite or {}
  _G.rfsuite.session = _G.rfsuite.session or {}
end

local function publishConnected(val)
  ensureSession()
  local session = _G.rfsuite.session
  if session.isConnected == val then return end
  session.isConnected = val
  if Log and type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.events", "session.isConnected=" .. tostring(val), "info", true)
  end
end

function Events.reset()
  state.linkUpSince = nil
  state.linkDownSince = nil
  state.linkStableUp = false
  ensureSession()
  _G.rfsuite.session.isConnected = false
end

function Events.wakeup()
  ensureDeps()
  if not MspRuntime or type(MspRuntime.getState) ~= "function" then return end
  local mspState = MspRuntime.getState()
  if type(mspState) ~= "table" then return end

  local connected = mspState.lastConnected == true
  local t = nowSeconds()

  if connected then
    state.linkDownSince = nil
    if not state.linkUpSince then state.linkUpSince = t end
    if not state.linkStableUp and (t - state.linkUpSince) >= CONNECT_STABLE_SECONDS then
      state.linkStableUp = true
      publishConnected(true)
    end
  else
    state.linkUpSince = nil
    if not state.linkDownSince then state.linkDownSince = t end
    if state.linkStableUp and (t - state.linkDownSince) >= DISCONNECT_STABLE_SECONDS then
      state.linkStableUp = false
      publishConnected(false)
    end
  end
  -- Trigger per-category runners
  do
    -- onconnect: call runner while linkStableUp is true (runner progresses internally)
    if state.linkStableUp then
      local onconnect = ensureEventRunner("onconnect")
      if onconnect and type(onconnect.wakeup) == "function" then
        pcall(onconnect.wakeup)
      end
    end

    -- arm/ disarm transitions: detect changes and call corresponding runners
    local armed = mspState and mspState.lastArmed == true
    if state.lastArmed == nil then
      state.lastArmed = armed
    end
    if armed ~= state.lastArmed then
      state.lastArmed = armed
      if armed then
        local onarm = ensureEventRunner("onarm")
        if onarm and type(onarm.wakeup) == "function" then
          pcall(onarm.wakeup)
        end
      else
        local ondisarm = ensureEventRunner("ondisarm")
        if ondisarm and type(ondisarm.wakeup) == "function" then
          pcall(ondisarm.wakeup)
        end
      end
    end
  end
end

if type(_G) == "table" then
  _G.__rfsuite_events_module = Events
end

return Events
