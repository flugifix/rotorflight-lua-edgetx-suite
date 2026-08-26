-- Radio-side helpers for the setup assistant.
--
-- Everything here reads or writes the ACTIVE EdgeTX model. Lua registers no model selection
-- function, so a write can only ever reach the model the pilot has open.
--
-- The rule this file follows throughout: read what is configured, measure only what cannot be
-- read. The mapping and the travel are in the model; only the path to the flight controller
-- needs a hand on a stick.

local M = {}

-- The channel layout the project's own radio setup documents. Index is the wire channel.
-- CH1 to CH6 are the same order the configurator offers as a prepared channel map, so a
-- flight controller at its default map already agrees with this table.
M.BASELINE = {
  [1] = "aileron",
  [2] = "elevator",
  [3] = "collective",
  [4] = "rudder",
  [5] = "arm",
  [6] = "throttle",
  [7] = "profile",
  [8] = "rescue"
}

-- The four sticks, as the radio numbers them, against the wire channel the baseline puts them
-- on. `defaultChannel` answers with the channel THIS radio believes a stick belongs on, which
-- is the second signal every mapping check needs: a check that only watches for movement
-- attributes whatever moved to whatever it asked for.
M.STICKS = {
  { stick = 3, channel = 1, key = "aileron" },
  { stick = 1, channel = 2, key = "elevator" },
  { stick = 2, channel = 3, key = "collective" },
  { stick = 0, channel = 4, key = "rudder" }
}

-- Channels the assistant lays out, in the order it walks them.
--
-- A channel carries a LIST of roles rather than one, on both sides, and the simplification that
-- it carries exactly one fails on real layouts in both directions: the documented blackbox
-- channel is one channel driving two mode boxes at two windows, and the throttle channel needs a
-- hold and a governor source at once. Only one role each is populated here, and the shape is a
-- list so that adding the second is data rather than a rewrite.
--
-- `kind` decides which value window is computed and what is written beside the mix:
--   condition  - one position turns a flight controller mode on, the rest leave it off
--   throttle   - two mixer lines, and the firmware has no mode box for a throttle hold at all
--   adjustment - the whole travel is mapped onto a value range, in adjustment slots
--
-- `tier` has four values and the fourth is not decoration: *required*, *recommended*, *optional*
-- and **unavailable** -- a channel the assistant knows about and cannot deliver today. Marking
-- such a channel *recommended* would promise something the run does not keep.
M.CHANNELS = {
  {
    channel = 5, key = "arm", tier = "required",
    roles = { { kind = "condition", box = "ARM" } }
  },
  {
    channel = 6, key = "throttle", tier = "required",
    roles = { { kind = "throttle" } }
  },
  {
    -- Profile selection is not a mode box: it is two adjustment slots, the rate profile and the
    -- pid profile, driven continuously from one three-position switch onto 1..3.
    channel = 7, key = "profile", tier = "recommended",
    needsPositions = 3,
    roles = { { kind = "adjustment", functions = { 1, 2 }, min = 1, max = 3 } }
  },
  {
    channel = 8, key = "rescue", tier = "recommended",
    roles = { { kind = "condition", box = "RESCUE" } }
  }
}

-- The first role of a channel, which is what every screen renders today. Written as a lookup
-- rather than as `entry.kind` so that the day a channel grows a second role, the callers that
-- must change are the ones that say `firstRole`.
function M.firstRole(entry)
  if type(entry) ~= "table" or type(entry.roles) ~= "table" then return nil end
  return entry.roles[1]
end

-- The four sticks, as INPUTS. This is the level the setup actually lives on: a source belongs in
-- an input, and the mixer line below it is a plain one-to-one from that input to its channel. A
-- switch or a stick written straight into a mixer line produces the same channel value and is not
-- the same setup -- it leaves the input list empty, so the pilot's own radio shows nothing where
-- the configuration is supposed to be.
--
-- The order is the flight controller's, not the transmitter's. A radio at its factory setting
-- carries RETA, and this layout is roll, pitch, collective, yaw -- so on a fresh model two of the
-- four inputs have the wrong source and the assistant is what puts them right.
--
-- `stick` is a FUNCTION, not a label: 0 yaw, 1 pitch, 2 collective, 3 roll, in the numbering the
-- radio's own `defaultChannel` speaks. The names beside it are what the pilot will read and
-- nothing is resolved from them -- `Ail` is EdgeTX's default label for one physical stick in one
-- stick mode, and on a radio set up differently it means another stick or does not exist. What
-- has to come out right is the RESULT: roll on channel one, whatever it is called here.
M.STICK_INPUTS = {
  { input = 0, channel = 1, stick = 3, inputName = "Ail", channelName = "Ail" },
  { input = 1, channel = 2, stick = 1, inputName = "Ele", channelName = "Ele" },
  { input = 2, channel = 3, stick = 2, inputName = "Col", channelName = "Col" },
  { input = 3, channel = 4, stick = 0, inputName = "Rud", channelName = "Rud" }
}

