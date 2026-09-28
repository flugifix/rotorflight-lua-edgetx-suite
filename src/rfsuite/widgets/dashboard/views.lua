-- The dashboard widget's fullscreen views: which surface fullscreen shows, and what follows a
-- press on one of them.
--
-- A view is a module with `build(children, widget)`, and optionally `renderKey(widget)`, that
-- draws the whole fullscreen tree. Which one is on screen is a bounded stack of view ids on the
-- widget, `widget._viewStack`, lying above a base layer:
--
--   * the top of the stack is what fullscreen shows;
--   * with the stack empty the base layer shows. `widget._viewBase` is the hook for it, and it
--     is nil: nothing in the runtime sets it yet. It is where a later theme mode that draws its
--     own fullscreen puts itself. With no base layer and an empty stack the default view -- the
--     quick menu -- is shown, which is what fullscreen has always shown on entry.
--
-- The stack is one field, so that the pass which arrives without an event -- fullscreen has
-- been left, possibly by a long press on RTN that Lua never saw -- drops all of it in one
-- assignment in widgets/dashboard/runtime.lua.
--
-- What follows a press is data rather than code. An entry, an option or a button carries an
-- `after` action; its `press` does the work only, and `navigate()` below performs the follow-up.
-- `navigate()` is therefore the one place a view leaves fullscreen from. The in-flight tuning
-- surface is not a view here -- it takes fullscreen ahead of all of them -- and keeps its own
-- close box.
--
-- Loaded on the first fullscreen pass, never on a zone pass, and by the rfsuite.batteryPick
-- handle when something calls it. Nothing here is module state: the registry and the stack live
-- on the widget, so a second copy of this module would change nothing.

