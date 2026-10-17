-- app/pages/settings/audio/volume/create.lua
-- Writes the links of the master-volume chain that chain.lua's plan says are missing, and nothing
-- else. It never changes a link that is there and never removes anything: a slot it writes was
-- empty when the plan was read.
--
-- How EdgeTX takes each write (radio/src/lua/api_model.cpp at EdgeTX 2.12):
--   * model.insertInput INSERTS a line, it never overwrites one; into an input with no line, at
--     line 0. It writes nothing, and says nothing, when the model's 64 input lines are all used --
--     which is why each write is read back below rather than trusted.
--   * model.setLogicalSwitch and model.setCustomFunction clear the WHOLE slot first and then set
--     the fields given, so every field the link needs is given, `active` included.
--   * Each write marks the model for EdgeTX to save, and the special functions, logical switches
--     and inputs are evaluated on every mixer cycle, so the chain acts at once.

local M = {}

local function api(name)
  local fn = type(model) == "table" and model[name] or nil
  if type(fn) == "function" then return fn end
  return nil
end

-- The input line: the global variable as its source and nothing that would change its value
-- (weight 100, both sides, no offset, curve, switch, trim or flight-mode restriction) -- exactly
-- what chain.lua checks for. The input keeps whatever name it has.
local function writeInput(slot, gvSource)
  local insertInput, getInputsCount, getInput = api("insertInput"), api("getInputsCount"), api("getInput")
  if not (insertInput and getInputsCount and getInput) then return false end
  if not pcall(insertInput, slot, 0, {
    name = "", source = gvSource, weight = 100, offset = 0, switch = 0, curveType = 0, curveValue = 0,
    scale = 0, side = 3, trimSource = -1, flightModes = 0
  }) then return false end
  local okC, count = pcall(getInputsCount, slot)
  local okL, line = pcall(getInput, slot, 0)
  return okC and tonumber(count) == 1 and okL and type(line) == "table" and tonumber(line.source) == gvSource
end

local function writeLogicalSwitch(slot, gvSource, vpos)
  local set, get = api("setLogicalSwitch"), api("getLogicalSwitch")
  if not (set and get) then return false end
  if not pcall(set, slot, { func = vpos, v1 = gvSource, v2 = -1024 }) then return false end
  local ok, ls = pcall(get, slot)
  return ok and type(ls) == "table" and tonumber(ls.func) == vpos and tonumber(ls.v1) == gvSource
    and tonumber(ls.v2) == -1024
end

local function writeSpecialFunction(slot, switch, inputSource, volume)
  local set, get = api("setCustomFunction"), api("getCustomFunction")
  if not (set and get) then return false end
  if not pcall(set, slot, { switch = switch, func = volume, value = inputSource, active = 1 }) then return false end
  local ok, cf = pcall(get, slot)
  return ok and type(cf) == "table" and tonumber(cf.switch) == switch and tonumber(cf.func) == volume
    and tonumber(cf.value) == inputSource and tonumber(cf.active) == 1
end

--- Writes the links `plan` (chain.lua M.plan) marks `create`, in the order input, logical switch,
--- special function -- the special function names the other two, so it goes last -- and stops at
--- the first write the model does not read back. `read` is the chain.lua answer the plan came from.
---
--- Returns { created = { "input" | "ls" | "sf", ... }, failed = kind or nil }.
function M.write(plan, read)
  local out = { created = {} }
  local inputSource = read.firstInput + plan.input.slot
  local switch = read.lsBase + plan.ls.slot
  local steps = {
    { kind = "input", fn = function() return writeInput(plan.input.slot, read.gvSource) end },
    { kind = "ls", fn = function() return writeLogicalSwitch(plan.ls.slot, read.gvSource, read.vpos) end },
    { kind = "sf", fn = function() return writeSpecialFunction(plan.sf.slot, switch, inputSource, read.volume) end },
  }
  for _, step in ipairs(steps) do
    if plan[step.kind].create then
      if not step.fn() then
        out.failed = step.kind
        return out
      end
      out.created[#out.created + 1] = step.kind
    end
  end
  return out
end

return M