local function callGlobal(name, ...)
  local fn = _G and _G[name]
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if not ok then return nil end
  return a, b
end

local function modelApi(name)
  local model = _G and _G.model
  if type(model) ~= "table" then return nil end
  local fn = model[name]
  if type(fn) ~= "function" then return nil end
  return fn
end

-- Raw channel values run from -1024 to 1024 around centre; the flight controller speaks
-- microseconds. Values already in the microsecond band are passed through, because the same
-- helper is used on numbers arriving from both sides.
function M.rawToUs(value)
  value = tonumber(value)
  if value == nil then return nil end
  if value >= -1200 and value <= 1200 then
    return math.floor(1500 + (value * 500 / 1024) + 0.5)
  end
  if value >= 700 and value <= 2300 then
    return math.floor(value + 0.5)
  end
  return nil
end

-- What the radio is sending on a wire channel right now. This is the radio's own mixer output
-- and says nothing about what arrives at the flight controller.
function M.channelUs(channel)
  local raw = callGlobal("getValue", "ch" .. tostring(channel))
  return M.rawToUs(raw)
end

function M.mixesCount(channel)
  local fn = modelApi("getMixesCount")
  if not fn then return nil end
  local ok, value = pcall(fn, channel - 1)
  if not ok then return nil end
  return tonumber(value) or 0
end

function M.getMix(channel, index)
  local fn = modelApi("getMix")
  if not fn then return nil end
  local ok, mix = pcall(fn, channel - 1, index)
  if not ok or type(mix) ~= "table" then return nil end
  return mix
end

function M.getOutput(channel)
  local fn = modelApi("getOutput")
  if not fn then return nil end
  local ok, out = pcall(fn, channel - 1)
  if not ok or type(out) ~= "table" then return nil end
  return out
end

-- Which wire channel this radio puts a stick on, 1-based, or nil where the radio does not
-- answer for it.
function M.stickChannel(stick)
  local value = tonumber(callGlobal("defaultChannel", stick))
  if value == nil then return nil end
  return value + 1
end

-- A switch position, as the radio's own picker returns it. Positions are grouped three to a
-- switch from the first switch onward, which is what lets a single field carry both halves of
-- the answer: which switch, and which of its states.
local SWSRC_FIRST_SWITCH = 1
local POSITIONS_PER_SWITCH = 3

M.POSITION_UP = 0
M.POSITION_MIDDLE = 1
M.POSITION_DOWN = 2

function M.switchNumber(swsrc)
  swsrc = tonumber(swsrc)
  if swsrc == nil or swsrc < SWSRC_FIRST_SWITCH then return nil end
  return math.floor((swsrc - SWSRC_FIRST_SWITCH) / POSITIONS_PER_SWITCH)
end

function M.switchPosition(swsrc)
  swsrc = tonumber(swsrc)
  if swsrc == nil or swsrc < SWSRC_FIRST_SWITCH then return nil end
  return (swsrc - SWSRC_FIRST_SWITCH) % POSITIONS_PER_SWITCH
end

function M.firstPositionOf(swsrc)
  local number = M.switchNumber(swsrc)
  if number == nil then return nil end
  return SWSRC_FIRST_SWITCH + number * POSITIONS_PER_SWITCH
end

function M.switchPositionName(swsrc)
  return callGlobal("getSwitchName", swsrc)
end

