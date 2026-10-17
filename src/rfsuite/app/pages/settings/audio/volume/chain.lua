-- app/pages/settings/audio/volume/chain.lua
-- Reads the model for the chain that lets a global variable set the radio's master volume, for the
-- Volume page's diagnosis. It reads and never writes.
--
-- EdgeTX's Volume special function cannot take a global variable as its source, so the chain has
-- three links, and the suite only knows the global variable:
--   an input whose source is GVx                      (model.getInput: `source`)
--   a logical switch a > x with a = GVx, x = -1024    (model.getLogicalSwitch: `func`, `v1`, `v2`)
--   a Volume special function switched by that logical switch, with that input as its source
--                                                     (model.getCustomFunction: `switch`, `func`, `value`)
-- Any slots will do, so all of them are searched: whatever combination forms a complete chain
-- counts. Mixes are not searched -- a mix that also uses GVx is the pilot's own business, and
-- reading every line of every channel would cost more than the whole rest of this.
--
-- The encodings, from radio/src at EdgeTX 2.12:
--   * an input's `source` and a logical switch's `v1` are mix source numbers; GV n is
--     getFieldInfo("gvar1").id + n - 1, which the page already resolves for its picker.
--   * input k (0-based) as a mix source is MIXSRC_FIRST_INPUT + k (dataconstants.h: the inputs
--     are the first block after "none"; the same rule app/pages/setup_wizard/radio.lua uses).
--   * for a logical switch on a global variable, `v2` is the raw value compared with
--     (switches.cpp, getLogicalSwitch: `y = ls->v2` once v1 is a global variable), so -1024 reads
--     back as -1024.
--   * logical switch k (0-based) as a switch is the index of "L01" + k (strhelpers.cpp names
--     them L01..L64); a NEGATIVE switch is the inverted one ("!L01"), which is not the chain.
--   * a Volume special function's source is its `value` field (functions.cpp calls
--     calcVolumeValue(CFN_PARAM(cfn)), and CFN_PARAM is all.val, which getCustomFunction
--     returns as `value`); `active` is 0 when the function is switched off.

local M = {}

-- radio/src/dataconstants.h: the same on every colour radio.
local MAX_INPUTS = 32
local MAX_LOGICAL_SWITCHES = 64
local MAX_SPECIAL_FUNCTIONS = 64

-- The value the suite writes when it lets go; the logical switch has to be false exactly then.
local RELEASE = -1024

local function api(name)
  local fn = type(model) == "table" and model[name] or nil
  if type(fn) == "function" then return fn end
  return nil
end

local function call(fn, ...)
  local ok, v = pcall(fn, ...)
  if ok then return v end
  return nil
end

-- The switch number of L01. Asked of the firmware by name; past it, the logical switches are the
-- last block of switches before ON (dataconstants.h, SWSRC_LAST_LOGICAL_SWITCH = SWSRC_LAST).
local function firstLogicalSwitch()
  if type(getSwitchIndex) == "function" then
    local idx = tonumber(call(getSwitchIndex, "L01"))
    if idx ~= nil and idx > 0 then return idx end
  end
  local last = tonumber(_G.SWSRC_LAST)
  if last ~= nil then return last - MAX_LOGICAL_SWITCHES + 1 end
  return nil
end