local M = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require) or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local chunk = loadScript(fullPath, "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local Log = requireModule("lib/log.lua")

local function viewLog(msg)
  if Log and type(Log.emit) == "function" then
    Log.emit("rfsuite.widget", msg, "warn")
  end
end

-- How deep the stack may grow. A push beyond it is refused rather than dropping the bottom
-- entry: a view that silently disappeared from under the others would be a way back that no
-- longer leads anywhere.
M.STACK_LIMIT = 4

-- What an empty stack shows when there is no base layer.
M.DEFAULT_VIEW = "menu"

-- The views the widget ships, in the order their `openWhen` is asked. Only the first one whose
-- condition holds is opened on a pass, so the battery prompt comes ahead of the quick menu.
local CORE_VIEWS = {
  { id = "battery_pick", module = "widgets/dashboard/battery_pick_menu.lua", openWhen = "batteryPickPending" },
  { id = "menu", module = "widgets/dashboard/fullscreen_menu.lua" },
}

-- ---------------------------------------------------------------------------
-- Conditions
-- ---------------------------------------------------------------------------

-- The conditions a menu entry's `visibleWhen` and a view's `openWhen` may name. Both are asked
-- on the pass that draws or resolves, so a condition is a function of the widget rather than a
-- flag in a table prepared beforehand; a name that is not here is false, which hides an entry
-- and never opens a view -- what an unresolvable condition does in `app/menu_registry.lua` as
-- well.
--
-- Only the vocabulary an entry or a view actually uses is resolved. `enabledWhen`,
-- `lockedWhileArmed` and `confirm` are part of the same manifest vocabulary and nothing sets
-- one, so the first entry that needs one brings its resolver with it.
--
-- A condition that opens a view is cleared by whoever set it when the view is answered or
-- closed. A view whose condition is still true when it is closed opens again on the next pass.
local CONDITIONS = {}

-- In-flight tuning, only for a model that has it switched on and only while the preview
-- switch is on.
--
-- The snapshot alone would very nearly do -- the drive that publishes it is not built with
-- the preview off -- but the menu is built from the preferences of this pass and the
-- snapshot is what the last one left behind. Reading the switch here means the entry cannot
-- offer a route into a feature the runtime has already stopped driving.
--
-- The entry is offered with the interlock OPEN on purpose: the setup check and the parameter
-- grid are what a pilot wants to see on the ground, and the interlock is what decides whether
-- anything is sent. The screen the entry opens is inert until the switch is thrown.
function CONDITIONS.previewInflightTuning(widget)
  local previewOn = widget.preferences and widget.preferences.general
    and widget.preferences.general.preview_inflight_tuning == true
  return previewOn == true and type(widget.state.inflight) == "table"
end

-- The battery prompt, re-opened: only where the registry has a pack for this model, so a pilot
-- who keeps no registry never sees a button that opens an empty list, and only while the model
-- is disarmed, because a pack chosen in the air would be recorded against the flight in progress.
function CONDITIONS.batteryPickHasPacks(widget)
  if widget.state and widget.state.armed == true then return false end
  local pick = widget.state and widget.state.batteryPick or nil
  local candidates = (type(pick) == "table" and type(pick.candidates) == "table") and pick.candidates or nil
  return candidates ~= nil and #candidates > 0
end

-- The battery prompt is waiting for an answer. Raised by the runtime's registry load once per
-- connection; cleared by a pick, by closing the picker, by arming and by a reconnect.
function CONDITIONS.batteryPickPending(widget)
  local pick = widget.state and widget.state.batteryPick or nil
  return type(pick) == "table" and pick.pending == true
end

--- Whether the named condition holds for this widget. Unknown names, nil included, are false.
function M.condition(name, widget)
  local condition = CONDITIONS[name]
  if type(condition) ~= "function" then return false end
  return condition(widget) == true
end

-- ---------------------------------------------------------------------------
-- The registry
-- ---------------------------------------------------------------------------

--- This widget's views, in `openWhen` order.
--
-- A copy per widget, entry tables included: the runtime caches a view's loaded module on its
-- entry, and a later addition to one widget's list must not reach another's.
function M.registry(widget)
  local registry = widget._viewRegistry
  if registry == nil then
    registry = {}
    for i = 1, #CORE_VIEWS do
      local entry = {}
      for k, v in pairs(CORE_VIEWS[i]) do entry[k] = v end
      registry[i] = entry
    end
    widget._viewRegistry = registry
  end
  return registry
end

--- This widget's registry entry for `id`, or nil.
function M.find(widget, id)
  local registry = M.registry(widget)
  for i = 1, #registry do
    if registry[i].id == id then return registry[i] end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- The stack
-- ---------------------------------------------------------------------------

local function indexOf(stack, id)
  if stack == nil then return nil end
  for i = 1, #stack do
    if stack[i].id == id then return i end
  end
  return nil
end

--- The id of the view on top of the stack, or nil when the stack is empty.
function M.top(widget)
  local stack = widget._viewStack
  local entry = stack and stack[#stack] or nil
  return entry and entry.id or nil
end

-- Put `id` on top. A view already on the stack is returned to -- everything above it is
-- dropped -- rather than pushed a second time. An explicit open (`auto` not set) takes the
-- automatic mark off an entry its condition had pushed, so it no longer closes when the
-- condition falls.
--
-- Returns false when nothing changed because the stack is full. The refusal is logged once and
-- the latch sits on the stack table itself, so any change to the stack -- the one-assignment
-- clear included -- rearms it; the resolve pass runs on every interactive pass and must not log
-- on every one of them.
local function push(widget, id, auto)
  local stack = widget._viewStack
  local at = indexOf(stack, id)
  if at ~= nil then
    for i = #stack, at + 1, -1 do stack[i] = nil end
    if not auto then stack[at].auto = nil end
    stack.refused = nil
    return true
  end
  stack = stack or {}
  if #stack >= M.STACK_LIMIT then
    if not stack.refused then
      stack.refused = true
      viewLog("view '" .. tostring(id) .. "' not opened: the view stack is full")
    end
    return false
  end
  stack[#stack + 1] = { id = id, auto = auto and true or nil }
  stack.refused = nil
  widget._viewStack = stack
  return true
end

-- Take the top entry off; an empty stack becomes nil, so there is one way of being empty.
local function pop(widget)
  local stack = widget._viewStack
  if stack == nil then return end
  stack[#stack] = nil
  stack.refused = nil
  if #stack == 0 then widget._viewStack = nil end
end

--- The view fullscreen shows on this pass, and the render key for it.
--
-- 1. A view its own condition opened is closed again once that condition has fallen. That is
--    what keeps the battery prompt as it has always been: it shows while it is pending, and
--    three places end the pending state without closing anything -- the arm edge in
--    `updateDerivedFlightState`, a pick in `batteryPickApplyStep`, and the reconnect edge.
-- 2. The first view in registry order whose `openWhen` holds is opened, unless it is already on
--    the stack. No further view is considered on that pass.
-- 3. The top of the stack is the view. With the stack empty: the base layer, reported as nil,
--    or with no base layer the default view.
--
-- The key is the view id, followed by the view's own `renderKey(widget)` where it has one and
-- its module is already loaded. A module is never loaded here; that is the job pass's work.
function M.resolve(widget)
  local registry = M.registry(widget)

  local stack = widget._viewStack
  if stack ~= nil then
    local changed = false
    for i = #stack, 1, -1 do
      if stack[i].auto then
        local entry = M.find(widget, stack[i].id)
        if not (entry and M.condition(entry.openWhen, widget)) then
          table.remove(stack, i)
          changed = true
        end
      end
    end
    if changed then
      stack.refused = nil
      if #stack == 0 then widget._viewStack = nil end
    end
  end

  for i = 1, #registry do
    local entry = registry[i]
    if entry.openWhen ~= nil and M.condition(entry.openWhen, widget) then
      if indexOf(widget._viewStack, entry.id) == nil then push(widget, entry.id, true) end
      break
    end
  end

  local id = M.top(widget)
  if id == nil then
    if widget._viewBase ~= nil then return nil, nil end
    id = M.DEFAULT_VIEW
  end

  local entry = M.find(widget, id)
  local view = entry and entry.loaded or nil
  if view ~= nil and type(view.renderKey) == "function" then
    return id, id .. "|" .. tostring(view.renderKey(widget))
  end
  return id, id
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

-- An action is a string: `openView:<id>`, `closeView`, `done`, `exitFullscreen` or `none`.
local SIMPLE_ACTIONS = { closeView = true, done = true, exitFullscreen = true, none = true }

--- The one place an action is read: its verb, and the view id for `openView`.
--
-- nil and anything unrecognised are `none`, so a missing `after` leaves the view where it is.
-- A later form that is not a string is added here and nowhere else.
function M.parseAction(after)
  if type(after) ~= "string" then return "none", nil end
  if SIMPLE_ACTIONS[after] then return after, nil end
  local id = string.match(after, "^openView:(.+)$")
  if id ~= nil then return "openView", id end
  viewLog("unknown view action '" .. after .. "' ignored")
  return "none", nil
end

-- Whatever is built is dropped, so the next interactive pass builds the view now on top.
local function reset(widget)
  widget.built = false
  widget.renderKey = nil
end

local function exitFullscreen(widget)
  reset(widget)
  if lcd and type(lcd.exitFullScreen) == "function" then
    lcd.exitFullScreen()
  end
end

--- Perform the action that follows a press.
--
--   openView:<id>   open that view, or return to it where it is already on the stack
--   closeView       close the view on top; what is under it shows again
--   done            the interaction is finished: the stack is emptied, which leaves fullscreen
--                   where there is no base layer and shows the base layer where there is one
--   exitFullscreen  empty the stack and leave fullscreen, base layer or not
--   none            nothing at all; the press did whatever needed doing itself
--
-- An `openView` that is refused -- a view this widget does not have, or a full stack -- changes
-- nothing and forces no rebuild. A view that is not in the registry would otherwise be a job no
-- step can build, re-queued on every pass.
function M.navigate(widget, after)
  local verb, id = M.parseAction(after)
  if verb == "none" then return end
  if verb == "openView" then
    if M.find(widget, id) == nil then
      viewLog("view '" .. id .. "' not opened: this widget has no such view")
      return
    end
    if not push(widget, id, false) then return end
    reset(widget)
  elseif verb == "closeView" then
    pop(widget)
    reset(widget)
  elseif verb == "done" then
    widget._viewStack = nil
    if widget._viewBase == nil then
      exitFullscreen(widget)
    else
      reset(widget)
    end
  elseif verb == "exitFullscreen" then
    widget._viewStack = nil
    exitFullscreen(widget)
  end
end

--- The actions, bound to one widget, for code that holds no widget of its own to pass:
--- `ctx.action(after)` performs `after` exactly as `navigate(widget, after)` does.
function M.bind(widget)
  return {
    action = function(after) M.navigate(widget, after) end,
  }
end

return M
