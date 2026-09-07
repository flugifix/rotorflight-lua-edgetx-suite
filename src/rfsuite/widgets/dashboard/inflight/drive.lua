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

local Setup = requireModule("widgets/dashboard/inflight/setup.lua")
local Functions = requireModule("widgets/dashboard/inflight/functions.lua")

-- Everything about what the model must LOOK like -- the store, the radio seam, the trim block,
-- the setup check -- lives in setup.lua, so that the settings page can have it without this
-- file. Re-exported here because the widget side, the screens and the probes reach for it
-- through this module and there is no reason to make them all learn a second name.
M.DEFAULTS = Setup.DEFAULTS
M.PULSE_MS_MIN = Setup.PULSE_MS_MIN
M.PULSE_MS_MAX = Setup.PULSE_MS_MAX
M.CHANNEL_MIN = Setup.CHANNEL_MIN
M.CHANNEL_MAX = Setup.CHANNEL_MAX
M.GVAR_MAX_INDEX = Setup.GVAR_MAX_INDEX
M.TRIM_COUNT = Setup.TRIM_COUNT
M.PROFILE_MAX = Setup.PROFILE_MAX
M.TRIM_MODE_ROWS = Setup.TRIM_MODE_ROWS
M.TRIM_MODE_NAVIGATE = Setup.TRIM_MODE_NAVIGATE
M.radio = Setup.radio
M.loadSettings = Setup.loadSettings
M.storeSettings = Setup.storeSettings
M.resolveTrims = Setup.resolveTrims
M.trimsFromList = Setup.trimsFromList
M.check = Setup.check

local logDrive = Setup.log
local SWITCH_SLICE = Setup.SWITCH_SLICE
local SWITCH_WALK_LIMIT = Setup.SWITCH_WALK_LIMIT

-- A switch has to hold its new reading this long before the overlay believes it. It is not a
-- debounce for the switch, which does not bounce: it is the margin against a pilot brushing the
-- interlock on the way to something else.
local STABILITY_TICKS = 30

-- The walk is EDGE triggered: one press, one parameter. A trim held on purpose then repeats, after
-- a delay long enough that a single press can never produce two steps, at a rate a pilot can still
-- count while looking somewhere else.
local NAV_REPEAT_DELAY_TICKS = 50
local NAV_REPEAT_INTERVAL_TICKS = 33

-- ---------------------------------------------------------------------------
-- The drive
-- ---------------------------------------------------------------------------

local Drive = {}
Drive.__index = Drive

--- Which parameters the screen offers, before anything has been read off the board.
--
-- In the STANDARD set layout that is the whole answer: the set is a constant of this build, the
-- screen names all thirty-six cells from the first frame, and the ground half reads the board's
-- own slot table only to say whether the board agrees with it. In the CUSTOM layout it is a
-- placeholder -- the documented thirty, which is the best guess available until the board's table
-- has been read and turned into the set it really describes.
--
-- Called again whenever the settings change, because the channels a cell is derived from and the
-- layout it is derived under are both settings.
function Drive:seedSet()
  local standard = (self.settings and self.settings.set_mode) ~= Setup.SET_MODE_CUSTOM
  self.bands = Functions.REFERENCE_BANDS
  self.bankValues = Functions.REFERENCE_BAND_GV
  if standard then
    self.set = Functions.STANDARD_SET
    self.setSource = "standard"
  else
    self.set = Functions.REFERENCE_SET
    self.setSource = "reference"
  end
  self.compare = nil
