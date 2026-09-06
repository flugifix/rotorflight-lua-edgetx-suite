-- The in-flight tuning overlay's ground half: what it reads off the flight controller before a
-- flight, and the undo it lays down before the pilot turns anything.
--
-- Everything in this file speaks MSP, and MSP is only spoken on the ground. tasks/msp/runtime.lua
-- clears its whole queue on every armed tick and pump() refuses while armed, so a read started in
-- the air is dropped without an answer and a write is lost silently. This module therefore
-- refuses to start while armed and abandons a run that is armed into -- and it treats the queue's
-- own "cleared" reason as that abandon rather than as a failure, because the clear IS the runtime
-- enforcing the same rule.
--
-- It does NOT attach a client of its own. Runtime.attach() records the id and brings the runtime
-- up, and widgets/dashboard/runtime.lua's tickMspRuntime already does both on every pass, along
-- with the tick and the pump these replies arrive on. Nothing in the queue schedules by client id
-- -- it is one FIFO, and the id is what a clear and a log line name -- so a second registration
-- would add an id that something would afterwards have to detach, and the widget has no teardown
-- point that could. The messages still carry `client`, which is the part that has an effect.
--
-- Two things are read off the board rather than assumed. The SET is the board's own adjustment
-- slot table: which parameter sits in which bank and row is whatever the pilot configured there,
-- and the documented layout is only the fallback for a board that yields nothing usable. The
-- VALUES are the nine reads that between them answer every adjustment function id, so the screen
-- can show a number before the first step is made -- AdjF/AdjV only report what has just moved.

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

local function logPrime(fmt, ...)
  if not (Log and type(Log.wanted) == "function" and Log.wanted("info")) then return end
  local msg = tostring(fmt)
  if select("#", ...) > 0 then msg = string.format(msg, ...) end
  Log.emit("rfsuite.inflight", msg, "info")
end

-- The name every message of this module carries. The queue clears and logs by it; nothing
-- schedules by it.
M.CLIENT = "inflight-tuning"

-- MSP_RX_MAP, MSP_GET_ADJUSTMENT_FUNCTION_IDS and MSP_GET_ADJUSTMENT_RANGE. The whole-table read
-- (52) is deliberately absent: over CRSF its reply overruns the reassembly buffer, which is why
-- their own adjustments page reads the table one slot at a time as well.
local CMD_RX_MAP = 64
local CMD_ADJ_FUNCTION_IDS = 167
local CMD_ADJ_RANGE = 156

-- MSP_COPY_PROFILE and MSP_EEPROM_WRITE, the pair their app/pages/tools/copy_profiles page uses.
-- 183 carries { type, destination, source } and 0 is the PID profile type; the copy lives in RAM
-- until 250 commits it, so the two always travel together.
local CMD_COPY_PROFILE = 183
local CMD_EEPROM_WRITE = 250
local PROFILE_TYPE_PID = 0

-- MSP_STATUS, the one value read that also says how many profiles the board has.
local CMD_STATUS = 101

-- The board's table is 42 slots, the length of the 167 reply.
local SLOT_COUNT = 42

-- Their adjustments page bounds an AUX field to this before it maps it (its AUX_CHANNEL_COUNT).
local AUX_FIELD_COUNT = 13

-- The first AUX member when the receiver map has not been read: four sticks and the throttle
-- ahead of it, 0-based.
local AUX_MEMBER_BASE = 5

-- How long the connect chain has to have been FINISHED before the automatic prime runs, in
-- getTime ticks of 10 ms.
--
-- The wait used to be measured from the link coming up, and two seconds of link is not the same
-- thing at all: measured against a board, the chain was still running sixteen seconds in, the
-- prime's forty-odd round trips went into the same single queue beside it, and the chain the
-- dashboard is waiting for took fifty-nine seconds instead of sixteen -- long enough for the
-- widget's own splash timeout to fire. So the chain is what is waited for, and this is only the
-- settle on top of it.
local AUTO_DELAY_TICKS = 100

