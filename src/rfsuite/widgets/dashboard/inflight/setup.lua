-- What a model must look like before the in-flight tuning overlay can drive it.
--
-- This half of the overlay is shared by two callers with very different budgets. The dashboard
-- widget needs the settings, the radio seam and the trim block; the settings page needs those plus
-- the setup check, and needs them WITHOUT the live state machine and without the adjustment
-- function tables behind it. Keeping them in one file cost the settings page the whole of
-- `drive.lua` and `functions.lua` on entry -- measured at 135 kB of Lua on a desktop interpreter,
-- against 0.1 to 3.9 kB for the project's other settings pages -- on a radio whose tool had 134 kB
-- of heap left, and the tool stopped answering twelve seconds after that page was opened. So the
-- split is not tidiness: it is the page's memory.
--
-- Everything that touches the radio goes through the small table `M.radio()` returns, so a radio
-- that does not offer one of those calls makes this file say less rather than raise.

local M = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require)
if not requireModule then
  local mode = (_G.rfsuite and _G.rfsuite.loadMode) or "bt"
  local rChunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/require.lua", mode)
  if rChunk then
    local ok, res = pcall(rChunk)
    if ok and type(res) == "function" then
      requireModule = res
    end
  end
end
requireModule = requireModule or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local mode = (_G.rfsuite and _G.rfsuite.loadMode) or "bt"
  local chunk = loadScript(fullPath, mode)
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local Log = requireModule("lib/log.lua")

-- The trace of what the overlay wrote, through the logging core: the session ring takes it, and
-- the card sink when logging to card is on. The message is assembled past the gate rather than by
-- the caller, following the idiom widgets/dashboard/runtime.lua uses for its own reload trace --
-- with the test inside the function the callers still paid for a string that was then dropped.
local function logDrive(fmt, ...)
  if not (Log and type(Log.wanted) == "function" and Log.wanted("info")) then return end
  local msg = tostring(fmt)
  if select("#", ...) > 0 then msg = string.format(msg, ...) end
  Log.emit("rfsuite.inflight", msg, "info")
end

-- The same trace, for the half of the overlay that stayed in drive.lua: it has no logger of its
-- own now that the assembly past the gate lives here.
M.log = logDrive

-- What the per-model store holds under [inflight], and what the overlay falls back to when it
-- holds nothing. No global variable is defaulted: a variable this overlay writes has to be one
-- the pilot declared, because writing an arbitrary one would move whatever it already drives.
-- The channels ARE defaulted, to the pair the project's own generic radio setup documents.
M.DEFAULTS = {
  enabled = false,
  switch = 0,
  bank_ch = 11,
  value_ch = 12,
  bank_gvar = 0,
  value_gvar = 0,
  pulse_ms = 150,
  trims = true,
  trim_mode = "rows",
  nav_trim = 2,
  adj_trim = 4,
  row_trim_1 = 2,
  row_trim_2 = 4,
  row_trim_3 = 1,
  row_trim_4 = 3,
  row_trim_5 = 5,
  row_trim_6 = 6,
  backup_profile = 0
}

M.PULSE_MS_MIN = 100
M.PULSE_MS_MAX = 500
M.CHANNEL_MIN = 5
M.CHANNEL_MAX = 16
-- F4 and F7 radios carry nine global variables, H7 fifteen. Nine is what every target has.
M.GVAR_MAX_INDEX = 9
M.TRIM_COUNT = 6
M.PROFILE_MAX = 6

-- The two ways the physical trims reach the parameters.
--
-- `rows` is the reference layout: six trims, six rows, each trim's two directions moving that
-- row's parameter. `navigate` claims two trims instead -- one walks the set and one adjusts what
-- the walk has selected -- which is the route for a radio with four trims and for a pilot who
-- wants one gesture rather than six positions to remember.
M.TRIM_MODE_ROWS = "rows"
M.TRIM_MODE_NAVIGATE = "navigate"

-- TRIM_MODE_NONE, as model.getFlightMode reports it. A row driven from a trim needs the trim
-- switched OFF in the active flight mode, otherwise the same press also moves a stick's neutral.
local TRIM_MODE_NONE = 31

-- A mixer weight naming a global variable is stored as 1024 plus that variable's source index
-- (datastructs_private.h). This is the offset the check reads a weight back through.
local MIX_WEIGHT_GVAR_BASE = 1024
-- MLTPX_ADD, the multiplex mode a plain summed line has.
local MIX_MULTIPLEX_ADD = 0

