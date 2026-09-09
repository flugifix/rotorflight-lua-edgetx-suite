-- OnConnect task: give this model the special function that runs the background decoder.
--
-- SCRIPTS/FUNCTIONS/rfsbg.lua only runs if a special function calls it, and a pilot cannot be
-- expected to add one by hand for a script the suite installed. So the suite adds it, once per
-- model, on the first connect that model ever makes.
--
-- Once, and never again for that model: the EdgeTX model file names it has written into are
-- remembered in the per-model preferences, and a name that is listed is never revisited. A
-- pilot who deletes the special function has said what they want, and this must not be a task
-- that puts it back on the next flight.
--
-- The slot becomes active the next time the model is loaded, because the firmware reads the
-- special functions when it loads a model. That is the whole reason there is no on-screen
-- notice here: there is nothing for the pilot to do, and the next model load is free.
--
-- `widget` context, like the two tasks beside it in the manifest that reach outside the suite:
-- writing to the pilot's model is background work, not something a configuration tool should do
-- because somebody opened a settings page.

local M = {}

-- The base name EdgeTX stores in the special function, and the file it looks for under
-- SCRIPTS/FUNCTIONS. The firmware's field holds eight characters.
local SCRIPT_NAME = "rfsbg"

-- Where the memory lives in the per-model preferences: one key, the model file names this has
-- installed into, comma separated.
local PREF_SECTION = "functions"
local PREF_KEY = "installed_models"

-- radio/src/dataconstants.h, MAX_SPECIAL_FUNCTIONS.
local SPECIAL_FUNCTION_COUNT = 64

-- How many slots one wakeup reads. The whole connect chain runs inside a single widget pass and
-- that pass is the closest any pass comes to the firmware's per-call instruction limit, so the
-- walk is spread: the runner calls this task again on the next pass while it says it is not
-- complete, and eight passes cover every slot.
local SLOTS_PER_WAKEUP = 8

-- The switch position that is always on. Resolved by NAME, and the name is translated on the
-- radio -- so a radio in a language that spells it differently resolves nothing, and then this
-- task writes nothing at all rather than guessing an index.
local ALWAYS_ON_SWITCH = "ON"

local done = false
local started = false
local nextSlot = 0
local firstFreeSlot = nil
local modelFile = nil
local taggedLog = nil

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

-- The logging core's tagged emitter, bound on first use: the default level and the
-- console flag are lib/log.lua's, and this file states only its tag.
local function log(msg, level)
  if not taggedLog then
    local rf = _G.rfsuite
    local L = rf and rf.Log
    if type(L) ~= "table" or type(L.tagged) ~= "function" then return end
    taggedLog = L.tagged("rfsuite.tasks.function_script")
  end
  taggedLog(msg, level)
end

local function finish(msg, level)
  if msg then log(msg, level or "info") end
  done = true
end

--- The EdgeTX file this model is stored in, which is what identifies it here.
--
-- Not the model NAME: two models may carry the same name, and renaming one would make this
-- forget that it had already been here.
local function currentModelFile()
  if type(model) ~= "table" or type(model.getInfo) ~= "function" then return nil end
  local ok, info = pcall(model.getInfo)
  if not ok or type(info) ~= "table" then return nil end
  local name = info.filename
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

local function installedList(prefs)
  local section = type(prefs) == "table" and prefs[PREF_SECTION] or nil
  local value = type(section) == "table" and section[PREF_KEY] or nil
  if value == nil then return "" end
  return tostring(value)
end

local function listContains(list, name)
  for entry in string.gmatch(list, "[^,]+") do
    if entry == name then return true end
  end
  return false
end

local function remember(session, name)
  local prefs = session.modelPreferences
  if type(prefs) ~= "table" then return end

  local list = installedList(prefs)
  prefs[PREF_SECTION] = type(prefs[PREF_SECTION]) == "table" and prefs[PREF_SECTION] or {}
  prefs[PREF_SECTION][PREF_KEY] = (list == "") and name or (list .. "," .. name)

  local store = loadModule("lib/model_preferences.lua")
  if store and type(store.saveByMcuId) == "function" then
    pcall(store.saveByMcuId, session.mcu_id, prefs)
  end
end

--- Read up to SLOTS_PER_WAKEUP slots; true if the script is already in one of them.
--
-- An EMPTY slot is one whose switch is unset. The function number cannot say it: a cleared slot
-- reads back as function 0, which is a real function (override a channel), so a test on the
-- function would take the first cleared slot for one the pilot had configured.
local function walk()
  local last = math.min(nextSlot + SLOTS_PER_WAKEUP, SPECIAL_FUNCTION_COUNT) - 1
  for i = nextSlot, last do
    local ok, fn = pcall(model.getCustomFunction, i)
    if ok and type(fn) == "table" then
      if fn.func == FUNC_PLAY_SCRIPT and fn.name == SCRIPT_NAME then
        return true
      end
      if firstFreeSlot == nil and fn.switch == 0 then
        firstFreeSlot = i
      end
    end
  end
  nextSlot = last + 1
  return false
end

local function install(session)
  local switch = getSwitchIndex(ALWAYS_ON_SWITCH)
  if type(switch) ~= "number" or switch == 0 then
    finish("no always-on switch under the name '" .. ALWAYS_ON_SWITCH ..
      "'; the background decoder's special function was not created")
    return
  end

  local ok = pcall(model.setCustomFunction, firstFreeSlot, {
    switch = switch,
    func = FUNC_PLAY_SCRIPT,
    name = SCRIPT_NAME,
    active = 1,
    -- Zero is what makes the firmware call the script on every cycle. Any other value makes it
    -- a one-shot on the switch going true, which for an always-on switch is once per model load.
    repetition = 0
  })
  if not ok then
    finish("could not write the background decoder's special function")
    return
  end

  remember(session, modelFile)
  finish("background decoder installed in special function " .. tostring(firstFreeSlot + 1) ..
    ", active the next time this model is loaded")
end

function M.wakeup()
  if done then return end

  local root = _G and _G.rfsuite
  local session = type(root) == "table" and root.session or nil
  if type(session) ~= "table" then return end
  -- After `uid`, which is what fills both of these in.
  if not session.mcu_id or session.mcu_id == "" then return end
  if type(session.modelPreferences) ~= "table" then return end

  if not started then
    started = true

    modelFile = currentModelFile()
    if not modelFile then
      finish("the radio does not name the model's file; the background decoder's special " ..
        "function was not created")
      return
    end

    -- The cheap path, and the one every connect after the first takes: this model has been
    -- here before, so nothing is read and nothing is written.
    if listContains(installedList(session.modelPreferences), modelFile) then
      done = true
      return
    end

    if type(model) ~= "table" or type(model.getCustomFunction) ~= "function"
      or type(model.setCustomFunction) ~= "function" or type(FUNC_PLAY_SCRIPT) ~= "number"
      or type(getSwitchIndex) ~= "function" then
      finish("this radio has no special-function scripting; the background decoder was not " ..
        "installed", "debug")
      return
    end
  end

  local present = walk()
  if present then
    -- Somebody already put it there. Nothing to do, and nothing to remember either: the memory
    -- records what this task has written, so that what it wrote is never written twice.
    done = true
    return
  end
  if nextSlot < SPECIAL_FUNCTION_COUNT then return end

  if firstFreeSlot == nil then
    finish("every special function slot on this model is in use; the background decoder was " ..
      "not installed")
    return
  end

  install(session)
end

function M.isComplete()
  return done
end

function M.reset()
  done = false
  started = false
  nextSlot = 0
  firstFreeSlot = nil
  modelFile = nil
end

return M