-- The name of the switch itself, without the position symbol the radio appends. The upper and
-- lower symbols are two bytes wide and the middle one is a single hyphen, so how much to drop
-- follows from the position rather than from guessing at the encoding.
function M.switchBaseName(swsrc)
  local name = M.switchPositionName(swsrc)
  if type(name) ~= "string" or name == "" then return nil end
  local drop = 2
  if M.switchPosition(swsrc) == M.POSITION_MIDDLE then drop = 1 end
  if #name <= drop then return nil end
  return string.sub(name, 1, #name - drop)
end

-- The mix source of the switch a position belongs to. A switch and its own source carry the
-- same name, a custom one included, so the lookup goes through the name rather than through a
-- constant Lua is never told. A nil answer means the switch cannot be expressed as a mix
-- source, and then nothing is written for it.
function M.switchSource(swsrc)
  local base = M.switchBaseName(swsrc)
  if base == nil then return nil, nil end
  local id = callGlobal("getSourceIndex", base)
  if id ~= nil then return tonumber(id), base end
  local info = callGlobal("getFieldInfo", base)
  if type(info) == "table" and info.id ~= nil then return tonumber(info.id), base end
  return nil, base
end

-- How many positions this switch actually has. A two-position switch has no middle, so it
-- never rests at centre and its windows are the two ends alone.
function M.switchPositionCount(swsrc)
  local first = M.firstPositionOf(swsrc)
  if first == nil then return nil end
  local count = 0
  for offset = 0, POSITIONS_PER_SWITCH - 1 do
    if M.switchPositionName(first + offset) ~= nil then count = count + 1 end
  end
  if count == 0 then return nil end
  return count
end

-- What a switch position produces on a channel the assistant wrote itself: full deflection at
-- the ends, centre in the middle. Computed rather than measured because the assistant is the
-- author of that mix and therefore knows its transfer function exactly.
function M.positionUs(swsrc)
  local position = M.switchPosition(swsrc)
  if position == nil then return nil end
  if position == M.POSITION_UP then return 2012 end
  if position == M.POSITION_MIDDLE then return 1500 end
  return 988
end

-- The travel a switch actually produces on a channel the assistant wrote itself -- both ends, not
-- the theoretical span of the step encoding.
--
-- This is the difference between a profile switch that lands on 1 / 2 / 3 and one that lands on
-- 1.18 / 2.00 / 2.82 and is only correct by rounding. The assistant authors the mix, so it knows
-- the travel and has no reason to approximate it.
function M.travelRange(swsrc)
  local first = M.firstPositionOf(swsrc)
  if first == nil then return nil end
  return { start = 988, ["end"] = 2012 }
end

-- The value window a mode box gets for a picked position: wide enough to hold the position
-- against switch and receiver tolerance, narrow enough that no other position of the same
-- switch falls inside it.
function M.windowFor(swsrc)
  local position = M.switchPosition(swsrc)
  if position == nil then return nil end
  if position == M.POSITION_MIDDLE then return { start = 1350, ["end"] = 1650 } end
  if position == M.POSITION_UP then return { start = 1700, ["end"] = 2100 } end
  return { start = 900, ["end"] = 1300 }
end

-- Reading a channel back out of the model. A single-line mix with a constant weight, no offset,
-- no curve and no switch of its own is fully computable; anything more involved is reported as
-- found but not derived, because inverting it means simulating the mixer and getting that
-- subtly wrong is easy.
function M.describeChannel(channel)
  local count = M.mixesCount(channel)
  if count == nil then return nil end

  local info = { channel = channel, count = count, lines = {} }
  for i = 0, count - 1 do
    local mix = M.getMix(channel, i)
    if mix then info.lines[#info.lines + 1] = mix end
  end

  if count == 0 then
    info.state = "empty"
    return info
  end

  local first = info.lines[1]
  local simple = (count == 1) and (first ~= nil)
  if simple then
    if (tonumber(first.curveType) or 0) ~= 0 then simple = false end
    if (tonumber(first.offset) or 0) ~= 0 then simple = false end
    if (tonumber(first.switch) or 0) ~= 0 then simple = false end
  end

  info.state = simple and "derived" or "found"
  if first then
    info.source = tonumber(first.source)
    info.sourceName = callGlobal("getSourceName", info.source)
    info.weight = tonumber(first.weight)
  end
  return info
end

-- Writing. Nothing here is called until the pilot has seen the whole list on one screen and
-- pressed once: an assistant that writes a channel per step leaves states behind that are not
-- safe on their own.
function M.clearChannel(channel)
  local fn = modelApi("deleteMix")
  if not fn then return false end
  local count = M.mixesCount(channel) or 0
  for _ = 1, count do
    local ok = pcall(fn, channel - 1, 0)
    if not ok then return false end
  end
  return true
end

local MULTIPLEX_ADD = 0
local MULTIPLEX_REPLACE = 2

-- A condition channel: the picked switch drives the channel over its full travel, so each of
-- its positions lands on a value the window either contains or does not.
function M.writeConditionChannel(channel, swsrc)
  local insert = modelApi("insertMix")
  if not insert then return false, "no_model_api" end
  local source = M.switchSource(swsrc)
  if source == nil then return false, "no_source" end
  if not M.clearChannel(channel) then return false, "clear_failed" end
  local ok = pcall(insert, channel - 1, 0, {
    source = source,
    weight = 100,
    offset = 0,
    switch = 0,
    multiplex = MULTIPLEX_ADD,
    curveType = 0,
    curveValue = 0,
    flightModes = 0
  })
  if not ok then return false, "insert_failed" end
  return true
end

-- The throttle channel, and it is the one place where the safe intermediate state has to be
-- built rather than hoped for. An unassigned channel sits at centre, which the flight
-- controller reads as half throttle rather than as off. So both lines carry the minimum: the
-- base line is a placeholder the drivetrain step later replaces with the governor source, and
-- the hold line overrides it wherever the hold position is present. Until that replacement
-- happens the motor is off in every switch position, which is the correct state for an
-- assistant the pilot may leave at any point.
function M.writeThrottleChannel(channel, swsrc)
  local insert = modelApi("insertMix")
  if not insert then return false, "no_model_api" end
  local source = M.switchSource(swsrc)
  if source == nil then return false, "no_source" end
  if not M.clearChannel(channel) then return false, "clear_failed" end

  local ok = pcall(insert, channel - 1, 0, {
    source = source,
    weight = 0,
    offset = -100,
    switch = 0,
    multiplex = MULTIPLEX_ADD,
    curveType = 0,
    curveValue = 0,
    flightModes = 0
  })
  if not ok then return false, "insert_failed" end

  ok = pcall(insert, channel - 1, 1, {
    source = source,
    weight = 0,
    offset = -100,
    switch = swsrc,
    multiplex = MULTIPLEX_REPLACE,
    curveType = 0,
    curveValue = 0,
    flightModes = 0
  })
  if not ok then return false, "insert_failed" end
  return true
end

-- The mix source that stands for an input. The inputs are the first block of mix sources -- the
-- enumeration opens with "none" and the input block follows it -- so input n is source n + 1. It
-- is derived rather than looked up by name because an input's NAME is something the pilot edits,
-- and a source resolved from a name would move when they rename it.
--
-- The derivation carries its own control: the answer is only used when the radio agrees that the
-- source exists. Where it does not, nothing is written.
local MIXSRC_FIRST_INPUT = 1

function M.inputSource(inputIndex)
  local id = MIXSRC_FIRST_INPUT + (tonumber(inputIndex) or 0)
  if callGlobal("getSourceName", id) == nil then return nil end
  return id
end

-- Is this source id one of the INPUTS? The input block is the first one, so input n is id n + 1,
-- and an id that addresses an input with lines on it is an input rather than a control.
--
-- The test exists because a name cannot tell them apart: an input the pilot has not named is
-- DISPLAYED under the name of its own source, so on a factory model `getSourceIndex("Ail")`
-- answers with the input that happens to carry the aileron stick -- and writing that back makes an
-- input feed itself. Measured on a fresh model: the four stick inputs came out as I3, I1, I2 and
-- one stick, which is what a name lookup produces here rather than a wrong constant.
local MAX_INPUTS_SCAN = 31

-- Is this source id one of the INPUTS? Answered by building the set of ids the inputs actually
-- occupy, rather than by inverting the arithmetic -- `id - 1` is only an input index while it IS
-- one, and asking `getInputsCount` about an index past the end answers something rather than
-- refusing. Reading that answer as "yes, an input" rejected every stick on the first attempt.
local function isInputSource(id)
  id = tonumber(id)
  if id == nil then return false end
  for index = 0, MAX_INPUTS_SCAN do
    local count = M.inputCount(index)
    if count ~= nil and count > 0 and M.inputSource(index) == id then return true end
  end
  return false
end

-- The source id of a control, resolved through the RADIO'S OWN mapping rather than through a name.
--
-- `defaultChannel(f)` answers which channel this radio puts function `f` on by default, and on a
-- model whose inputs are still in that order the input at that channel carries exactly that
-- control. So the pair gives function -> source id with no label anywhere in the chain, which is
-- what makes it survive a different stick mode or a renamed analog.
--
-- It is read ONCE, before anything is written, because the first write destroys the arrangement it
-- reads from.
function M.controlSources()
  local found = {}
  for _, entry in ipairs(M.STICK_INPUTS) do
    local channel = M.stickChannel(entry.stick)
    if channel ~= nil then
      local input = M.getInput(channel - 1, 0)
      local source = input and tonumber(input.source) or nil
      if source ~= nil and not isInputSource(source) then
        found[entry.stick] = source
      end
    end
  end
  return found
end

-- The source for one entry, from a map captured before the first write. A control the radio and
-- the model do not agree on has no answer here, and then nothing is written for that channel: a
-- guessed source id would have the shape of a fact.
function M.controlSource(entry, cache)
  if type(entry) ~= "table" then return nil end
  local map = cache or M.controlSources()
  return map[entry.stick]
end

function M.inputCount(inputIndex)
  local fn = modelApi("getInputsCount")
  if not fn then return nil end
  local ok, value = pcall(fn, inputIndex)
  if not ok then return nil end
  return tonumber(value) or 0
end

function M.getInput(inputIndex, line)
  local fn = modelApi("getInput")
  if not fn then return nil end
  local ok, value = pcall(fn, inputIndex, line)
  if not ok or type(value) ~= "table" then return nil end
  return value
end

-- What one stick input holds today, against what the layout asks of it.
function M.describeStick(entry, cache)
  local info = {
    entry = entry,
    lines = M.inputCount(entry.input),
    wantSource = M.controlSource(entry, cache)
  }
  local first = M.getInput(entry.input, 0)
  if first then
    info.source = tonumber(first.source)
    info.sourceName = callGlobal("getSourceName", info.source)
    info.inputName = first.inputName
  end
  local mixSource = M.inputSource(entry.input)
  local mix = M.getMix(entry.channel, 0)
  info.mixCount = M.mixesCount(entry.channel)
  info.mixSource = mix and tonumber(mix.source) or nil
  info.wantMixSource = mixSource

  info.sourceOk = (info.source ~= nil and info.wantSource ~= nil and info.source == info.wantSource)
  info.mixOk = (info.mixCount == 1 and info.mixSource ~= nil and mixSource ~= nil
                and info.mixSource == mixSource)

  -- The names are part of the target state, not decoration on top of it. Leaving them out of the
  -- criterion is how a channel whose SOURCE was already right kept no name at all: the write only
  -- ran where something was wrong, and the naming lived inside the write. What has to come out
  -- right is the end state.
  local output = M.getOutput(entry.channel)
  info.channelNameNow = output and output.name or nil
  info.nameOk = (info.inputName == entry.inputName and info.channelNameNow == entry.channelName)

  info.ok = info.sourceOk and info.mixOk and info.nameOk
  return info
end

-- Lay one stick out: the input carries the source and the name, the mixer line carries nothing but
-- the input. Existing lines are replaced rather than added to, because a second line on the same
-- channel is a different setup and not a stronger one.
function M.writeStick(entry, cache)
  local insertInput = modelApi("insertInput")
  local deleteInput = modelApi("deleteInput")
  local insertMix = modelApi("insertMix")
  if not insertInput or not deleteInput or not insertMix then return false, "no_model_api" end

  local source = M.controlSource(entry, cache)
  if source == nil then return false, "no_source" end
  local mixSource = M.inputSource(entry.input)
  if mixSource == nil then return false, "no_input_source" end

  -- The existing first line is read before anything is removed, so the fields this layout does not
  -- speak about -- the curve, the side, which trim follows the input -- are carried across rather
  -- than invented. A fresh input is only built where there was none.
  local existing = M.getInput(entry.input, 0)
  local line = {
    name = "",
    inputName = entry.inputName,
    source = source,
    weight = 100,
    offset = 0,
    switch = 0,
    curveType = existing and existing.curveType or 0,
    curveValue = existing and existing.curveValue or 0,
    scale = existing and existing.scale or 0,
    side = existing and existing.side or 3,
    trimSource = existing and existing.trimSource or 0,
    flightModes = 0
  }

  local count = M.inputCount(entry.input) or 0
  for _ = 1, count do
    if not pcall(deleteInput, entry.input, 0) then return false, "clear_input_failed" end
  end
  if not pcall(insertInput, entry.input, 0, line) then return false, "insert_input_failed" end

  if not M.clearChannel(entry.channel) then return false, "clear_failed" end
  local ok = pcall(insertMix, entry.channel - 1, 0, {
    source = mixSource,
    weight = 100,
    offset = 0,
    switch = 0,
    multiplex = MULTIPLEX_ADD,
    curveType = 0,
    curveValue = 0,
    flightModes = 0
  })
  if not ok then return false, "insert_failed" end

  M.setChannelName(entry.channel, entry.channelName)
  return true
end

-- The channel's own label. Not decoration: it is what the pilot reads in the transmitter's output
-- list, and a layout whose channels are called CH1..CH12 is one nobody can check by looking.
function M.setChannelName(channel, name)
  local fn = modelApi("setOutput")
  if not fn or type(name) ~= "string" then return false end
  local current = M.getOutput(channel)
  local value = { name = name }
  if current then
    value.min = tonumber(current.min)
    value.max = tonumber(current.max)
    value.offset = tonumber(current.offset)
    value.ppmCenter = tonumber(current.ppmCenter)
    value.symetrical = tonumber(current.symetrical)
    value.revert = tonumber(current.revert)
  end
  return pcall(fn, channel - 1, value)
end

return M