local function clampNumber(value, low, high, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  if value < low then return low end
  if value > high then return high end
  return math.floor(value + 0.5)
end

-- ---------------------------------------------------------------------------
-- The radio, behind functions
-- ---------------------------------------------------------------------------

local function callGlobal(name, ...)
  local fn = _G and _G[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c
end

-- How many entries the switch walk is allowed to take before it gives up. The firmware's own
-- iterator ends on its own; the bound is here so a stub or a future firmware that does not
-- cannot hang the widget pass.
local SWITCH_WALK_LIMIT = 256

-- How many switch positions one WIDGET pass may take off that walk.
--
-- The whole walk does not fit in a widget pass and must not be attempted in one. `switches()`
-- yields every available position on the radio -- the physical switches, both positions of every
-- trim, the flight modes and every logical switch the model has configured -- and each one costs
-- a call into the firmware plus a table. Run in a startup pass, where the widget is already close
-- to the firmware's per-call instruction limit, the walk overruns it: the pass raises `CPU limit`,
-- the widget entry point catches it and the pass is abandoned before anything below it has run.
-- Measured on a radio: with the overlay enabled the dashboard never left its connection splash,
-- because every pass died in this walk and the build was enqueued in the part of `refresh` that
-- was never reached. The walk is therefore taken in slices and resumed, the way the runtime's own
-- scene build is chunked.
local SWITCH_SLICE = 32

local function modelApi(name)
  local m = _G and _G.model
  if type(m) ~= "table" then return nil end
  local fn = m[name]
  if type(fn) ~= "function" then return nil end
  return fn
end

--- The radio surface the drive uses, and the only place in this file that touches a global.
--
-- Every member answers nil when the firmware does not provide it, so a radio without one of them
-- makes the overlay say less rather than raise inside the widget pass.
function M.radio()
  return {
    now = function()
      return tonumber((callGlobal("getTime"))) or 0
    end,

    -- true while the position is the one the switch rests in, false when it is not, and nil when
    -- this radio does not have that position at all -- which is how a trim the radio lacks is
    -- told apart from a trim nobody is pressing.
    switchValue = function(swsrc)
      return callGlobal("getSwitchValue", swsrc)
    end,

    -- Every switch POSITION the radio offers, in the firmware's own order, as { swsrc, name }.
    -- The trim block is found by walking this rather than by computing an index: the first trim's
    -- position number is not a constant Lua is ever told.
    -- `from` resumes the walk after that position and `budget` bounds what one call takes; with
    -- neither it walks the lot, which is what a Lua PAGE wants and what a widget pass must not do.
    -- Resuming needs no state on this side: the firmware's iterator is a plain function of (last,
    -- index), so handing it back the last position seen continues exactly where it stopped.
    --
    -- Returns the slice and the position to resume AFTER, or nil for "that was the end".
    switchList = function(from, budget)
      local iter, last, first = callGlobal("switches")
      if type(iter) ~= "function" then return nil end
      local list = {}
      local index = from or first
      for _ = 1, (budget or SWITCH_WALK_LIMIT) do
        local ok, nextIndex, name = pcall(iter, last, index)
        if not ok or nextIndex == nil then return list, nil end
        list[#list + 1] = { swsrc = nextIndex, name = name }
        index = nextIndex
      end
      return list, index
    end,

    -- The only member that needs the adjustment-function tables, and it is one the settings page
    -- never calls. Requiring them here rather than at the top of the file is what keeps a page
    -- that only wants the check from paying for functions.lua as well.
    channelUs = function(channel)
      local fns = requireModule("widgets/dashboard/inflight/functions.lua")
      if type(fns) ~= "table" then return nil end
      return fns.channelRawToUs(callGlobal("getValue", "ch" .. tostring(channel)))
    end,

    sensor = function(name)
      return tonumber((callGlobal("getValue", name)))
    end,

    -- getFlightMode() answers with the mode number AND its name, and getSourceIndex and
    -- getValue may grow a second return the same way, so every one of these calls is truncated to
    -- its first value before tonumber sees it. Unparenthesised, the second return lands on
    -- tonumber's BASE argument and the call raises inside the widget pass.
    flightMode = function()
      return tonumber((callGlobal("getFlightMode"))) or 0
    end,

    setGlobalVariable = function(index0, fm, value)
      local fn = modelApi("setGlobalVariable")
      if not fn then return false end
      return pcall(fn, index0, fm, value)
    end,

    globalVariableDetails = function(index0)
      local fn = modelApi("getGlobalVariableDetails")
      if not fn then return nil end
      local ok, details = pcall(fn, index0)
      if not ok or type(details) ~= "table" then return nil end
      return details
    end,

    mixesCount = function(channel)
      local fn = modelApi("getMixesCount")
      if not fn then return nil end
      local ok, count = pcall(fn, channel - 1)
      if not ok then return nil end
      return tonumber(count) or 0
    end,

    mix = function(channel, line0)
      local fn = modelApi("getMix")
      if not fn then return nil end
      local ok, mix = pcall(fn, channel - 1, line0)
      if not ok or type(mix) ~= "table" then return nil end
      return mix
    end,

    flightModeData = function(fm)
      local fn = modelApi("getFlightMode")
      if not fn then return nil end
      local ok, data = pcall(fn, fm)
      if not ok or type(data) ~= "table" then return nil end
      return data
    end,

    sourceIndex = function(name)
      return tonumber((callGlobal("getSourceIndex", name)))
    end,

    mixsrcMax = function()
      return tonumber(_G and _G.MIXSRC_MAX)
    end
  }
end
-- How many switch positions one WIDGET pass may take off the walk; the drive reads it from here.
M.SWITCH_SLICE = SWITCH_SLICE
-- and the ceiling the resumed walk is bounded by, for the same caller.
M.SWITCH_WALK_LIMIT = SWITCH_WALK_LIMIT

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

--- The [inflight] section of the per-model store, filled in and bounded.
--
-- Reading is deliberately forgiving -- a store written by an older build is missing keys rather
-- than wrong -- and bounding is not: a channel or a variable index outside what the radio has
-- would be a write into something else entirely.
function M.loadSettings(modelPreferences)
  local src = nil
  if type(modelPreferences) == "table" and type(modelPreferences.inflight) == "table" then
    src = modelPreferences.inflight
  end
  src = src or {}

  local settings = {
    enabled = src.enabled == true,
    switch = clampNumber(src.switch, -1024, 1024, M.DEFAULTS.switch),
    bank_ch = clampNumber(src.bank_ch, M.CHANNEL_MIN, M.CHANNEL_MAX, M.DEFAULTS.bank_ch),
    value_ch = clampNumber(src.value_ch, M.CHANNEL_MIN, M.CHANNEL_MAX, M.DEFAULTS.value_ch),
    bank_gvar = clampNumber(src.bank_gvar, 0, M.GVAR_MAX_INDEX, M.DEFAULTS.bank_gvar),
    value_gvar = clampNumber(src.value_gvar, 0, M.GVAR_MAX_INDEX, M.DEFAULTS.value_gvar),
    pulse_ms = clampNumber(src.pulse_ms, M.PULSE_MS_MIN, M.PULSE_MS_MAX, M.DEFAULTS.pulse_ms),
    trims = src.trims ~= false,
    trim_mode = (src.trim_mode == M.TRIM_MODE_NAVIGATE) and M.TRIM_MODE_NAVIGATE or M.TRIM_MODE_ROWS,
    nav_trim = clampNumber(src.nav_trim, 0, M.TRIM_COUNT, M.DEFAULTS.nav_trim),
    adj_trim = clampNumber(src.adj_trim, 0, M.TRIM_COUNT, M.DEFAULTS.adj_trim),
    backup_profile = clampNumber(src.backup_profile, 0, M.PROFILE_MAX, M.DEFAULTS.backup_profile)
  }

  settings.rowTrim = {}
  for row = 1, M.TRIM_COUNT do
    local key = "row_trim_" .. tostring(row)
    settings.rowTrim[row] = clampNumber(src[key], 0, M.TRIM_COUNT, M.DEFAULTS[key])
  end

  return settings
end

--- Write the settings back into the shape the store keeps. Scalars only: lib/model_preferences.lua
-- serialises one level of tables and nothing below it.
function M.storeSettings(section, settings)
  if type(section) ~= "table" or type(settings) ~= "table" then return end
  section.enabled = settings.enabled == true
  section.switch = settings.switch or 0
  section.bank_ch = settings.bank_ch
  section.value_ch = settings.value_ch
  section.bank_gvar = settings.bank_gvar
  section.value_gvar = settings.value_gvar
  section.pulse_ms = settings.pulse_ms
  section.trims = settings.trims == true
  section.trim_mode = settings.trim_mode or M.TRIM_MODE_ROWS
  section.nav_trim = settings.nav_trim or 0
  section.adj_trim = settings.adj_trim or 0
  section.backup_profile = settings.backup_profile
  for row = 1, M.TRIM_COUNT do
    section["row_trim_" .. tostring(row)] = (settings.rowTrim and settings.rowTrim[row]) or 0
  end
end

-- ---------------------------------------------------------------------------
-- The trim block
-- ---------------------------------------------------------------------------

local function endsWith(name, char)
  if type(name) ~= "string" or name == "" then return false end
  return string.sub(name, -1) == char
end

--- The radio's trim positions, resolved by walking the switch list.
--
-- The firmware names a trim position `<trim label><+|->`, the label being the localised and
-- renameable short label of the stick it belongs to (strhelpers.cpp), so no stem can be
-- hard-coded. The positions come in pairs, the even one decrementing; a radio with four trims
-- simply does not offer the last two, and they are absent from the list rather than false.
--
-- The middle position of a three-position switch is also spelled with a hyphen, which is why a
-- run is accepted only when it is at least one whole pair long and alternates minus, plus from
-- its start -- a lone `SA-` between two arrow-spelled positions can never satisfy that.
function M.resolveTrims(radio)
  local list = radio and type(radio.switchList) == "function" and radio.switchList() or nil
  return M.trimsFromList(list)
end

--- The same analysis over a list that has already been read, in one slice or in several.
--
-- Kept apart from the walk above because the two have different budgets: a Lua page reads the
-- whole list in one call and analyses it there, while a widget pass reads it a slice at a time
-- and analyses it once, on the pass that completes it.
function M.trimsFromList(list)
  if type(list) ~= "table" or #list == 0 then return nil end

  local bestStart, bestLength = nil, 0
  local index = 1
  while index <= #list do
    local length = 0
    while index + length <= #list do
      local name = list[index + length].name
      local wanted = (length % 2 == 0) and "-" or "+"
      if not endsWith(name, wanted) then break end
      length = length + 1
    end
    if length >= 2 then
      local pairs2 = length - (length % 2)
      if pairs2 > bestLength then
        bestStart, bestLength = index, pairs2
      end
      index = index + length
    else
      index = index + 1
    end
  end

  if bestStart == nil then return nil end

  local trims = {}
  for trim = 1, bestLength // 2 do
    local entry = list[bestStart + (trim - 1) * 2]
    local plus = list[bestStart + (trim - 1) * 2 + 1]
    local name = entry.name
    if type(name) == "string" and #name > 1 then
      name = string.sub(name, 1, #name - 1)
    end
    trims[trim] = { name = name, minus = entry.swsrc, plus = plus.swsrc }
  end
  return trims
end

-- ---------------------------------------------------------------------------
-- The setup check
-- ---------------------------------------------------------------------------

local function checkGvarDetails(radio, index, faults, prefix)
  local details = radio.globalVariableDetails(index - 1)
  if details == nil then return end
  if tonumber(details.prec) ~= 0 then
    -- With one decimal the mixer divides the weight by ten (mixer.cpp), so every step lands at a
    -- tenth of the window it was aimed at and nothing ever fires.
    faults[#faults + 1] = prefix .. "_gvar_prec"
  end
  local min = tonumber(details.min)
  local max = tonumber(details.max)
  if (min ~= nil and min > -100) or (max ~= nil and max < 100) then
    faults[#faults + 1] = prefix .. "_gvar_range"
  end
end

local function checkMixLine(radio, channel, gvarIndex, faults, prefix)
  local count = radio.mixesCount(channel)
  if count == nil then return false end
  if count == 0 then
    faults[#faults + 1] = prefix .. "_mix_missing"
    return true
  end
  if count > 1 then
    faults[#faults + 1] = prefix .. "_mix_count"
  end
  local mix = radio.mix(channel, 0)
  if type(mix) ~= "table" then
    faults[#faults + 1] = prefix .. "_mix_missing"
    return true
  end
  local mixsrcMax = radio.mixsrcMax()
  if mixsrcMax ~= nil and tonumber(mix.source) ~= mixsrcMax then
    faults[#faults + 1] = prefix .. "_mix_source"
  end
  local sourceIndex = radio.sourceIndex("GV" .. tostring(gvarIndex))
  if sourceIndex ~= nil and tonumber(mix.weight) ~= (MIX_WEIGHT_GVAR_BASE + sourceIndex) then
    faults[#faults + 1] = prefix .. "_mix_weight"
  end
  if tonumber(mix.multiplex) ~= MIX_MULTIPLEX_ADD then
    faults[#faults + 1] = prefix .. "_mix_multiplex"
  end
  if tonumber(mix.switch) ~= 0 then
    faults[#faults + 1] = prefix .. "_mix_switch"
  end
  return true
end

--- What is missing between this model and a working overlay.
--
-- Answers "ok", a list of named faults, or nil for UNCHECKED -- and the third is not the same as
-- the first. A radio whose Lua does not offer the mixer reader cannot be told apart from a
-- correct model by anything here, and reporting that as correct is the failure this return value
-- exists to prevent.
--
-- Nothing is written. The overlay reports what a model lacks and leaves authoring it to the
-- pilot, because a mixer line written behind a pilot's back is a control surface moving for a
-- reason nobody can find later.
function M.check(drive, settings)
  if type(drive) ~= "table" then return nil end
  settings = settings or drive.settings
  if type(settings) ~= "table" then return nil end
  local radio = drive.radio
  if type(radio) ~= "table" then return nil end

  local faults = {}
  if (settings.switch or 0) == 0 then faults[#faults + 1] = "no_switch" end
  if (settings.bank_gvar or 0) <= 0 then faults[#faults + 1] = "no_bank_gvar" end
  if (settings.value_gvar or 0) <= 0 then faults[#faults + 1] = "no_value_gvar" end

  local looked = false
  if (settings.bank_gvar or 0) > 0 then
    checkGvarDetails(radio, settings.bank_gvar, faults, "bank")
    looked = checkMixLine(radio, settings.bank_ch, settings.bank_gvar, faults, "bank") or looked
  end
  if (settings.value_gvar or 0) > 0 then
    checkGvarDetails(radio, settings.value_gvar, faults, "value")
    looked = checkMixLine(radio, settings.value_ch, settings.value_gvar, faults, "value") or looked
  end

  -- A trim driving a row must be OFF as a trim in the active flight mode. Left on, the same press
  -- moves the stick neutral the flight controller was calibrated against.
  if settings.trims == true then
    -- Which trims this configuration actually claims, and under what name a fault would be
    -- reported. In navigate mode two trims do the work and every other one is inert, so checking
    -- the six row assignments there would report on trims nothing reads.
    local claimed = {}
    if settings.trim_mode == M.TRIM_MODE_NAVIGATE then
      local nav = settings.nav_trim or 0
      local adj = settings.adj_trim or 0
      if nav == 0 or adj == 0 then
        faults[#faults + 1] = "no_nav_trim"
      elseif nav == adj then
        -- One trim cannot both walk the set and move the parameter: whichever ran first would
        -- decide, and which one that is nobody could tell from the screen.
        faults[#faults + 1] = "trim_claimed_twice"
      end
      if nav > 0 then claimed[#claimed + 1] = { index = nav, code = "trim_mode_nav" } end
      if adj > 0 then claimed[#claimed + 1] = { index = adj, code = "trim_mode_adj" } end
    else
      for row = 1, M.TRIM_COUNT do
        local index = settings.rowTrim and settings.rowTrim[row] or 0
        if index > 0 then
          claimed[#claimed + 1] = { index = index, code = "trim_mode_" .. tostring(row) }
        end
      end
    end

    local data = radio.flightModeData(radio.flightMode())
    if type(data) == "table" and type(data.trimsModes) == "table" then
      looked = true
      for i = 1, #claimed do
        local mode = tonumber(data.trimsModes[claimed[i].index])
        if mode ~= nil and mode ~= TRIM_MODE_NONE then
          faults[#faults + 1] = claimed[i].code
        end
      end
    end
  end

  if #faults > 0 then return faults end
  if not looked then return nil end
  return "ok"
end

return M