--- What the model holds for global variable `gv` (1-based), whose mix source number is `gvSource`.
---
--- Returns a table:
---   readable  false when this radio cannot answer (no model getters, or a constant missing); the
---             page then says so instead of reporting a fault the model may not have.
---   complete  true when one input, one logical switch and one Volume function form the chain.
---   input, ls, sf
---             the slot found for each link, 0-based, or nil. With a complete chain, the chain's.
---   lsWrongX  { slot, x } for a logical switch a > x on GVx with another x, when none has -1024.
---   sfFault   { slot, kind, source | switch } for a Volume function on one link but not the
---             other: kind "source" (switched right, `source` is what it takes instead) or
---             "switch" (right source, `switch` is what switches it instead).
---   inputSource, lsSwitch
---             the mix source of the input found and the switch of the logical switch found, for
---             the page's names.
---   warn      the conditions that let the chain be found and still not do what it should.
function M.read(gv, gvSource)
  local result = { readable = false }
  local getInputsCount, getInput = api("getInputsCount"), api("getInput")
  local getLogicalSwitch, getCustomFunction = api("getLogicalSwitch"), api("getCustomFunction")
  local vpos, volume = tonumber(_G.LS_FUNC_VPOS), tonumber(_G.FUNC_VOLUME)
  local firstInput = tonumber(_G.MIXSRC_FIRST_INPUT)
  local lsBase = firstLogicalSwitch()
  gvSource = tonumber(gvSource)
  if not (getInputsCount and getInput and getLogicalSwitch and getCustomFunction)
    or vpos == nil or volume == nil or firstInput == nil or lsBase == nil or gvSource == nil then
    return result
  end
  result.readable = true

  -- Inputs whose source is GVx: by mix source number, the line that carries it.
  local inputs, firstFound = {}, nil
  for i = 0, MAX_INPUTS - 1 do
    local count = tonumber(call(getInputsCount, i)) or 0
    for l = 0, count - 1 do
      local line = call(getInput, i, l)
      if type(line) == "table" and tonumber(line.source) == gvSource then
        inputs[firstInput + i] = { slot = i, line = line, lines = count }
        if firstFound == nil then firstFound = firstInput + i end
        break
      end
    end
  end

  -- Logical switches a > x on GVx with x = -1024, by switch number.
  local switches, firstSwitch, wrongX = {}, nil, nil
  for k = 0, MAX_LOGICAL_SWITCHES - 1 do
    local ls = call(getLogicalSwitch, k)
    if type(ls) == "table" and ls.func == vpos and tonumber(ls.v1) == gvSource then
      if tonumber(ls.v2) == RELEASE then
        switches[lsBase + k] = { slot = k, ls = ls }
        if firstSwitch == nil then firstSwitch = lsBase + k end
      elseif wrongX == nil then
        wrongX = { slot = k, x = tonumber(ls.v2) }
      end
    end
  end

  -- The Volume functions: the first one that joins a found switch to a found input is the chain.
  local chain, volumes = nil, {}
  for f = 0, MAX_SPECIAL_FUNCTIONS - 1 do
    local cf = call(getCustomFunction, f)
    if type(cf) == "table" and cf.func == volume then
      local entry = { slot = f, cf = cf, sw = tonumber(cf.switch), src = tonumber(cf.value) }
      volumes[#volumes + 1] = entry
      if chain == nil and switches[entry.sw] and inputs[entry.src] then chain = entry end
    end
  end

  local inputKey, switchKey
  if chain then
    result.complete = true
    inputKey, switchKey = chain.src, chain.sw
    result.sf = chain.slot
  else
    inputKey, switchKey = firstFound, firstSwitch
    -- A Volume function on one link but not the other is the fault worth naming.
    for _, entry in ipairs(volumes) do
      if switches[entry.sw] then
        result.sfFault = { slot = entry.slot, kind = "source", source = entry.src }
        break
      end
      if inputs[entry.src] then
        result.sfFault = { slot = entry.slot, kind = "switch", switch = entry.sw }
        break
      end
    end
    if switchKey == nil then result.lsWrongX = wrongX end
  end

  local warn = {}
  result.warn = warn
  local input = inputKey and inputs[inputKey]
  if input then
    result.input, result.inputSource = input.slot, inputKey
    local line = input.line
    local weight = tonumber(line.weight)
    if weight ~= nil and weight ~= 100 then warn.weight = weight end
    local offset = tonumber(line.offset)
    if offset ~= nil and offset ~= 0 then warn.offset = offset end
    -- Every curve type leaves the value as it is at curve value 0 (curves.cpp, applyCurve).
    if (tonumber(line.curveValue) or 0) ~= 0 then warn.curve = true end
    if (tonumber(line.switch) or 0) ~= 0 then warn.inputSwitch = true end
    if (tonumber(line.flightModes) or 0) ~= 0 then warn.flightModes = true end
    -- `side` is the line's Side (radio/src/myeeprom.h, EXPO_MODE_ENABLE): bit 1 lets negative
    -- values through, bit 2 positive ones, 3 both. On one side, the other half of the global
    -- variable's span reads as 0. Firmware before EdgeTX 2.11 has no `side` and is not warned.
    local side = tonumber(line.side)
    if side ~= nil and side ~= 3 then warn.side = side end
    -- Of an input's lines, the first one whose switch and flight modes let it through is the
    -- input's value and the lines after it are not looked at (mixer.cpp, applyExpos), so
    -- another line can take the input over from the global variable's.
    if input.lines > 1 then warn.lines = input.lines end
  end
  local switch = switchKey and switches[switchKey]
  if switch then
    result.ls, result.lsSwitch = switch.slot, switchKey
    local ls = switch.ls
    if (tonumber(ls["and"]) or 0) ~= 0 then warn.andSwitch = true end
    if (tonumber(ls.delay) or 0) ~= 0 then warn.delay = true end
    if (tonumber(ls.duration) or 0) ~= 0 then warn.duration = true end
  end
  if chain then
    if tonumber(chain.cf.active) == 0 then warn.sfOff = true end
    -- Two Volume functions that are both on fight over the volume; the one further down wins.
    for _, entry in ipairs(volumes) do
      if entry ~= chain and tonumber(entry.cf.active) ~= 0 and (entry.sw or 0) ~= 0 then
        warn.secondSf = entry.slot
        break
      end
    end
  end
  local details = api("getGlobalVariableDetails")
  local gvDetails = details and call(details, gv - 1)
  if type(gvDetails) == "table" and gvDetails.popup and gvDetails.popup ~= 0 then warn.popup = true end

  return result
end

return M