-- How many profiles a board has, when neither the status read nor the session says. Their own
-- status reply carries `pid_profile_count`, which is where the real number comes from; this is
-- only what the refusal falls back on, and it is the count every current target ships.
local PROFILE_COUNT_FALLBACK = 6

-- Every read this module makes is a read, and 250 is a write with an empty payload. The queue
-- infers `isWrite` from a non-empty payload (tasks/msp/queue.lua), which is wrong for both: 156
-- carries a slot index and is still a read, 250 carries nothing and is still a write. Both are
-- therefore stated rather than inferred, everywhere below.

-- ---------------------------------------------------------------------------
-- The link
-- ---------------------------------------------------------------------------

local MspRuntime = nil
local function mspState()
  if MspRuntime == nil then
    MspRuntime = requireModule("tasks/msp/runtime.lua") or false
  end
  if MspRuntime == false or type(MspRuntime.getState) ~= "function" then return nil end
  local state = MspRuntime.getState()
  if type(state) ~= "table" then return nil end
  return state
end

local function queueOf()
  local state = mspState()
  if state == nil or type(state.queue) ~= "table" or type(state.queue.add) ~= "function" then return nil end
  return state.queue
end

--- Whether the board is armed, from both places that know.
--
-- The widget's own copy is what the screen is drawn from; the MSP runtime's is what actually
-- gates the queue. Either one saying armed is enough: the two are read from the same sensor a
-- pass apart, and the cost of believing the earlier of them is a prime that starts a moment
-- later, while the cost of believing the later one is a request the runtime throws away.
local function isArmed(widget)
  local state = widget and widget.state
  if type(state) == "table" and state.armed == true then return true end
  local msp = mspState()
  return type(msp) == "table" and msp.lastArmed == true
end

local function apiModule(name)
  if type(name) ~= "string" or name == "" then return nil end
  return requireModule("tasks/msp/api/" .. name .. ".lua")
end

-- ---------------------------------------------------------------------------
-- The run
-- ---------------------------------------------------------------------------

M.PHASE_IDLE = "idle"
M.PHASE_RXMAP = "rxmap"
M.PHASE_FUNCTION_IDS = "functionIds"
M.PHASE_SLOTS = "slots"
M.PHASE_VALUES = "values"
M.PHASE_DONE = "done"
M.PHASE_ERROR = "error"

local RUNNING = {
  [M.PHASE_RXMAP] = true, [M.PHASE_FUNCTION_IDS] = true,
  [M.PHASE_SLOTS] = true, [M.PHASE_VALUES] = true
}

--- Whether a run is still expecting a reply.
function M.isRunning(drive)
  local prime = type(drive) == "table" and drive.prime or nil
  return type(prime) == "table" and RUNNING[prime.phase] == true
end

local function bump(drive)
  drive.valueEpoch = (drive.valueEpoch or 0) + 1
end

--- The reply belongs to the run that is still current, or it belongs to nothing.
--
-- A prime that was restarted, abandoned or failed leaves its messages in the queue, and their
-- callbacks close over the run they were made for. Comparing the run rather than a flag is what
-- keeps a late reply from a previous attempt out of the current one's counters.
local function stillCurrent(drive, prime)
  return type(drive) == "table" and drive.prime == prime and RUNNING[prime.phase] == true
end

local function fail(drive, prime, reason)
  if not stillCurrent(drive, prime) then return false end
  prime.phase = M.PHASE_ERROR
  prime.error = tostring(reason or "failed")
  bump(drive)
  logPrime("prime failed in %s: %s", tostring(prime.failedIn or "?"), prime.error)
  return false
end

--- A run given up rather than failed: the board was armed into, or the runtime cleared the queue,
-- which while armed is the same event seen from the other side. It is not an error and it is not
-- shown as one -- the pilot armed, which is allowed.
local function abandon(drive, prime, why)
  if not stillCurrent(drive, prime) then return end
  prime.phase = M.PHASE_IDLE
  prime.error = nil
  bump(drive)
  logPrime("prime abandoned: %s", tostring(why))
