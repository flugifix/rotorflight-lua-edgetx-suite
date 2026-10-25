-- The picker stores function ids, independent of their current slot addresses. A missing
-- stored id remains an explicit checked row until the pilot removes it.
local Functions = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/inflight/functions.lua", "t"))()
local M = {}

function M.new(stored, layout)
  local available, indexed, groups = {}, {}, {}
  local function add(id, missing)
    if available[id] then return end
    available[id] = not missing or nil
    local index = Functions.groupOf(id)
    local group = indexed[index]
    if group == nil then
      group = { name = Functions.GROUPS[index].name, entries = {} }
      indexed[index] = group
    end
    group.entries[#group.entries + 1] = { id = id, name = Functions.nameOf(id), missing = missing == true }
  end
  if layout then
    local derived = Functions.deriveGroups(layout.set, layout.rowValues, layout.bankValues)
    for _, group in ipairs(derived) do
      for _, entry in ipairs(group.entries) do add(entry.id, false) end
    end
  else
    for _, fn in ipairs(Functions.FUNCTIONS) do
      if not Functions.SELECTORS[fn.id] then add(fn.id, false) end
    end
  end
  local wanted = Functions.flightList(stored)
  for id in pairs(wanted) do if not available[id] then add(id, true) end end
  for index = 1, #Functions.GROUPS do
    local group = indexed[index]
    if group then
      table.sort(group.entries, function(a, b) return Functions.parameterOrder(a.id) < Functions.parameterOrder(b.id) end)
      groups[#groups + 1] = group
    end
  end
  return { groups = groups, available = available, stored = stored or "", wanted = wanted }
end

function M.serialize(wanted)
  local ids = {}
  for id in pairs(wanted) do ids[#ids + 1] = id end
  table.sort(ids)
  for i = 1, #ids do ids[i] = tostring(ids[i]) end
  return table.concat(ids, ",")
end

function M.checked(list, entry)
  if list.stored == "" then return not entry.missing end
  return list.wanted[entry.id] == true
end

function M.all(list)
  list.stored, list.wanted = "", {}
end

function M.toggle(list, id, on)
  local wanted = {}
  for key in pairs(list.stored == "" and list.available or list.wanted) do wanted[key] = true end
  wanted[id] = on and true or nil
  -- Empty is the all sentinel, so the last selected row cannot be removed.
  if next(wanted) == nil then return false end
  local all = true
  for key in pairs(list.available) do if not wanted[key] then all = false; break end end
  for key in pairs(wanted) do if not list.available[key] then all = false; break end end
  list.wanted, list.stored = wanted, all and "" or M.serialize(wanted)
  return true
end

return M
