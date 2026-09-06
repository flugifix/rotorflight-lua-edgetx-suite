-- The in-flight tuning drive: what the overlay does to the radio, and when it is allowed to.
--
-- The flight controller's stepped adjustments are reached through two global variables that a
-- mixer line each puts on the enable and the value channel. This module owns those two writes and
-- nothing else. It never speaks MSP -- tasks/msp/runtime.lua clears its own queue on every armed
-- tick, so a write attempted in flight would be dropped without a word -- and it never writes the
-- model: mixer lines, global variable details and trim modes are CHECKED here and reported, never
-- authored.
--
-- Everything that touches the radio goes through the small table `M.radio()` returns, so the
-- state machine can be driven under a plain Lua interpreter with those functions replaced.
--
-- The safety rule the whole file is built around: the value variable is 0 whenever no pulse is
-- running and nothing is held, including after EVERY way out of the overlay. `cleanup` is cheap
-- and idempotent for exactly that reason -- it is run on every transition away rather than on the
-- one transition that happened to be observed.

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

local Functions = requireModule("widgets/dashboard/inflight/functions.lua")
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

-- A switch has to hold its new reading this long before the overlay believes it. It is not a
-- debounce for the switch, which does not bounce: it is the margin against a pilot brushing the
-- interlock on the way to something else.
local STABILITY_TICKS = 30