end

local function advanced(drive, prime)
  prime.done = (prime.done or 0) + 1
  bump(drive)
end

--- One handler for every message this module sends: the queue's own clear is an abandon, and
-- everything else -- a timeout, the retry budget, a board that answered with an error -- is a
-- failure the screen names.
local function replyFailed(drive, prime, where)
  return function(_, reason)
    if reason == "cleared" then
      abandon(drive, prime, "queue cleared")
      return
    end
    prime.failedIn = where
    fail(drive, prime, reason)
  end
end

-- ---------------------------------------------------------------------------
-- The board's own slot table, turned into a set
-- ---------------------------------------------------------------------------

--- The wire channel an AUX field of a slot record names.
--
-- The record's field is a 0-based index into the receiver's AUX channels, and which wire channel
-- AUX1 actually is comes out of the receiver map (MSP 64). Above AUX3 the map says nothing and
-- the channels are consecutive from AUX1, which is the extrapolation their own adjustments page
-- makes. The return is 1-based, the way "ch11" is spelled.
function M.auxToWireChannel(auxField, map)
  local index = math.floor(tonumber(auxField) or 0)
  if index < 0 then index = 0 end
  if index > (AUX_FIELD_COUNT - 1) then index = AUX_FIELD_COUNT - 1 end

  local member = nil
  if type(map) == "table" then
    if index == 0 then member = tonumber(map.aux1) end
    if index == 1 then member = tonumber(map.aux2) end
    if index == 2 then member = tonumber(map.aux3) end
    if member == nil then
      local base = tonumber(map.aux1)
      if base ~= nil then member = base + index end
    end
  end
  if member == nil then member = AUX_MEMBER_BASE + index end
  return member + 1
end

local function windowKey(window)
  if type(window) ~= "table" then return nil end
  local from = tonumber(window.start)
  local to = tonumber(window["end"])
  if from == nil or to == nil then return nil end
  return tostring(from) .. ":" .. tostring(to), from, to
end