end

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
  self:seedSet()
  self.bankShown = nil
  self.written = 0
  self.writtenFm = nil
  self.bankWritten = nil
  self.bankFm = nil
  self.pulseCode = nil
  self.pulseUntil = nil
  self.coolUntil = 0
  self.holdRow = nil
  self.holdUp = nil
  self.trimRow = nil
  self.trimUp = nil
  self.trimCode = nil
  self.trimHold = false
  self.trimPulseUntil = nil
  self.trimCoolUntil = 0
  self.trims = nil
  self.trimsResolved = false
  self.trimScan = nil
  self.navDir = 0
  self.navNextAt = nil
  self.bankDir = 0
  self.bankNextAt = nil
  self.fastAt = nil
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
--
-- The BOOKKEEPING IS PESSIMISTIC, and the order of the two lines is the whole of it. A widget pass
-- is killed wherever the firmware's instruction limit happens to land, including between the write
-- and the note of it, and the two orders fail in opposite directions. Recording afterwards, a pass
-- killed in between leaves the drive believing 0 is standing when the row's magnitude is -- and
-- `cleanup(false)` then writes nothing, for ever, because it only clears what it believes it put
-- there. Recording first, the same pass leaves the drive believing a value is standing that is
-- not, and the cost of that is one redundant write of 0.
--
-- Which of the two lines comes first therefore depends on the direction. A value going ON is
-- recorded before it is written; a value going OFF is written before it is un-recorded, because
-- for a clear it is the clear itself that must not be lost.
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
  if value ~= 0 then
    self.written = value
    self.writtenFm = mode
    writeGvar(self, settings.value_gvar, mode, value)
  else
    writeGvar(self, settings.value_gvar, mode, 0)
    self.written = 0
    self.writtenFm = nil
  end
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
  -- Recorded before it is written, for the reason writeValue sets out: a pass killed between the
  -- two must leave the drive believing MORE is standing than is, never less, because a cleanup
  -- only takes back what it believes it put there.
  --
  -- The flight mode is recorded with it, for the same reason the value variable's is:
  -- model.setGlobalVariable resolves a "same as FMx" link itself, so a bank armed in one mode and
  -- cleared in another leaves the first one armed. A pilot who changes flight mode with the
  -- interlock closed -- which is a switch, not a rare event -- would otherwise land back on the
  -- ground with the enable channel still parked in a band.
  self.bankWritten = value
  self.bankFm = fm
  writeGvar(self, settings.bank_gvar, fm, value)
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
  self.trimCode = nil
  self.trimHold = false
  self.trimPulseUntil = nil
  self.navDir = 0
  self.navNextAt = nil
  self.bankDir = 0
  self.bankNextAt = nil

  if settings and (settings.value_gvar or 0) > 0 and (force or self.written ~= 0) then
    writeGvar(self, settings.value_gvar, fm, 0)
    logDrive("cleanup: value gvar %d fm %d <- 0", settings.value_gvar, fm)
  end
  self.written = 0
  self.writtenFm = nil

  if settings and (settings.bank_gvar or 0) > 0 and (force or (self.bankWritten or 0) ~= 0) then
    -- The mode the bank was ARMED in, not the mode the radio happens to be in now. Cleared in the
    -- wrong one, the write goes to a different slot -- or is redirected by a "same as FMx" link --
    -- and the enable channel stays parked in a band nobody chose.
    local bankFm = self.bankFm
    if bankFm == nil then bankFm = self.radio.flightMode() end
    writeGvar(self, settings.bank_gvar, bankFm, 0)
    logDrive("cleanup: bank gvar %d fm %d <- 0", settings.bank_gvar, bankFm)
  end
  self.bankWritten = 0
  self.bankFm = nil
  self.coolUntil = 0
  self.trimCoolUntil = 0
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
--
-- The walk is taken a slice at a time and answers nil until it is complete, so no single pass can
-- be killed by it -- and the cursor is advanced BEFORE the slice is asked for, so a pass that is
-- killed inside it anyway loses that slice rather than starting the same walk again on the next
-- pass, for ever. That ordering is the whole defect this function was rewritten for: with the
-- state written after the work, a walk that overruns the instruction limit is retried by every
-- following pass and the widget never gets past it.
--
-- The epoch is bumped on the pass that completes the walk, because the row list carries a marker
-- per trim and that marker becomes knowable exactly then.
function Drive:ensureTrims()
  if self.trimsResolved then
    if type(self.trims) ~= "table" then return nil end
    return self.trims
  end

  local scan = self.trimScan
  if scan == nil then
    scan = { list = {}, from = nil }
    self.trimScan = scan
  end

  local slice, resumeAt = self.radio.switchList(scan.from, SWITCH_SLICE)
  scan.from = resumeAt
  if type(slice) == "table" then
    for i = 1, #slice do
      scan.list[#scan.list + 1] = slice[i]
    end
  end
  if resumeAt ~= nil and #scan.list < SWITCH_WALK_LIMIT then return nil end

  self.trims = M.trimsFromList(scan.list)
  self.trimsResolved = true
  self.trimScan = nil
  self.valueEpoch = self.valueEpoch + 1
  if type(self.trims) ~= "table" then return nil end
  return self.trims
end

function Drive:navigateMode()
  local settings = self.settings
  return settings ~= nil and settings.trim_mode == M.TRIM_MODE_NAVIGATE
end

--- Whether a trim of this radio's is actually stepping the bank.
--
-- Configured is not enough: a bank trim named in the settings and absent from this radio would
-- otherwise leave the walk trim confined to one bank with no way of reaching the other five, which
-- is worse than either arrangement on its own. So the split is decided by what the walk can
-- REACH, and a radio without the named trim falls back to walking the whole set.
function Drive:bankTrimActive()
  local settings = self.settings
  if not settings or settings.trims ~= true or not self:navigateMode() then return false end
  local index = settings.bank_trim or 0
  if index <= 0 then return false end
  local trims = self.trims
  return type(trims) == "table" and trims[index] ~= nil
end

--- One step of the walk WITHIN the current bank, wrapping. The other half of the pilot's own
-- arrangement: with a bank trim of its own the walk trim no longer has to count its way across
-- thirty-six cells to reach the row beside the one it started on.
function Drive:navigateRow(up)
  if not self:bankTrimActive() then return self:navigate(up) end
  if not self.live then return false, "not_live" end
  if self.written ~= 0 then return false, "busy" end
  local total = Functions.ROW_COUNT
  local index = self.row - 1
  for _ = 1, total do
    index = (index + (up and 1 or -1)) % total
    if self:functionId(self.bank, index + 1) ~= nil then
      self.row = index + 1
      self.valueEpoch = self.valueEpoch + 1
      return true
    end
  end
  return false, "empty"
end

--- One bank previous or next, wrapping, with the first assigned row of the new bank selected.
--
-- Refused while the value variable is not 0, for the reason the bank CHIP is: moving the enable
-- channel under a value that sits inside a step window is how one press ends up counted against
-- another parameter. A bank with no assigned cell at all is stepped over rather than shown empty.
function Drive:navigateBank(up)
  if not self.live then return false, "not_live" end
  if self.written ~= 0 then return false, "busy" end
  local count = Functions.BANK_COUNT
  local bank = self.bank
  for _ = 1, count do
    bank = ((bank - 1 + (up and 1 or -1)) % count) + 1
    for row = 1, Functions.ROW_COUNT do
      if self:functionId(bank, row) ~= nil then
        self.bank = bank
        self.row = row
        self.valueEpoch = self.valueEpoch + 1
        return self:armBank(bank)
      end
    end
  end
  return false, "empty"
end

--- One walk trim, read as an EDGE with a repeat clock of its own. One press moves one step,
-- however long the pass takes; held on purpose it repeats, after a delay no single press reaches.
local function walkTrim(self, now, trim, dirKey, nextKey, step)
  local direction = 0
  if self.radio.switchValue(trim.plus) == true then
    direction = 1
  elseif self.radio.switchValue(trim.minus) == true then
    direction = -1
  end

  if direction ~= self[dirKey] then
    self[dirKey] = direction
    if direction ~= 0 then
      step(self, direction > 0)
      self[nextKey] = now + NAV_REPEAT_DELAY_TICKS
    else
      self[nextKey] = nil
    end
    return
  end

  if direction ~= 0 and self[nextKey] ~= nil and now >= self[nextKey] then
    step(self, direction > 0)
    self[nextKey] = now + NAV_REPEAT_INTERVAL_TICKS
  end
end

--- The two walk trims: one steps the bank, one steps the row inside it.
--
-- The bank is polled FIRST. Both refuse while a value is standing on the variable, and a pilot
-- who presses the two together means the bank -- the row he lands on is chosen by the bank step
-- anyway, so reading the row first would make the pair depend on which one his thumb reached a
-- millisecond earlier.
function Drive:pollNavigate(now)
  local settings = self.settings
  if not settings or settings.trims ~= true or not self:navigateMode() then return end
  local trims = self:ensureTrims()
  if trims == nil then return end

  local bankTrim = trims[settings.bank_trim or 0]
  if bankTrim ~= nil then
    walkTrim(self, now, bankTrim, "bankDir", "bankNextAt", Drive.navigateBank)
  end

  local navTrim = trims[settings.nav_trim or 0]
  if navTrim ~= nil then
    walkTrim(self, now, navTrim, "navDir", "navNextAt", Drive.navigateRow)
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

--- The adjust trim, read as an EDGE and answered with a PULSE.
--
-- Why it is not the level, which is what this was. A trim is a momentary contact and a pilot's
-- press on one lasts as long as a pilot's press: the two in his own log are 0.0 and 0.1 seconds
-- long. The flight controller counts no step at all until the value channel has stood STILL
-- inside one window for TRIGGER_DELAY, 100 ms (fc/rc_adjustments.c) -- so a relay that wrote the
-- magnitude while the trim was down and 0 when it came up made the channel move out and back
-- without ever standing still. Short press: no step, and nothing on the screen to say why. Held
-- for a second: three or four. That is the pilot's report exactly -- it works "only after a
-- while, and very inaccurately".
--
-- So one press is one pulse, which is what the touch control has always done: the magnitude goes
-- on at the edge and stays on for at least `pulse_ms` however early the trim is let go, and a
-- trim genuinely held keeps it on past that for as long as it is held -- which is where the
-- board's own REPEAT_DELAY takes over and steps at its own rate. The cool-down after a pulse is
-- the same length, so two presses closer together than the board can tell apart are one step and
-- not an arbitrary number of them.
--
-- The pulse and the hold are the trim's OWN, deliberately not the touch control's. A held touch
-- button is published as `holding` and freezes the widget's render key, because a rebuild would
-- delete the object that reports its release; a trim has no object and a rebuild cannot lose it,
-- and freezing the surface for as long as a thumb is on a trim would freeze it for the whole of
-- the tuning.
function Drive:pollTrimStep(now)
  local row, up = self:pollTrims()

  if row ~= self.trimRow or up ~= self.trimUp then
    self.trimRow, self.trimUp = row, up
    self.valueEpoch = self.valueEpoch + 1
    if row == nil then
      -- Let go. The magnitude does not fall away here: a pulse still running owns it until its
      -- own clock says otherwise, and that is the whole of what makes a short press step at all.
      self.trimHold = false
    else
      self.row = row
      -- The same thumb moved to another row without coming up. The magnitude follows the new row
      -- rather than finishing the old one's pulse: the screen has already followed the pilot and
      -- the wire has to agree with the screen.
      if self.trimHold == true then self.trimCode = Functions.rowCode(row, up) end
    end
  end

  if row == nil then return end
  -- Already holding the value, or a pulse of this trim's own still on the wire: nothing to start.
  if self.trimHold == true or self.trimPulseUntil ~= nil then return end
  -- The board needs its REPEAT_DELAY between two magnitudes before it counts them as two steps.
  -- A trim still down when that gap has passed gets its pulse then; two TAPS inside the gap get
  -- ONE pulse between them, which is the point of having it.
  if now < (self.trimCoolUntil or 0) then return end

  self.trimCode = Functions.rowCode(row, up)
  self.trimPulseUntil = now + self:pulseTicks()
  self.trimHold = true
end

--- Which rows the pilot can actually reach, as a mask the zone screen hides rows by.
--
-- In `rows` mode that is the rows whose trim this radio has; in `navigate` mode it is every
-- assigned cell, because the walk reaches all of them with the same two trims.
-- This is the SNAPSHOT's view and it never starts the walk. The mask describes the tuning
-- surface's rows, and that surface exists only while the overlay is live; starting the walk from
-- here put it in every pass of the widget's cold start instead, which is where it does not fit.
-- Until `pollTrims` has finished the walk the rows publish no marker, and the epoch bump on the
-- completing pass is what puts them on the screen.
function Drive:trimRowsPresent()
  local mask = {}
  local settings = self.settings
  if not settings or settings.trims ~= true then return mask end
  if self.trimsResolved ~= true then return mask end
  local trims = self.trims
  if type(trims) ~= "table" then return mask end

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

--- The fast half of a pass: what the board is reporting and what the pilot's thumb is doing.
--
-- Split out of `tick` because the two clocks are not the same one. The widget's background half
-- runs on a 100 ms logic tick while the firmware calls the widget every 50 ms, and neither of the
-- things in here can wait for the slower clock. The value on the screen is the board's answer to
-- the step the pilot has just asked for, and it is the only thing that tells him the step landed;
-- the trims are momentary contacts, and a press that begins and ends between two logic ticks is a
-- press nothing ever saw. Both are cheap -- two telemetry reads and a handful of switch reads, no
-- allocation and no model call -- and none of it runs while the interlock is open.
--
-- Guarded on the radio's own clock, so a pass that runs the whole tick as well as this one does
-- the work once rather than twice.
function Drive:fastTick(now)
  if self.fastAt == now then return end
  self.fastAt = now

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
    self:pollTrimStep(now)
  end

  if self.pulseUntil ~= nil and now >= self.pulseUntil then
    self.pulseUntil = nil
    self.pulseCode = nil
    self.coolUntil = now + self:pulseTicks()
  end
  -- The trim's pulse ends on its own clock, and it ends on every pass -- including one the touch
  -- path took over above. A magnitude left standing by a pulse nothing is looking at any more is
  -- precisely the state this module exists to make impossible.
  if self.trimPulseUntil ~= nil and now >= self.trimPulseUntil then
    self.trimPulseUntil = nil
    self.trimCode = nil
    self.trimCoolUntil = now + self:pulseTicks()
  end

  local want = 0
  if self.pulseUntil ~= nil then
    want = self.pulseCode or 0
  elseif self.holdRow ~= nil then
    want = Functions.rowCode(self.holdRow, self.holdUp) or 0
  elseif self.trimPulseUntil ~= nil then
    want = self.trimCode or 0
  elseif self.trimHold == true and self.trimRow ~= nil then
    want = Functions.rowCode(self.trimRow, self.trimUp) or 0
  end

  if want ~= self.written then
    self:writeValue(want, want ~= 0 and self.radio.flightMode() or nil)
  end
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

  self:fastTick(now)
  return true
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
    tostring(settings.trim_mode), tostring(settings.nav_trim), tostring(settings.bank_trim),
    tostring(settings.adj_trim),
    tostring(settings.set_mode),
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
    -- and the setup verdict with it: the settings are the only thing that can change the answer
    -- without the pilot leaving the screen it is shown on, and the screen walks the model once
    -- and then reads this.
    drive._checkedAt = nil
    drive._checkResult = nil
    drive.trimsResolved = false
    -- and with it whatever a walk in progress had collected: a half-read list belongs to the
    -- settings it was started under.
    drive.trimScan = nil
    drive.seeded = false
    -- The set goes back to what this build knows, and the verdict on the board with it. Both were
    -- reached under the channels and the layout that have just changed; a set derived from the
    -- old value channel would keep naming parameters no window on the new one reaches.
    drive:seedSet()
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
  -- Whether a control is being HELD, which is the one thing on here that no epoch bump reports:
  -- a press and a release both leave the value cache alone. It is on the snapshot because the
  -- widget's render key must not move while a finger is down -- the rebuild would delete the very
  -- object that reports the release -- so the guard below has to notice it changing.
  local holding = (drive.holdRow ~= nil)
  if type(snapshot) == "table" and snapshot.epoch == epoch and snapshot.live == drive.live
    and snapshot.bank == drive.bank and snapshot.row == drive.row
    and snapshot.holding == holding then
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

  -- The ground half's progress, summarised rather than handed over. Its own table is mutated in
  -- place as replies arrive, and everything published here is read from a tree that is being
  -- built -- so what travels is a copy of the counters, taken at the moment of the swap.
  --
  -- `skipped` travels as a COUNT and not as the list it is kept as. The list is the run's own and
  -- goes on being appended to; a snapshot holding a reference to it is not a snapshot, and the
  -- screen wants the number anyway -- how many of the board's slots the overlay cannot drive is a
  -- fact the pilot needs, and it was being published in a form the screen never showed.
  local prime = drive.prime
  local primeState = nil
  if type(prime) == "table" then
    primeState = {
      phase = prime.phase,
      done = prime.done,
      total = prime.total,
      error = prime.error,
      skipped = #(prime.skipped or {})
    }
  end

  -- The undo and the transfer, likewise copied rather than aliased. The transfer table in
  -- particular is mutated in place -- a copy that is running writes its own outcome into it when
  -- the reply lands -- so a snapshot pointing at it would change under a closure that is reading
  -- it. Only the scalars travel; the backup's own value table is not on this screen.
  local backup = drive.backup
  local backupState = nil
  if type(backup) == "table" then
    backupState = { profile = backup.profile, at = backup.at }
  end

  local transfer = drive.transfer
  local transferState = nil
  if type(transfer) == "table" then
    transferState = { kind = transfer.kind, state = transfer.state, reason = transfer.reason }
  end

  -- What the board's own slot table said when it was held against the standard set. Only the
  -- verdict and the count travel: the list of slots behind it is the ground half's own table and
  -- goes on being appended to, and the screen has room for a sentence rather than for a list.
  local compare = drive.compare
  local compareState = nil
  if type(compare) == "table" then
    compareState = { verdict = compare.verdict, count = compare.count }
  end

  local activeId = drive:functionId(drive.bank, drive.row)
  state.inflight = {
    epoch = epoch,
    enabled = drive.settings.enabled == true,
    live = drive.live,
    -- True exactly while a step control is held down. The widget reads it and leaves the render
    -- key alone while it is true; see M.release above for what a rebuild would cost here.
    holding = holding,
    bank = drive.bank,
    bankShown = drive.bankShown,
    row = drive.row,
    rows = rows,
    activeId = activeId,
    activeName = activeId and Functions.nameOf(activeId) or nil,
    activeValue = activeId and drive.values[activeId] or nil,
    navigate = drive:navigateMode(),
    profile = drive.profile,
    prime = primeState,
    -- Which of the two layouts the rows above came from: the board's own slot table once the
    -- prime has read it, the documented one until then and whenever the board's yields nothing
    -- usable. It is on the screen because a set that silently fell back to the reference layout
    -- and a set that came off this board look exactly alike otherwise.
    setSource = drive.setSource,
    -- and, in the standard layout, whether the board carries it: the set is known without the
    -- board in that mode, so its table is read to be compared rather than to be believed.
    compare = compareState,
    backup = backupState,
    transfer = transferState
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

--- The fast half of a pass, called from the widget's FOREGROUND half on every pass.
--
-- The widget's background work runs on a 100 ms logic tick and a build pass skips it altogether,
-- which is the right cadence for reading telemetry into a dashboard and the wrong one for a
-- tuning surface: the pilot's own report is that the value lags and that a trim press often does
-- nothing. Both come off the same clock. So the two things that must not wait -- the board's
-- AdjF/AdjV report and the trims -- are polled here instead, at the firmware's own 50 ms widget
-- cadence, and everything else stays where it was.
--
-- Costs one table lookup and one boolean test unless the overlay is live, and never constructs a
-- drive: a widget that has not run the overlay this session has nothing to sample.
function M.sample(widget)
  if type(widget) ~= "table" then return false end
  local drive = widget._inflight
  if drive == nil or drive.live ~= true then return false end
  drive:fastTick(drive.radio.now())
  publish(widget, drive)
  return true
end

--- The held control let go, from a caller that is about to destroy the object which would have
-- reported the release itself.
--
-- EdgeTX raises a momentary button's release handler on LV_EVENT_RELEASED and on nothing else
-- (lua_lvgl_widget.cpp, MomentaryButton::customEventHandler), and an object that is deleted while
-- the finger is still down never receives that event. So a rebuild -- lvgl.clear() drops the whole
-- tree -- would take the release with it and leave the drive writing the row's magnitude with
-- nothing left in the world able to take it back. The rebuild path lets go here instead.
--
-- Answers whether there was a hold to let go, so a caller can tell the two cases apart.
function M.release(widget)
  if type(widget) ~= "table" then return false end
  local drive = widget._inflight
  if drive == nil or drive.holdRow == nil then return false end
  drive:release()
  return true
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