-- The walk is EDGE triggered: one press, one parameter. A trim held on purpose then repeats, after
-- a delay long enough that a single press can never produce two steps, at a rate a pilot can still
-- count while looking somewhere else.
local NAV_REPEAT_DELAY_TICKS = 50
local NAV_REPEAT_INTERVAL_TICKS = 33

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
    switchList = function()
      local iter, last, first = callGlobal("switches")
      if type(iter) ~= "function" then return nil end
      local list = {}
      local index = first
      for _ = 1, SWITCH_WALK_LIMIT do
        local ok, nextIndex, name = pcall(iter, last, index)
        if not ok or nextIndex == nil then break end
        list[#list + 1] = { swsrc = nextIndex, name = name }
        index = nextIndex
      end
      return list
    end,

    channelUs = function(channel)
      return Functions.channelRawToUs(callGlobal("getValue", "ch" .. tostring(channel)))
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
-- The drive
-- ---------------------------------------------------------------------------

local Drive = {}
Drive.__index = Drive

--- A drive with no history: nothing seeded, nothing written, no bank chosen.
function M.newDrive(radio, settings)
  local self = setmetatable({}, Drive)
  self.radio = radio or M.radio()
  self.settings = settings or M.loadSettings(nil)
  self.live = false
  self.seeded = false
  self.rawSwitch = nil
  self.rawSince = nil
  self.bank = 1
  self.row = 1
  self.bands = Functions.REFERENCE_BANDS
  self.bankValues = Functions.REFERENCE_BAND_GV
  self.set = Functions.REFERENCE_SET
  self.bankShown = nil
  self.written = 0
  self.writtenFm = nil
  self.bankWritten = nil
  self.pulseCode = nil
  self.pulseUntil = nil
  self.coolUntil = 0
  self.holdRow = nil
  self.holdUp = nil
  self.trimRow = nil
  self.trimUp = nil
  self.trims = nil
  self.trimsResolved = false
  self.navDir = 0
  self.navNextAt = nil
  self.values = {}
  self.valueEpoch = 0
  return self
end

function Drive:pulseTicks()
  local ms = tonumber(self.settings and self.settings.pulse_ms) or M.DEFAULTS.pulse_ms
  local ticks = math.floor((ms / 10) + 0.5)
  if ticks < 1 then ticks = 1 end
  return ticks
end

--- The function id sitting in the current cell, or nil when the cell carries no slot.
function Drive:functionId(bank, row)
  local bankSet = self.set and self.set[bank or self.bank]
  if type(bankSet) ~= "table" then return nil end
  return bankSet[row or self.row]
end

local function writeGvar(self, index, fm, value)
  if not index or index <= 0 then return false end
  return self.radio.setGlobalVariable(index - 1, fm, value)
end

--- Put `value` on the value variable, and remember the flight mode it went to.
--
-- The flight mode matters: model.setGlobalVariable resolves a "same as FMx" link itself, so a
-- write made in one mode and cleared in another can leave the first one standing. The clear goes
-- back to the mode the write was made in.
function Drive:writeValue(value, fm)
  if self.written == value then return end
  local settings = self.settings
  if not settings or (settings.value_gvar or 0) <= 0 then
    self.written = value
    return
  end
  local mode = fm
  if mode == nil then mode = self.writtenFm end
  if mode == nil then mode = self.radio.flightMode() end
  writeGvar(self, settings.value_gvar, mode, value)
  self.written = value
  self.writtenFm = (value ~= 0) and mode or nil
  logDrive("value gvar %d fm %d <- %d", settings.value_gvar, mode, value)
end

--- Park the enable channel in the middle of one band's window.
--
-- Mid-band rather than an edge, so switch, mixer and receiver tolerance all fit inside the window
-- the firmware is watching.
function Drive:armBank(bank)
  local settings = self.settings
  if not settings or (settings.bank_gvar or 0) <= 0 then return false, "no_gvar" end
  local value = self.bankValues and self.bankValues[bank]
  if value == nil then return false, "no_band" end
  local fm = self.radio.flightMode()
  writeGvar(self, settings.bank_gvar, fm, value)
  self.bankWritten = value
  logDrive("bank gvar %d fm %d <- %d (bank %d)", settings.bank_gvar, fm, value, bank)
  return true
end

--- A bank chosen by hand, from a chip on the fullscreen screen.
--
-- Refused while the value variable is not 0: moving the enable channel under a value that is
-- inside a step window is how one tap ends up counted against another parameter.
function Drive:setBank(bank)
  bank = tonumber(bank)
  if bank == nil or bank < 1 or bank > Functions.BANK_COUNT then return false, "range" end
  if self.written ~= 0 then return false, "busy" end
  self.bank = bank
  self.row = 1
  return self:armBank(bank)
end

--- The next assigned cell in the set's own order: bank by bank, row by row, unassigned cells
-- skipped. It wraps, because a walk that stops without a sound cannot be told apart from a trim
-- that stopped answering -- and this is the control a pilot uses without looking.
function Drive:stepCell(up)
  local perBank = Functions.ROW_COUNT
  local total = Functions.BANK_COUNT * perBank
  local index = (self.bank - 1) * perBank + (self.row - 1)
  for _ = 1, total do
    index = (index + (up and 1 or -1)) % total
    local bank = (index // perBank) + 1
    local row = (index % perBank) + 1
    if self:functionId(bank, row) ~= nil then return bank, row end
  end
  return nil
end

--- One step of the walk, in navigate mode.
--
-- Refused outright while the value variable is not 0. The alternative -- moving the selection and
-- leaving the enable channel where it was -- puts the screen and the board on different
-- parameters, which is the one state a tuning surface must never be in.
function Drive:navigate(up)
  if not self.live then return false, "not_live" end
  if self.written ~= 0 then return false, "busy" end
  local bank, row = self:stepCell(up)
  if bank == nil then return false, "empty" end
  local crossed = (bank ~= self.bank)
  self.bank = bank
  self.row = row
  self.valueEpoch = self.valueEpoch + 1
  if crossed then self:armBank(bank) end
  return true
end

function Drive:selectRow(row)
  row = tonumber(row)
  if row == nil or row < 1 or row > Functions.ROW_COUNT then return false end
  self.row = row
  return true
end

--- A press on the minus or plus control. Refused inside the cool-down, which is one pulse long:
-- the flight controller needs REPEAT_DELAY between steps, and two taps closer together than that
-- would look like one held position rather than two steps.
function Drive:press(row, up)
  if not self.live then return false, "not_live" end
  local now = self.radio.now()
  if self.pulseUntil ~= nil or now < (self.coolUntil or 0) then return false, "cooling" end
  local code = Functions.rowCode(row or self.row, up)
  if code == nil then return false, "range" end
  self.row = row or self.row
  self.pulseCode = code
  self.pulseUntil = now + self:pulseTicks()
  self.holdRow = row or self.row
  self.holdUp = up
  self:writeValue(code, self.radio.flightMode())
  return true
end

--- The release of a held control. The value falls away at the end of the pulse rather than here,
-- so a control tapped faster than the flight controller's own trigger delay still produces a step.
function Drive:release()
  self.holdRow = nil
  self.holdUp = nil
end

--- One tap, for a radio whose LVGL build has no momentary button: press without the hold, so the
-- pulse ends on its own timer and nothing waits for a release that never comes.
function Drive:tap(row, up)
  local ok, reason = self:press(row, up)
  if ok then self:release() end
  return ok, reason
end

--- Both variables to 0 and every pending motion dropped.
--
-- Cheap and idempotent by design: it runs on the interlock falling, on leaving fullscreen, on the
-- widget going to background, on the link dropping, and once defensively on the interlock rising.
-- `force` writes even when the drive believes the variables are already clear, which is what the
-- rising edge needs -- what a previous session left behind is not knowable from here.
function Drive:cleanup(force)
  local settings = self.settings
  local fm = self.writtenFm
  if fm == nil then fm = self.radio.flightMode() end

  self.pulseCode = nil
  self.pulseUntil = nil
  self.holdRow = nil
  self.holdUp = nil
  self.trimRow = nil
  self.trimUp = nil
  self.navDir = 0
  self.navNextAt = nil

  if settings and (settings.value_gvar or 0) > 0 and (force or self.written ~= 0) then
    writeGvar(self, settings.value_gvar, fm, 0)
    logDrive("cleanup: value gvar %d fm %d <- 0", settings.value_gvar, fm)
  end
  self.written = 0
  self.writtenFm = nil

  if settings and (settings.bank_gvar or 0) > 0 and (force or (self.bankWritten or 0) ~= 0) then
    local bankFm = self.radio.flightMode()
    writeGvar(self, settings.bank_gvar, bankFm, 0)
    logDrive("cleanup: bank gvar %d fm %d <- 0", settings.bank_gvar, bankFm)
  end
  self.bankWritten = 0
  self.coolUntil = 0
end

--- Where the interlock stands, with the first evaluation seeding rather than firing.
--
-- A widget that starts up with the switch already ON must not read that as the pilot having just
-- turned it on: the overlay would open, and on the transition it would write. So the first
-- evaluation only records what it saw.
function Drive:evaluateInterlock(now)
  local settings = self.settings
  if not settings or settings.enabled ~= true or (settings.switch or 0) == 0 then
    if self.live then
      self.live = false
      self:cleanup(false)
    end
    self.seeded = false
    self.rawSwitch = nil
    return false
  end

  local raw = (self.radio.switchValue(settings.switch) == true)

  if not self.seeded then
    self.seeded = true
    self.rawSwitch = raw
    self.rawSince = now
    self.live = false
    return false
  end

  if raw ~= self.rawSwitch then
    self.rawSwitch = raw
    self.rawSince = now
    return self.live
  end

  if self.live == raw then return self.live end
  if (now - (self.rawSince or now)) < STABILITY_TICKS then return self.live end

  self.live = raw
  if raw then
    -- Defensive on the way in, never only on the way out: what the previous session left in the
    -- two variables cannot be read back from a drive that has just been constructed.
    self:cleanup(true)
    self.bankShown = nil
    logDrive("interlock on: bank ch%d value ch%d", settings.bank_ch, settings.value_ch)
  else
    self:cleanup(false)
    logDrive("interlock off")
  end
  return self.live
end

--- The radio's trim block, resolved once and kept. Re-resolved when the settings change, because
-- the walk that finds it is not free and nothing else moves it.
function Drive:ensureTrims()
  if not self.trimsResolved then
    self.trims = M.resolveTrims(self.radio)
    self.trimsResolved = true
  end
  if type(self.trims) ~= "table" then return nil end
  return self.trims
end

function Drive:navigateMode()
  local settings = self.settings
  return settings ~= nil and settings.trim_mode == M.TRIM_MODE_NAVIGATE
end

--- The walk trim, read as an EDGE. One press moves one parameter, however long the pass takes;
-- held on purpose, it repeats after a delay no single press can reach.
function Drive:pollNavigate(now)
  local settings = self.settings
  if not settings or settings.trims ~= true or not self:navigateMode() then return end
  local trims = self:ensureTrims()
  local trim = trims and trims[settings.nav_trim or 0] or nil
  if trim == nil then return end

  local direction = 0
  if self.radio.switchValue(trim.plus) == true then
    direction = 1
  elseif self.radio.switchValue(trim.minus) == true then
    direction = -1
  end

  if direction ~= self.navDir then
    self.navDir = direction
    if direction ~= 0 then
      self:navigate(direction > 0)
      self.navNextAt = now + NAV_REPEAT_DELAY_TICKS
    else
      self.navNextAt = nil
    end
    return
  end

  if direction ~= 0 and self.navNextAt ~= nil and now >= self.navNextAt then
    self:navigate(direction > 0)
    self.navNextAt = now + NAV_REPEAT_INTERVAL_TICKS
  end
end

--- Which row a held trim is asking for, read once per pass.
--
-- In `rows` mode every assigned trim is a row of its own. In `navigate` mode ONE trim adjusts and
-- it always means the selected row; every other trim, the walk trim included, is inert here.
function Drive:pollTrims()
  local settings = self.settings
  if not settings or settings.trims ~= true then return nil, nil end
  local trims = self:ensureTrims()
  if trims == nil then return nil, nil end

  if self:navigateMode() then
    local trim = trims[settings.adj_trim or 0]
    if trim then
      if self.radio.switchValue(trim.plus) == true then return self.row, true end
      if self.radio.switchValue(trim.minus) == true then return self.row, false end
    end
    return nil, nil
  end

  -- The row with the largest magnitude wins when two trims are held at once. It is a choice
  -- rather than a reading: the shipped template SUMS its trims onto the value channel, and a sum
  -- of two lands outside every window, so two trims there produce no step at all.
  for row = 1, Functions.ROW_COUNT do
    local trim = trims[settings.rowTrim and settings.rowTrim[row] or 0]
    if trim then
      if self.radio.switchValue(trim.plus) == true then return row, true end
      if self.radio.switchValue(trim.minus) == true then return row, false end
    end
  end
  return nil, nil
end

--- Which rows the pilot can actually reach, as a mask the zone screen hides rows by.
--
-- In `rows` mode that is the rows whose trim this radio has; in `navigate` mode it is every
-- assigned cell, because the walk reaches all of them with the same two trims.
function Drive:trimRowsPresent()
  local mask = {}
  local settings = self.settings
  if not settings or settings.trims ~= true then return mask end
  local trims = self:ensureTrims()
  if trims == nil then return mask end

  if self:navigateMode() then
    if trims[settings.adj_trim or 0] == nil then return mask end
    for row = 1, Functions.ROW_COUNT do
      mask[row] = self:functionId(self.bank, row) ~= nil
    end
    return mask
  end

  for row = 1, Functions.ROW_COUNT do
    local index = settings.rowTrim and settings.rowTrim[row] or 0
    mask[row] = (index > 0 and trims[index] ~= nil)
  end
  return mask
end

--- One pass of the drive. Everything with a cost is behind `live`; a widget whose pilot has the
-- interlock off pays one switch read per pass and nothing else.
function Drive:tick()
  local now = self.radio.now()
  local wasLive = self.live
  self:evaluateInterlock(now)
  if not self.live then
    if wasLive then self.valueEpoch = self.valueEpoch + 1 end
    return false
  end

  -- What the enable channel is actually doing. Read rather than assumed, so a six-position switch
  -- wired straight to it shows the right bank without the overlay having written anything, and a
  -- missing mixer line is visible as a bank that does not move.
  local shown = Functions.usToBand(self.radio.channelUs(self.settings.bank_ch), self.bands)
  if shown ~= self.bankShown then
    self.bankShown = shown
    self.valueEpoch = self.valueEpoch + 1
  end
  if shown ~= nil and shown ~= self.bank then
    self.bank = shown
  end

  -- The last adjustment the board reports having made. AdjF reads 0 between adjustments, so a
  -- non-zero reading is a fresh one and its value belongs to that function.
  local adjF = self.radio.sensor("AdjF")
  if adjF and adjF > 0 then
    local adjV = self.radio.sensor("AdjV")
    if adjV ~= nil and self.values[adjF] ~= adjV then
      self.values[adjF] = adjV
      self.valueEpoch = self.valueEpoch + 1
    end
  end

  -- A running touch pulse suspends both trim paths: the pilot's thumb and the pilot's finger must
  -- not both be writing the same variable.
  local pulsing = (self.pulseUntil ~= nil) or (self.holdRow ~= nil)
  if not pulsing then
    self:pollNavigate(now)
    local row, up = self:pollTrims()
    if row ~= self.trimRow or up ~= self.trimUp then
      self.trimRow, self.trimUp = row, up
      if row ~= nil then self.row = row end
      self.valueEpoch = self.valueEpoch + 1
    end
  end

  if self.pulseUntil ~= nil and now >= self.pulseUntil then
    self.pulseUntil = nil
    self.pulseCode = nil
    self.coolUntil = now + self:pulseTicks()
  end

  local want = 0
  if self.pulseUntil ~= nil then
    want = self.pulseCode or 0
  elseif self.holdRow ~= nil then
    want = Functions.rowCode(self.holdRow, self.holdUp) or 0
  elseif self.trimRow ~= nil then
    want = Functions.rowCode(self.trimRow, self.trimUp) or 0
  end

  if want ~= self.written then
    self:writeValue(want, want ~= 0 and self.radio.flightMode() or nil)
  end

  return true
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

-- ---------------------------------------------------------------------------
-- The widget's side
-- ---------------------------------------------------------------------------

local function settingsSignature(settings)
  if type(settings) ~= "table" then return "" end
  local rows = settings.rowTrim or {}
  return table.concat({
    tostring(settings.enabled), tostring(settings.switch), tostring(settings.bank_ch),
    tostring(settings.value_ch), tostring(settings.bank_gvar), tostring(settings.value_gvar),
    tostring(settings.pulse_ms), tostring(settings.trims), tostring(settings.backup_profile),
    tostring(settings.trim_mode), tostring(settings.nav_trim), tostring(settings.adj_trim),
    tostring(rows[1]), tostring(rows[2]), tostring(rows[3]),
    tostring(rows[4]), tostring(rows[5]), tostring(rows[6])
  }, "|")
end

--- The drive belonging to this widget, constructed on first use and re-settled whenever the
-- per-model store has been re-read.
--
-- A different TABLE is not a different setting. The store arrives here as a fresh table several
-- times per second -- the MSP runtime republishes its own copy on every publish -- so the identity
-- test is the cheap path taken on almost every pass, and the section is parsed and its signature
-- built only when the table really was replaced. Without it every pass paid for both, which is the
-- same trap widgets/dashboard/runtime.lua documents for its own theme reload.
function M.get(widget)
  if type(widget) ~= "table" then return nil end
  local prefs = widget.modelPreferences
  local drive = widget._inflight
  if drive ~= nil and drive._source == prefs then return drive end

  local settings = M.loadSettings(prefs)
  local signature = settingsSignature(settings)
  if drive == nil then
    drive = M.newDrive(nil, settings)
    drive._signature = signature
    widget._inflight = drive
  elseif drive._signature ~= signature then
    drive:cleanup(false)
    drive.settings = settings
    drive._signature = signature
    drive.trimsResolved = false
    drive.seeded = false
  end
  drive._source = prefs
  return drive
end

--- The snapshot the screen's reactive closures read.
--
-- Rebuilt as a FRESH table whenever anything on it moved, and reused otherwise: a closure holds
-- the widget and reads mid-sweep, so the swap has to be atomic. Nothing here is a probe, which is
-- the whole point -- the closures never reach past this table.
--
-- It is published on `state.inflight` rather than inside `state.derived`, because
-- widgets/dashboard/derived.lua assigns a brand new table to `state.derived` on every telemetry
-- read and anything parked there would vanish with it.
local function publish(widget, drive)
  local state = widget.state
  if type(state) ~= "table" then return end
  local snapshot = state.inflight
  local epoch = drive.valueEpoch
  if type(snapshot) == "table" and snapshot.epoch == epoch and snapshot.live == drive.live
    and snapshot.bank == drive.bank and snapshot.row == drive.row then
    return
  end

  local rows = {}
  local mask = drive:trimRowsPresent()
  for row = 1, Functions.ROW_COUNT do
    local id = drive:functionId(drive.bank, row)
    rows[row] = {
      id = id,
      name = id and Functions.nameOf(id) or nil,
      value = id and drive.values[id] or nil,
      trim = mask[row] == true
    }
  end

  local activeId = drive:functionId(drive.bank, drive.row)
  state.inflight = {
    epoch = epoch,
    enabled = drive.settings.enabled == true,
    live = drive.live,
    bank = drive.bank,
    bankShown = drive.bankShown,
    row = drive.row,
    rows = rows,
    activeId = activeId,
    activeName = activeId and Functions.nameOf(activeId) or nil,
    activeValue = activeId and drive.values[activeId] or nil,
    navigate = drive:navigateMode(),
    profile = drive.profile
  }
end

--- One pass, called from the widget's background half.
function M.tick(widget)
  local drive = M.get(widget)
  if drive == nil then return false end
  if drive.settings.enabled ~= true then
    if widget.state and widget.state.inflight ~= nil then widget.state.inflight = nil end
    return false
  end
  local live = drive:tick()
  -- The profile sensor is read only while the overlay is up. Off the overlay a pass costs one
  -- switch read and nothing else, which is the whole point of putting the gate first.
  if live then drive.profile = drive.radio.sensor("PID#") end
  publish(widget, drive)
  return live == true
end

--- Everything off, from a widget that is going away. Never allocates a drive that does not
-- already exist: a widget that never ran the overlay has nothing to clean up.
function M.cleanup(widget)
  if type(widget) ~= "table" then return end
  local drive = widget._inflight
  if drive == nil then return end
  drive.live = false
  drive.seeded = false
  drive:cleanup(false)
  if widget.state then widget.state.inflight = nil end
end

M.Drive = Drive

return M