--- The set the board is actually configured for: which parameter answers which bank and row.
--
-- Nothing about the layout is assumed. The BANKS are the distinct enable windows the usable slots
-- name, in rising microseconds -- that is the order a switch or a variable walks them in. The
-- ROWS are the distinct INCREMENT windows, in FALLING microseconds, so row 1 is the one furthest
-- from centre: that is the row the documented layout drives with the largest trim throw, and a
-- board configured some other way still gets its own outermost pair as row 1.
--
-- A slot is usable only when it steps -- a continuous slot has no park position, so nothing on
-- this screen could leave it alone -- and when both of its channels are the ones this model
-- devotes to the pair. A slot on some other channel belongs to a switch the pilot flies with and
-- is none of the overlay's business.
--
-- Answers nil when nothing usable came back, which is what keeps the documented layout as the
-- fallback rather than replacing it with an empty table.
function M.deriveSet(records, map, bankChannel, valueChannel)
  if type(records) ~= "table" then return nil, {} end

  local usable, skipped = {}, {}
  for slot = 1, SLOT_COUNT do
    local record = records[slot]
    if type(record) == "table" and (tonumber(record.adjFunction) or 0) ~= 0 then
      local enableCh = M.auxToWireChannel(record.enaChannel, map)
      local valueCh = M.auxToWireChannel(record.adjChannel, map)
      if enableCh == bankChannel and valueCh == valueChannel then
        if (tonumber(record.adjStep) or 0) > 0 then
          usable[#usable + 1] = record
        else
          skipped[#skipped + 1] = slot
        end
      end
    end
  end

  if #usable == 0 then return nil, skipped end

  local bands, bandSeen = {}, {}
  local rows, rowSeen = {}, {}
  for i = 1, #usable do
    local record = usable[i]
    local bandKey, bandFrom, bandTo = windowKey(record.enaRange)
    if bandKey ~= nil and bandSeen[bandKey] == nil then
      bandSeen[bandKey] = true
      bands[#bands + 1] = { key = bandKey, min = bandFrom, max = bandTo }
    end
    local rowKey, rowFrom, rowTo = windowKey(record.adjRange2)
    if rowKey ~= nil and rowSeen[rowKey] == nil then
      rowSeen[rowKey] = true
      rows[#rows + 1] = { key = rowKey, min = rowFrom, max = rowTo }
    end
  end

  table.sort(bands, function(a, b)
    if a.min ~= b.min then return a.min < b.min end
    return a.max < b.max
  end)
  table.sort(rows, function(a, b)
    if a.min ~= b.min then return a.min > b.min end
    return a.max > b.max
  end)

  local bandIndex, rowIndex = {}, {}
  local outBands, bankValues = {}, {}
  for i = 1, #bands do
    if i > Functions.BANK_COUNT then break end
    bandIndex[bands[i].key] = i
    outBands[i] = { min = bands[i].min, max = bands[i].max }
    bankValues[i] = Functions.bandMidGv(outBands[i])
  end
  for i = 1, #rows do
    if i > Functions.ROW_COUNT then break end
    rowIndex[rows[i].key] = i
  end

  local set, placed = {}, 0
  for i = 1, #usable do
    local record = usable[i]
    local bank = bandIndex[windowKey(record.enaRange) or ""]
    local row = rowIndex[windowKey(record.adjRange2) or ""]
    if bank ~= nil and row ~= nil then
      set[bank] = set[bank] or {}
      -- The first slot wins a cell it shares. Two slots on the same window pair are a
      -- configuration the board itself cannot resolve either -- it fires whichever it reaches
      -- first -- so guessing the other one here would only disagree with the flight controller.
      if set[bank][row] == nil then
        set[bank][row] = math.floor(tonumber(record.adjFunction) or 0)
        placed = placed + 1
      end
    end
  end

  if placed == 0 then return nil, skipped end
  return { bands = outBands, bankValues = bankValues, set = set, placed = placed }, skipped
end

local function applySet(drive, prime)
  local derived, skipped = M.deriveSet(prime.records, prime.map,
    drive.settings.bank_ch, drive.settings.value_ch)
  prime.skipped = skipped or {}
  if derived == nil then
    drive.setSource = "reference"
    logPrime("slot table yielded nothing usable; the documented layout stands")
    return
  end

  drive.bands = derived.bands
  drive.bankValues = derived.bankValues
  drive.set = derived.set
  drive.setSource = "board"
  logPrime("slot table gave %d cell(s) over %d band(s)", derived.placed, #derived.bands)

  -- The selection may be pointing at a cell the board's own table does not have.
  if drive:functionId(drive.bank, drive.row) == nil then
    for bank = 1, Functions.BANK_COUNT do
      for row = 1, Functions.ROW_COUNT do
        if drive:functionId(bank, row) ~= nil then
          drive.bank, drive.row = bank, row
          return
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- The phases
-- ---------------------------------------------------------------------------

local sendValues

local function sendValueRead(widget, drive, prime, queue)
  local command = Functions.VALUE_READS[prime.valueAt]
  if command == nil then
    -- Everything the nine reads can answer is in the cache. The snapshot the delta is measured
    -- against is taken here only when no backup has been made yet: once one exists, THAT is what
    -- the flight is compared with, and re-priming must not quietly move the baseline.
    if type(drive.backup) ~= "table" then
      local copy = {}
      for id, value in pairs(drive.values) do copy[id] = value end
      drive.primedValues = copy
    end
    prime.phase = M.PHASE_DONE
    bump(drive)
    logPrime("prime done: %d value(s) cached, %d id(s) unanswered", prime.mapped or 0, prime.unmapped or 0)
    return true
  end

  local moduleName, fields = Functions.fieldsForCommand(command)
  local api = apiModule(moduleName)
  if api == nil or type(api.parse) ~= "function" or type(api.simulatorResponse) ~= "table" then
    -- A module the tree does not have, or one with nothing to answer under the simulator, is
    -- skipped rather than fatal: the ids behind it stay unknown and the screen shows them so.
    prime.unmapped = (prime.unmapped or 0) + ((fields and #fields) or 0)
    prime.valueAt = prime.valueAt + 1
    advanced(drive, prime)
    return sendValueRead(widget, drive, prime, queue)
  end

  queue:add({
    command = command,
    isWrite = false,
    simulatorResponse = api.simulatorResponse,
    client = M.CLIENT,
    processReply = function(_, buf)
      if not stillCurrent(drive, prime) then return end
      local parsed = api.parse(buf)
      if type(parsed) == "table" then
        for i = 1, #fields do
          local entry = fields[i]
          local value = tonumber(parsed[entry.field])
          if value == nil then
            prime.unmapped = (prime.unmapped or 0) + 1
          else
            drive.values[entry.id] = value
            prime.mapped = (prime.mapped or 0) + 1
          end
        end
        -- The status reply is the only one that says how many profiles this board has and which
        -- of them is live, and the undo needs both.
        if command == CMD_STATUS then prime.status = parsed end
      end
      prime.valueAt = prime.valueAt + 1
      advanced(drive, prime)
      sendValues(widget, drive, prime)
    end,
    errorHandler = replyFailed(drive, prime, "values")
  })
  return true
end

sendValues = function(widget, drive, prime)
  local queue = queueOf()
  if queue == nil then
    prime.failedIn = "values"
    return fail(drive, prime, "no_link")
  end
  return sendValueRead(widget, drive, prime, queue)
end

local function startValues(widget, drive, prime)
  prime.phase = M.PHASE_VALUES
  prime.valueAt = 1
  prime.mapped = 0
  prime.unmapped = 0
  bump(drive)
  return sendValues(widget, drive, prime)
end

local function sendSlot(widget, drive, prime)
  local queue = queueOf()
  if queue == nil then
    prime.failedIn = "slots"
    return fail(drive, prime, "no_link")
  end

  local slot = prime.slotList[prime.slotAt]
  if slot == nil then
    applySet(drive, prime)
    return startValues(widget, drive, prime)
  end

  local api = prime.rangeApi
  queue:add({
    command = CMD_ADJ_RANGE,
    -- The slot index is 0-based on the wire, and this payload does not make the message a write:
    -- it carries which slot to answer for, and the queue is told so rather than left to infer it.
    payload = { slot - 1 },
    isWrite = false,
    simulatorResponse = api.simulatorResponse,
    client = M.CLIENT,
    processReply = function(_, buf)
      if not stillCurrent(drive, prime) then return end
      local parsed = api.parse(buf)
      local record = type(parsed) == "table" and parsed.adjustment_range or nil
      if type(record) == "table" then prime.records[slot] = record end
      prime.slotAt = prime.slotAt + 1
      advanced(drive, prime)
      sendSlot(widget, drive, prime)
    end,
    errorHandler = replyFailed(drive, prime, "slots")
  })
  return true
end

local function sendFunctionIds(widget, drive, prime)
  local queue = queueOf()
  if queue == nil then
    prime.failedIn = "functionIds"
    return fail(drive, prime, "no_link")
  end
  local api = apiModule("get_adjustment_function_ids")
  if api == nil then
    prime.failedIn = "functionIds"
    return fail(drive, prime, "no_api")
  end

  queue:add({
    command = CMD_ADJ_FUNCTION_IDS,
    isWrite = false,
    simulatorResponse = api.simulatorResponse,
    client = M.CLIENT,
    processReply = function(_, buf)
      if not stillCurrent(drive, prime) then return end
      local parsed = api.parse(buf)
      local ids = type(parsed) == "table" and parsed.adjustment_function_ids or nil
      if type(ids) ~= "table" then
        prime.failedIn = "functionIds"
        fail(drive, prime, "no_function_ids")
        return
      end
      -- Only the slots that name a function are read in full. An empty slot has nothing in its
      -- record worth 14 bytes and a round trip, and on this transport that is the whole cost.
      prime.slotList = {}
      for slot = 1, SLOT_COUNT do
        if (tonumber(ids[slot]) or 0) ~= 0 then prime.slotList[#prime.slotList + 1] = slot end
      end
      prime.slotAt = 1
      prime.rangeApi = apiModule("get_adjustment_range")
      if prime.rangeApi == nil then
        prime.failedIn = "slots"
        fail(drive, prime, "no_api")
        return
      end
      -- The estimate the run started with was the whole table; now the length is known.
      prime.total = 2 + #prime.slotList + #Functions.VALUE_READS
      prime.phase = M.PHASE_SLOTS
      advanced(drive, prime)
      sendSlot(widget, drive, prime)
    end,
    errorHandler = replyFailed(drive, prime, "functionIds")
  })
  return true
end

local function sendRxMap(widget, drive, prime)
  local queue = queueOf()
  if queue == nil then
    prime.failedIn = "rxmap"
    return fail(drive, prime, "no_link")
  end
  local api = apiModule("rx_map")
  if api == nil then
    prime.failedIn = "rxmap"
    return fail(drive, prime, "no_api")
  end

  queue:add({
    command = CMD_RX_MAP,
    isWrite = false,
    simulatorResponse = api.simulatorResponse,
    client = M.CLIENT,
    processReply = function(_, buf)
      if not stillCurrent(drive, prime) then return end
      -- A receiver that does not answer its map is not fatal: without it AUX1 is taken to be the
      -- sixth channel, which is where every documented setup puts it.
      prime.map = api.parse(buf)
      prime.phase = M.PHASE_FUNCTION_IDS
      advanced(drive, prime)
      sendFunctionIds(widget, drive, prime)
    end,
    errorHandler = replyFailed(drive, prime, "rxmap")
  })
  return true
end

--- Read the board: the receiver map, the slot table, and the nine value reads.
--
-- Refused while armed and without a link. The counters start at the whole table's length and are
-- corrected down once 167 has said how many slots actually carry a function.
function M.start(widget, drive)
  if type(widget) ~= "table" or type(drive) ~= "table" then return false, "no_drive" end
  if isArmed(widget) then return false, "armed" end
  if queueOf() == nil then return false, "no_link" end

  local prime = {
    phase = M.PHASE_RXMAP,
    done = 0,
    total = 2 + SLOT_COUNT + #Functions.VALUE_READS,
    records = {},
    skipped = {},
    slotList = {},
    slotAt = 1,
    valueAt = 1,
    mapped = 0,
    unmapped = 0
  }
  drive.prime = prime
  bump(drive)
  logPrime("prime started")
  return sendRxMap(widget, drive, prime)
end

--- Read the values again, without the slot table. What a restore puts back on the board is a set
-- of values, not a layout, so re-reading 42 slot records to learn them would be 42 round trips
-- spent on something that cannot have moved.
function M.refreshValues(widget, drive)
  if type(widget) ~= "table" or type(drive) ~= "table" then return false, "no_drive" end
  if isArmed(widget) then return false, "armed" end
  local prime = drive.prime
  if type(prime) ~= "table" or type(prime.records) ~= "table" then return M.start(widget, drive) end
  if queueOf() == nil then return false, "no_link" end
  prime.error = nil
  prime.done = 0
  prime.total = #Functions.VALUE_READS
  return startValues(widget, drive, prime)
end

-- ---------------------------------------------------------------------------
-- The undo
-- ---------------------------------------------------------------------------

--- Which PID profile the board is flying, 0-based.
--
-- The telemetry sensor counts from 1, the way the pilot's own menus do; the status reply counts
-- from 0, the way the wire does. The sensor is preferred because it is live even when nothing has
-- been primed this session.
function M.activeProfile0(drive)
  local sensor = tonumber(drive.radio.sensor("PID#"))
  if sensor == nil then sensor = tonumber(drive.profile) end
  if sensor ~= nil and sensor >= 1 then return math.floor(sensor) - 1 end
  local status = drive.prime and drive.prime.status or nil
  local index = status and tonumber(status.current_pid_profile_index) or nil
  if index ~= nil then return math.floor(index) end
  return nil
end

--- How many PID profiles this board has. Their status reply carries the number, and their own
-- status task keeps the last one on the session. The constant is what is left when neither spoke.
function M.profileCount(drive)
  local status = drive.prime and drive.prime.status or nil
  local count = status and tonumber(status.pid_profile_count) or nil
  if count == nil then
    local session = _G.rfsuite and _G.rfsuite.session or nil
    count = type(session) == "table" and tonumber(session.pid_profile_count) or nil
  end
  if count == nil or count < 1 then count = PROFILE_COUNT_FALLBACK end
  return math.floor(count)
end

--- What stands between this model and a usable undo, or nil when nothing does.
function M.transferRefusal(widget, drive)
  if isArmed(widget) then return "armed" end
  local backup = math.floor(tonumber(drive.settings.backup_profile) or 0)
  if backup <= 0 then return "unset" end
  if backup > M.profileCount(drive) then return "range" end
  local active0 = M.activeProfile0(drive)
  if active0 == nil then return "no_active" end
  -- Copying a profile onto itself is not a no-op on the board: it is a write and an eeprom
  -- commit, and it would leave the pilot believing an undo exists where none does.
  if (backup - 1) == active0 then return "same" end
  if queueOf() == nil then return "no_link" end
  return nil
end

local function copyProfile(drive, destination0, source0, kind, onDone)
  local queue = queueOf()
  if queue == nil then return false, "no_link" end

  drive.transfer = { kind = kind, state = "busy" }
  bump(drive)

  local function finished(ok, reason)
    if type(drive.transfer) ~= "table" or drive.transfer.kind ~= kind then return end
    drive.transfer.state = ok and "ok" or "error"
    drive.transfer.reason = ok and nil or tostring(reason or "failed")
    bump(drive)
    if ok and type(onDone) == "function" then onDone() end
  end

  queue:add({
    command = CMD_COPY_PROFILE,
    payload = { PROFILE_TYPE_PID, destination0, source0 },
    isWrite = true,
    simulatorResponse = {},
    client = M.CLIENT,
    processReply = function()
      -- The copy lives in RAM until the board is told to commit it, and the board commits nothing
      -- on its own until the next disarm -- by which time the flight this undo exists for has
      -- been flown. So the write follows immediately, as their copy-profiles page does it.
      queue:add({
        command = CMD_EEPROM_WRITE,
        payload = {},
        isWrite = true,
        simulatorResponse = {},
        client = M.CLIENT,
        processReply = function() finished(true) end,
        errorHandler = function(_, reason) finished(false, reason) end
      })
    end,
    errorHandler = function(_, reason) finished(false, reason) end
  })
  return true
end

--- Copy the flying profile into the spare one, and remember what it held.
--
-- The board writes an in-flight change into its own storage half a second after disarm, so the
-- copy has to exist BEFORE the flight; afterwards there is nothing left to copy. The values are
-- snapshotted at the same moment and for the same reason: after that save nothing on the radio
-- could still say what the profile used to hold, and the delta is measured against this.
function M.backup(widget, drive)
  local refusal = M.transferRefusal(widget, drive)
  if refusal ~= nil then return false, refusal end

  local backup0 = math.floor(tonumber(drive.settings.backup_profile) or 0) - 1
  local active0 = M.activeProfile0(drive)
  local snapshot = {}
  for id, value in pairs(drive.values) do snapshot[id] = value end
  local at = drive.radio.now()

  logPrime("backup: pid profile %d -> %d", active0, backup0)
  return copyProfile(drive, backup0, active0, "backup", function()
    drive.backup = { profile = backup0 + 1, at = at, values = snapshot }
    bump(drive)
  end)
end

--- Put the copy back over the flying profile, and read the values again.
--
-- The cached values describe what the board held a moment ago, which after a restore is exactly
-- what it no longer holds; leaving them would show a delta against a profile that has been undone.
function M.restore(widget, drive)
  local refusal = M.transferRefusal(widget, drive)
  if refusal ~= nil then return false, refusal end

  local backup0 = math.floor(tonumber(drive.settings.backup_profile) or 0) - 1
  local active0 = M.activeProfile0(drive)

  logPrime("restore: pid profile %d -> %d", backup0, active0)
  return copyProfile(drive, active0, backup0, "restore", function()
    M.refreshValues(widget, drive)
  end)
end

-- ---------------------------------------------------------------------------
-- The delta
-- ---------------------------------------------------------------------------

--- Every parameter whose cached value has moved away from the snapshot, largest change first.
--
-- Cached against the drive's value epoch, the way the setup check is cached against the clock: the
-- list is built into the tree rather than read by a closure, so it is wanted once per rebuild and
-- a rebuild happens exactly when that epoch moves.
--
-- Answers nil when there is no snapshot to measure against, which is a different thing from an
-- empty list and is said differently on screen.
function M.delta(drive)
  if type(drive) ~= "table" then return nil end
  local reference = (type(drive.backup) == "table" and drive.backup.values) or drive.primedValues
  if type(reference) ~= "table" then return nil end
  if drive._deltaEpoch == drive.valueEpoch and drive._deltaList ~= nil then return drive._deltaList end

  local list = {}
  for id, value in pairs(drive.values) do
    local was = reference[id]
    if was ~= nil and was ~= value then
      list[#list + 1] = {
        id = id,
        name = Functions.nameOf(id),
        old = was,
        new = value,
        size = math.abs(value - was)
      }
    end
  end
  -- Largest change first, and the id decides a tie: a list whose order depended on how the value
  -- table happened to be walked would reshuffle itself under the pilot between two rebuilds.
  table.sort(list, function(a, b)
    if a.size ~= b.size then return a.size > b.size end
    return a.id < b.id
  end)

  drive._deltaEpoch = drive.valueEpoch
  drive._deltaList = list
  return list
end

-- ---------------------------------------------------------------------------
-- The widget's side
-- ---------------------------------------------------------------------------

--- One pass of the ground half.
--
-- Costs two table reads while armed or disconnected, which is what it does for the whole of a
-- flight. The automatic run fires once per connect, and only after the link has stood for long
-- enough that the connect chain is no longer competing for the same queue.
function M.tick(widget, drive)
  if type(widget) ~= "table" or type(drive) ~= "table" then return end
  if type(widget.state) ~= "table" then return end

  if isArmed(widget) then
    if M.isRunning(drive) then abandon(drive, drive.prime, "armed") end
    drive._primeLinkSince = nil
    return
  end

  if widget.state.fblConnected ~= true then
    drive._primeLinkSince = nil
    drive._primeAutoDone = false
    return
  end

  -- The connect chain owns the queue until it says otherwise. `tasksDone` is the widget's own
  -- reading of that (widgets/dashboard/runtime.lua, updateConnectionState): the onconnect runner
  -- is idle and the MSP progress is complete. Only the AUTOMATIC run is held here -- a pilot who
  -- asks for a prime from the ground screen still gets one straight away.
  if widget.state.tasksDone == false then
    drive._primeLinkSince = nil
    return
  end

  local now = drive.radio.now()
  if drive._primeLinkSince == nil then drive._primeLinkSince = now end
  if drive._primeAutoDone == true then return end
  if (now - drive._primeLinkSince) < AUTO_DELAY_TICKS then return end
  if M.isRunning(drive) then return end

  drive._primeAutoDone = true
  M.start(widget, drive)
end

return M
