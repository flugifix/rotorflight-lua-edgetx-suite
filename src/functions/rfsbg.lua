-- Background decoder for the flight controller's custom telemetry, as a special function.
--
-- The same drain the dashboard and the service widget run, moved into the radio's script
-- state. What that buys is the billing: a widget call is cut off at a fixed instruction count,
-- while a call in the script state is yielded when it has held the interpreter for one task
-- period and resumed on the next turn. So this host decodes every frame it pops, where a
-- widget pass has to leave the older half of a backlog behind.
--
-- It publishes a moving counter in a shared-memory slot while it runs, and the suite's own
-- passes read that and step aside. Nothing here is required: a radio without the special
-- function, or one where the script has stopped, is a radio where the widget drains exactly
-- as it always did.
--
-- Install it as a special function: FUNC_PLAY_SCRIPT on a switch that is always on, with the
-- repetition set to zero so that run() is called on every cycle rather than once per switch
-- edge. tasks/events/onconnect/tasks/function_script.lua does that at connect.

local BASE_PATH = "/SCRIPTS/TOOLS/rfsuite-core/"

local Log = nil
local Preferences = nil
local Drain = nil
local Adjustments = nil
local initialized = false

-- Tasks read their settings from rfsuite.preferences, and that table belongs to one Lua state.
-- Re-read on an interval so a setting changed in the configuration tool takes effect without a
-- restart. There is no armed gate: nothing in this state knows whether the model is armed, and
-- a read that is yielded rather than killed costs nothing that matters here.
local PREFERENCES_INTERVAL_SECONDS = 30

-- How often the heap line below is written. It is the figure the whole arrangement has to be
-- judged on: the firmware sums the script state and the widget state against one Lua memory
-- ceiling, so work moved from one to the other relieves nothing by itself.
local HEAP_REPORT_INTERVAL_SECONDS = 30

local lastPreferencesLoad = nil
local lastHeapReport = nil

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, v = pcall(getTime)
    if ok and type(v) == "number" then return v / 100 end
  end
  return 0
end

-- The suite's own memoizer where this state already has one, and a plain load where it does
-- not. Nothing else of the suite runs in the script state today -- the configuration tool has
-- a state of its own -- so the memoizer is normally the one init() below has just loaded.
local function loadModule(path)
  local req = _G.rfsuite and _G.rfsuite.require
  if type(req) == "function" then
    local ok, mod = pcall(req, path)
    if ok and type(mod) == "table" then return mod end
  end
  local chunk = loadScript(BASE_PATH .. path, (_G.rfsuite and _G.rfsuite.loadMode) or "bt")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

-- One pass of its own, and no work in it. Every module below pulls in a subtree -- the decoder
-- table, the CRSF multiplexer, the logger, the audio pack resolver -- and the first turn of a
-- freshly loaded script is not the turn to drain a backlog on as well.
local function init()
  if type(_G.rfsuite) ~= "table" or type(_G.rfsuite.require) ~= "function" then
    local chunk = loadScript(BASE_PATH .. "lib/require.lua", "bt")
    if type(chunk) == "function" then pcall(chunk) end
  end

  Log = loadModule("lib/log.lua")
  Preferences = loadModule("lib/preferences.lua")
  Drain = loadModule("tasks/events/telemetry_bg/drain.lua")
  Adjustments = loadModule("tasks/events/telemetry_bg/adjustments.lua")
  initialized = true
end

local function refreshPreferences(now)
  if not Preferences or type(Preferences.load) ~= "function" then return end
  if lastPreferencesLoad and (now - lastPreferencesLoad) < PREFERENCES_INTERVAL_SECONDS then return end
  lastPreferencesLoad = now

  local ok, prefs = pcall(Preferences.load)
  if ok and type(prefs) == "table" then
    _G.rfsuite = _G.rfsuite or {}
    _G.rfsuite.preferences = prefs
  end
end

-- collectgarbage("count") answers in kilobytes as a float, and string.format("%d", ...) refuses
-- a float that is not an exact integer in this Lua -- so it is floored here rather than left to
-- raise inside the formatter, where the message would silently come out as its own format
-- string.
local function traceHeap(now)
  if not Log or type(Log.emitf) ~= "function" then return end
  if lastHeapReport and (now - lastHeapReport) < HEAP_REPORT_INTERVAL_SECONDS then return end
  lastHeapReport = now

  Log.emitf("rfsuite.functions", "trace", "heap %d kB", math.floor(collectgarbage("count")))
end

local function run()
  if not initialized then
    init()
    return
  end

  local now = nowSeconds()
  refreshPreferences(now)

  if Drain then
    -- Before the work, not after it. A reader has to be able to tell "this is running" from
    -- "this last finished a pass", and only a bump ahead of the work keeps moving while a
    -- pass is long. A pass that then fails stops the counter, which is exactly the signal the
    -- other decoders fall back on.
    Drain.publishLiveness()
    Drain.wakeup(now, true)
  end

  -- After the decode, never before it: what the teller reads is what the drain has just
  -- published, so the other order would announce one pass behind.
  if Adjustments and type(Adjustments.wakeup) == "function" then
    Adjustments.wakeup()
  end

  traceHeap(now)
end

return { run = run }
