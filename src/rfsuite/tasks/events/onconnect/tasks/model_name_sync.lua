-- OnConnect task: put the craft name the flight controller reports onto the radio's model,
-- when the "Synchronize Model Name" setting asks for it -- and put the model's own name back
-- when the link goes.
--
-- Runs after the `name` task in the manifest, which is what fills session.modelName.
--
-- The rename is TEMPORARY: the name the model had is remembered before it is overwritten and
-- restored at disconnect, so a pilot who flies one model with a craft plugged in does not find
-- it permanently renamed afterwards. The name is remembered in two places on purpose. The
-- module-local is what the in-session restore uses, so that path can never depend on a store
-- being reachable; the per-model preference file is the backstop for the one case the local
-- cannot cover -- the radio switched off while still connected, where nothing gets to run a
-- disconnect at all.

local M = {}

local done = false
local Log = nil
local ModelPreferences = nil

-- Where the previous name is kept in the per-model store. The store merges its defaults into
-- whatever is on disk without dropping anything it does not declare, so this section needs no
-- entry in defaultModelPreferences() to survive a load.
local STORE_SECTION = "model"
local STORE_KEY = "previous_name"

--: The name this model had before the craft name was written over it, for as long as the link
--: lasts. `nil` means nothing has been renamed and there is nothing to put back.
local previousName = nil

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
    pcall(Log.emit, "rfsuite.tasks.model_name_sync", msg, level or "debug", true)
  end
end

local function isTruthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

-- WHO decides, and it is not always the radio.
--
-- From MSP API 12.09 the flight controller carries a MODEL_SET_NAME bit in its pilot config
-- (`src/main/pg/pilot.h`), and that bit is the answer: the craft says whether it wants the
-- radio's model named after it, so the same helicopter behaves the same way on any transmitter.
-- The `model_params_sync` task reads the message one step earlier and parks it in the session.
--
-- Below 12.09 there is no such field -- `model_flags` is nil rather than zero, which is why the
-- API wrapper is careful to keep those apart -- and the radio-side setting is then the only
-- thing that can decide. It stays, as the fallback it now is.
local function syncEnabled()
  local root = _G and _G.rfsuite
  local session = type(root) == "table" and root.session or nil
  local pilot = type(session) == "table" and session.pilotConfig or nil
  local flags = type(pilot) == "table" and pilot.model_flags or nil

  if flags ~= nil then
    local Api = loadModule("tasks/msp/api/pilot_config.lua")
    if type(Api) == "table" and type(Api.flagSet) == "function" then
      local wanted = Api.flagSet(flags, Api.FLAG_SET_NAME)
      if wanted ~= nil then
        log("MODEL_SET_NAME from the flight controller: " .. tostring(wanted), "debug")
        return wanted
      end
    end
  end

  local prefs = type(root) == "table" and root.preferences or nil
  local general = type(prefs) == "table" and prefs.general or nil
  return isTruthy(general and general.syncname)
end

local function session()
  local root = _G and _G.rfsuite
  return type(root) == "table" and root.session or nil
end

-- The store, and both halves are best-effort: a model whose flight controller has not reported
-- its id yet has nowhere to keep this, and that is a reason to skip the backstop rather than to
-- skip the feature.
local function storeGet()
  local s = session()
  local prefs = s and s.modelPreferences
  local section = type(prefs) == "table" and prefs[STORE_SECTION] or nil
  local name = type(section) == "table" and section[STORE_KEY] or nil
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

local function storeSet(name)
  local s = session()
  local prefs = s and s.modelPreferences
  if type(prefs) ~= "table" or type(s.mcu_id) ~= "string" or s.mcu_id == "" then return end
  if type(prefs[STORE_SECTION]) ~= "table" then prefs[STORE_SECTION] = {} end
  prefs[STORE_SECTION][STORE_KEY] = name or ""
  if ModelPreferences == nil then
    ModelPreferences = loadModule("lib/model_preferences.lua") or false
  end
  if type(ModelPreferences) == "table" and type(ModelPreferences.saveByMcuId) == "function" then
    pcall(ModelPreferences.saveByMcuId, s.mcu_id, prefs)
  end
end

local function setModelName(name)
  if type(model) ~= "table" or type(model.getInfo) ~= "function" or type(model.setInfo) ~= "function" then
    return false
  end
  local ok, info = pcall(model.getInfo)
  if not ok or type(info) ~= "table" then return false end
  if info.name == name then return true end
  info.name = name
  return pcall(model.setInfo, info) == true
end

function M.wakeup()
  if done then return end

  local root = _G and _G.rfsuite
  local session = type(root) == "table" and root.session or nil
  if type(session) ~= "table" then return end

  -- Every exit below sets done: this task waits for nothing of its own, and a task that never
  -- completes holds the whole connect chain behind it.
  done = true

  if not syncEnabled() then return end

  local craftName = session.modelName
  if type(craftName) ~= "string" or craftName == "" then
    log("no craft name to synchronize", "debug")
    return
  end

  if type(model) ~= "table" or type(model.getInfo) ~= "function" or type(model.setInfo) ~= "function" then
    return
  end

  local ok, info = pcall(model.getInfo)
  if not ok or type(info) ~= "table" then return end

  -- A name already in the store is a rename that never got its restore -- the radio was switched
  -- off while connected. It, and not what the model is called right now, is what this model is
  -- really called; taking the current name here would write the craft name in as the original
  -- and lose the pilot's own for good.
  previousName = storeGet() or info.name

  if info.name == craftName then
    log("model is already called " .. tostring(craftName), "debug")
    return
  end

  if previousName == craftName then
    -- Nothing to put back that is not what is being written. Do not remember it.
    previousName = nil
    storeSet(nil)
  else
    storeSet(previousName)
  end

  local written = setModelName(craftName)
  log("model name set from craft name: " .. tostring(craftName) .. " (ok=" .. tostring(written) ..
      ", was " .. tostring(previousName) .. ")", "info")
end

function M.isComplete()
  return done
end

-- `reset` is the disconnect hook: `publishConnected(false)` calls it on every runner, and it
-- sets `session.isConnected` false BEFORE that loop. It is not ONLY the disconnect hook, which
-- is the part worth guarding -- `Events.rerunOnconnect()` calls it too, after a reboot, with the
-- link up and coming back. Restoring there would make the name flap. So the restore is gated on
-- the session, which is the one thing that tells the two apart.
function M.reset()
  done = false

  local s = session()
  if s and s.isConnected == true then return end

  local restore = previousName or storeGet()
  if restore == nil then return end

  local written = setModelName(restore)
  log("model name put back: " .. tostring(restore) .. " (ok=" .. tostring(written) .. ")", "info")
  previousName = nil
  storeSet(nil)
end

return M
