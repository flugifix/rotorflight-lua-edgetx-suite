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

-- The translator, with the fallback the menu has always carried: a widget that has no i18n
-- table of its own still draws the English text an entry names.
local function translator(widget)
  local i18n = widget.i18n
  if i18n and type(i18n.t) == "function" then return i18n.t end
  return function(k, f) return f or k end
end

-- The fullscreen views' shared vocabulary: the conditions a `visibleWhen` may name, and the
-- actions an `after` may name.
local Views = requireModule("widgets/dashboard/views.lua")

-- An entry without `visibleWhen` is always there. A named condition is resolved in views.lua,
-- where a name that is not known is false and hides its entry, which is what an unresolvable
-- condition does in `app/menu_registry.lua` as well.
local function isEntryVisible(entry, widget)
  local conditionKey = entry.visibleWhen
  if conditionKey == nil then return true end
  if not (Views and type(Views.condition) == "function") then return false end
  return Views.condition(conditionKey, widget) == true
end

-- A button's press: the row's own work, if it has any, and then the action that follows it.
local function pressFor(widget, work, after)
  return function()
    if type(work) == "function" then work() end
    if Views and type(Views.navigate) == "function" then Views.navigate(widget, after) end
  end
end

-- The menus the widget offers, each a list of entry ids in the order they are drawn. The quick
-- menu is the one there is; a theme draws it, or takes entries out of it by id, and adds none.
M.LISTS = {
  quick = { "erase_blackbox", "inflight_tuning", "battery_pick", "tool", "battery_profile" },
}

-- ---------------------------------------------------------------------------
-- Work that talks to the flight controller
-- ---------------------------------------------------------------------------

-- Queue a chain of messages, in order.
--
-- With a `report` -- only a theme's run hands one in; the menu's own presses never do, so what
-- they queue is exactly what they always queued -- the chain also says how it went: "busy" once
-- it is queued, "ok" when the LAST message has been answered, and "failed" when any message is
-- given up, whether out of retries, timed out or dropped by a clear of the queue. A message's own
-- reply and error handlers are kept and run first: they are wrapped, never replaced.
local function queueChain(queue, chain, report)
  local last = #chain
  if report ~= nil then
    for i = 1, last do
      local msg = chain[i]
      local ownError = msg.errorHandler
      msg.errorHandler = function(m, reason)
        if type(ownError) == "function" then ownError(m, reason) end
        report("failed")
      end
      if i == last then
        local ownReply = msg.processReply
        msg.processReply = function(m, buf)
          if type(ownReply) == "function" then ownReply(m, buf) end
          report("ok")
        end
      end
    end
  end
  for i = 1, last do queue:add(chain[i]) end
  if report ~= nil and last > 0 then report("busy") end
end

-- ---------------------------------------------------------------------------
-- The battery prompt's work
-- ---------------------------------------------------------------------------

-- A pick records a REQUEST on the widget and nothing else. The pick, the card write and the
-- flight controller write all happen in the runtime's job pass: an LVGL press callback runs
-- inside the firmware's event dispatch, where a card write or a queue turn is the one thing a
-- widget must not do.
local function requestPick(widget, id)
  -- `false` rather than nil for "no battery": nil is what the runtime reads as "no request at
  -- all", so the answer that clears the pack would never reach the job. Written out rather than
  -- as `(id == nil) and false or id`, which cannot produce `false` at all -- the `or` arm takes
  -- over the moment the `and` arm is false, and hands back the nil it was meant to replace.
  if id == nil then
    widget._batteryPickRequest = false
  else
    widget._batteryPickRequest = id
  end
end

-- Closing without a pick ends the prompt for this connection. `pending` is the condition that
-- opens the picker on its own, so it is cleared here, or the picker would open again at once.
local function dismissBatteryPick(widget)
  local pick = widget.state and widget.state.batteryPick or nil
  if type(pick) == "table" then
    pick.dismissed = true
    pick.pending = false
  end
end

-- The prompt's options: one per pack this model has, in registry order, and NO BATTERY last.
--
-- Every string an option carries is built here, once per call, so what draws them builds none.
-- `label` is the pack's name and `detail` the line under it; `pack` is the registry entry
-- itself, for a surface that wants to lay the same facts out differently. A pack's option
-- carries the pack's `id`, by which a run is matched to it. NO BATTERY is marked `none`, because
-- the picker reserves the foot row for it before the packs are laid out.
local function batteryPickOptions(widget, t)
  local pick = widget.state and widget.state.batteryPick or nil
  local candidates = (type(pick) == "table" and type(pick.candidates) == "table") and pick.candidates or {}
  local selectedId = type(pick) == "table" and pick.selectedId or nil

  local profileFmt = t("widgets.dashboard.battery_pick_profile", "Profile %d")
  local noProfile = t("widgets.dashboard.battery_pick_profile_none", "no profile")

  local options = {}
  for i = 1, #candidates do
    local pack = candidates[i]

    local nameText = pack.name
    if type(nameText) ~= "string" or nameText == "" then nameText = tostring(pack.id) end
    local capText = ""
    if type(pack.cap) == "number" and pack.cap > 0 then
      capText = string.format("%d mAh", math.floor(pack.cap))
    end
    local profileText = noProfile
    if type(pack.targetProfile) == "number" then
      profileText = string.format(profileFmt, pack.targetProfile + 1)
    end
    local detail = capText
    if detail ~= "" then
      detail = detail .. "  -  " .. profileText
    else
      detail = profileText
    end

    local id = pack.id
    options[i] = {
      id = id,
      label = nameText,
      detail = detail,
      current = (selectedId ~= nil and id == selectedId),
      pack = pack,
      press = function() requestPick(widget, id) end,
      after = "done"
    }
  end

  -- "No battery": the honest answer for a flight nobody wants in the log against a pack, and
  -- the one that clears a choice carried over from the previous connection.
  options[#options + 1] = {
    label = t("widgets.dashboard.battery_pick_none", "NO BATTERY"),
    none = true,
    press = function() requestPick(widget, nil) end,
    after = "done"
  }
  return options
end

-- The entries, one builder each, in the order the quick menu draws them. A caller that wants one
-- entry -- the battery picker wants its own record, and a theme one entry by its id -- builds that
-- one and not all of them, their translations and closures included.
local BUILD = {}

function BUILD.erase_blackbox(widget, t)
  return {
    id = "erase_blackbox",
    kind = "action",
    title = t("widgets.dashboard.erase_blackbox", "ERASE BLACKBOX"),
    press = function(report)
         local mspModule = requireModule("tasks/msp/runtime.lua")
         if mspModule and mspModule.getState then
            local mState = mspModule.getState()
            if mState and mState.queue then
               local eraseApi = requireModule("tasks/msp/api/dataflash_erase.lua")
               local summaryApi = requireModule("tasks/msp/api/dataflash_summary.lua")

               if eraseApi and summaryApi then
                 queueChain(mState.queue, {
                   {
                     command = eraseApi.writeCommand,
                     payload = eraseApi.buildWritePayload({}),
                     simulatorResponse = {},
                     isWrite = true,
                     timeout = 10.0,
                   },
                   {
                     command = summaryApi.command,
                     simulatorResponse = summaryApi.simulatorResponse,
                     processReply = function(_, buf)
                       local stats = summaryApi.parse(buf)
                       if stats then
                         if type(_G) == "table" and _G.rfsuite and _G.rfsuite.session then
                           _G.rfsuite.session.dataflash = stats
                         end
                       end
                     end
                   }
                 }, report)
               end
            end
         end
    end,
    -- How full the blackbox is, as the flight controller last reported it: the summary read on
    -- connecting, and again after every erase.
    info = function()
      local session = type(_G) == "table" and _G.rfsuite and _G.rfsuite.session or nil
      local stats = session and session.dataflash or nil
      if type(stats) ~= "table" then return nil end
      return { used = stats.used, total = stats.total }
    end,
    after = "done"
  }
end

-- The tuning surface is not a view on the stack: it takes fullscreen ahead of every view while
-- its own flag is up, so the press raises the flag and nothing follows it.
function BUILD.inflight_tuning(widget, t)
  return {
    id = "inflight_tuning",
    kind = "action",
    title = t("widgets.dashboard.inflight_open", "IN-FLIGHT TUNING"),
    visibleWhen = "previewInflightTuning",
    press = function()
        widget.inflightFullscreen = true
        widget.built = false
        widget.renderKey = nil
    end,
    after = "none"
  }
end

-- The battery prompt, as one record. Its options are the picks -- one per pack, then NO
-- BATTERY -- and `close` ends the prompt for this connection without a pick; the picker view
-- (battery_pick_menu.lua) draws this record, so what a pick does is written down once, here.
--
-- In this menu the record is the BATTERY row: a `choice` that names a `view` is drawn as the
-- single button that opens that view, which is its own `after`. The prompt comes up on its own
-- once per connection; this is the way back to it after it has been answered or closed. It
-- stays full screen, the picker taking the menu's place.
--
-- `options` needs no argument: the widget is the one this list was made for, so a caller that
-- holds only the record can still ask for the options as they stand now.
function BUILD.battery_pick(widget, t)
  return {
    id = "battery_pick",
    kind = "choice",
    view = "battery_pick",
    title = t("widgets.dashboard.battery_pick_open", "BATTERY"),
    visibleWhen = "batteryPickHasPacks",
    after = "openView:battery_pick",
    options = function() return batteryPickOptions(widget, t) end,
    close = {
      press = function() dismissBatteryPick(widget) end,
      after = "done"
    }
  }
end

-- The suite's tool, run inside the widget until it is closed (widgets/dashboard/tool_host.lua).
-- The whole effect is the action, so the row has no press of its own.
function BUILD.tool(widget, t)
  return {
    id = "tool",
    kind = "action",
    title = t("widgets.dashboard.tool_open", "RFSUITE TOOL"),
    visibleWhen = "modelDisarmed",
    after = "openTool"
  }
end

function BUILD.battery_profile(widget, t)
  return {
    id = "battery_profile",
    kind = "choice",
    title = t("widgets.dashboard.battery_profile", "BATTERY PROFILE"),
    -- One option per capacity the flight controller carries, resolved when the row is drawn
    -- rather than when the list is made, so an entry stays a description of what it offers. The
    -- widget is the one this list was made for where the caller passes none.
    options = function(w)
      w = w or widget
      local options = {}
      local state = w and w.state or {}
      local config = state.battery_config
      if config then
        for i=0,5 do
          local cap = config["batteryCapacity_"..i] or 0
          if cap > 0 then
            options[#options+1] = {
              -- The profile the pilot reads, 1 to 6, by which a run is matched to this option.
              id = i + 1,
              label = tostring(cap).." mAh",
              -- Highlight active battery profile
              -- FIX: Telemetry sensor BatP is 1-based (1 to 6)
              current = (state.batteryProfile == (i + 1)),
              press = function(report)
                local mspModule = requireModule("tasks/msp/runtime.lua")
                if mspModule and mspModule.getState then
                  local mState = mspModule.getState()
                  if mState and mState.queue then
                     local chain = {}
                     -- 1. Set Battery Profile
                     local api = requireModule("tasks/msp/api/battery_profile.lua")
                     if api and type(api.buildWritePayload) == "function" then
                       chain[#chain+1] = {
                          command = api.writeCommand,
                          payload = api.buildWritePayload({ batteryProfile = i }),
                          simulatorResponse = {}
                       }
                       -- The battery prompt keeps the profile the board reported on connecting
                       -- and skips a pick that matches it. After this write that report is
                       -- stale, so it is dropped and the next pick writes.
                       local batteryPick = w.state and w.state.batteryPick or nil
                       if type(batteryPick) == "table" then batteryPick.boardProfile = nil end
                     end
                     -- 2. Save to EEPROM so the FC applies and broadcasts the change
                     local eepromApi = requireModule("tasks/msp/api/eeprom_write.lua")
                     if eepromApi and type(eepromApi.buildWritePayload) == "function" then
                       chain[#chain+1] = {
                          command = eepromApi.writeCommand,
                          payload = eepromApi.buildWritePayload({}),
                          simulatorResponse = {},
                          isWrite = true,
                       }
                     end
                     queueChain(mState.queue, chain, report)
                  end
                end
              end,
              -- Close after selection
              after = "done"
            }
          end
        end
      end
      return options
    end
  }
end

--- What the menu offers, as a list rather than as drawing code.
--
-- One entry per row, in the order they are drawn, carrying the manifest's own vocabulary:
-- `id`, `title`, `kind`, `visibleWhen` and `press`. `kind` is what the builder makes of the
-- row -- `action` is a single button, `choice` is a title over a grid of options -- so the
-- battery-profile grid is a row of this list rather than a special case inside the builder. A
-- `choice` whose options belong to a view of their own names it in `view`, and the menu draws it
-- as the single button that opens that view.
--
-- `press` does the row's work and nothing else. What follows it -- leaving fullscreen, opening
-- another view, or nothing -- is the row's `after`, an action views.lua performs; an option of a
-- `choice` carries its own.
--
-- The title is resolved here, and it is resolved from a complete literal key: the translation
-- precompiler rewrites what it can read, and a key assembled from parts ships the English
-- fallback in every language with nothing saying so.
function M.entries(widget)
  local t = translator(widget)
  local list = {}
  local ids = M.LISTS.quick
  for i = 1, #ids do list[i] = BUILD[ids[i]](widget, t) end
  return list
end

--- The entry `id` of this widget's list, or nil. Only that entry is built.
function M.entry(widget, id)
  local build = BUILD[id]
  if build == nil then return nil end
  return build(widget, translator(widget))
end

--- The entries of the named list in `M.LISTS`, in its order; an empty list for an unknown name.
function M.list(widget, name)
  local ids = M.LISTS[name]
  local out = {}
  if type(ids) ~= "table" then return out end
  local byId = {}
  local all = M.entries(widget)
  for i = 1, #all do byId[all[i].id] = all[i] end
  for i = 1, #ids do
    if byId[ids[i]] ~= nil then out[#out+1] = byId[ids[i]] end
  end
  return out
end

--- The menu's own record, and its own option, for what a caller hands in; nil for either where
--- the menu has none.
--
-- A caller's tables are never run: they only name what is meant. The entry is found by its `id`;
-- an option by its `id` among the record's options as they stand now -- a pack's id, a battery
-- profile's number -- or, for NO BATTERY, by `none`, and the record's `close` by being the
-- `close` of the table handed in. Matching by identity would not do: a record's options are made
-- anew on every call, so the table a caller drew is never one of them by the time it is run.
function M.resolve(widget, entry, option)
  if type(entry) ~= "table" then return nil end
  local core = M.entry(widget, entry.id)
  if core == nil then return nil end
  if option == nil then return core, nil end
  if type(option) ~= "table" then return nil end
  if core.close ~= nil and option == entry.close then return core, core.close end
  local options = core.options
  if type(options) == "function" then options = options(widget) end
  if type(options) ~= "table" then return nil end
  for i = 1, #options do
    local candidate = options[i]
    if option.none == true then
      if candidate.none == true then return core, candidate end
    elseif candidate.id ~= nil and candidate.id == option.id then
      return core, candidate
    end
  end
  return nil
end

--- The menu's own records for a list a caller hands in, in its order: each item replaced by the
--- record of its `id`, and an item whose id the menu does not have left out.
function M.coreList(widget, list)
  local out = {}
  if type(list) ~= "table" then return out end
  local byId = {}
  local all = M.entries(widget)
  for i = 1, #all do byId[all[i].id] = all[i] end
  for i = 1, #list do
    local item = list[i]
    local core = type(item) == "table" and byId[item.id] or nil
    if core ~= nil then out[#out+1] = core end
  end
  return out
end

--- Whether the entry is offered now: the test the menu makes for each of its rows.
function M.visible(widget, entry)
  return isEntryVisible(entry, widget)
end

--- Run an entry, or one of its options: the work, then the action that follows it. This is the
--- one place both happen, for the menu's own buttons, the picker's and a theme's alike.
--
-- The work is the option's when an option is given and the entry's otherwise; so is the action,
-- unless `after` names another one. `report` is handed to the work, which tells it how the
-- messages it queued fared (see queueChain); the menu's own buttons pass none.
function M.run(widget, entry, option, after, report)
  local source = option or entry
  if type(source.press) == "function" then source.press(report) end
  if after == nil then after = source.after end
  if Views and type(Views.navigate) == "function" then Views.navigate(widget, after) end
end

--- Draw the menu.
--
-- `entries` is the list to draw; omitted, the menu draws its own, which is what the runtime
-- asks for. Taking the list as an argument is the point of the split: the same drawing code
-- can serve a list assembled somewhere else.
function M.build(children, widget, entries)
  entries = entries or M.entries(widget)
  local dW = widget.zone.w
  local dH = widget.zone.h
  local dX = 0
  local dY = 0
  
  local t = translator(widget)

  local bg_color = COLOR_THEME_PRIMARY3 or BLACK
  if bg_color == BLACK and lcd and type(lcd.RGB) == "function" then
     bg_color = lcd.RGB(40, 40, 40)
  end
  local accent_color = COLOR_THEME_SECONDARY1 or WHITE
  local btn_color = COLOR_THEME_PRIMARY1 or DARKGREY
  
  -- 1. Full Background
  children[#children+1] = {
    type = "rectangle", x=dX, y=dY, w=dW, h=dH, color=bg_color, filled=true
  }

  -- Layout Profile Definition
  -- TX16S MK3 is 800x480 (dH ~480)
  -- Standard TX16S is 480x272 (dH ~272)
  local isLarge = dH > 350
  
  local headerH, titleFont, fontH, closeSize, contentGap, titleGap, btnH, gapY, paddingX
  local headTextOffY, closeTextOffY, btnTextOffY

  if isLarge then
    -- Layout for TX16S MK3 (Large High-Res)
    headerH = 60
    titleFont = MIDSIZE
    fontH = 24
    closeSize = 44
    contentGap = 20
    titleGap = fontH + 30
    btnH = 50
    gapY = 10
    paddingX = 15
    headTextOffY = -6
    closeTextOffY = -8
    btnTextOffY = -8
  else
    -- Layout for standard TX16S (480x272)
    headerH = 22
    titleFont = SMLSIZE
    fontH = 12
    closeSize = 20
    contentGap = 5
    titleGap = fontH + 10
    btnH = 28
    gapY = 8
    paddingX = 5
    headTextOffY = -2
    closeTextOffY = -4
    btnTextOffY = -4
  end

  -- 2. Header
  children[#children+1] = {
    type = "rectangle", x=dX, y=dY, w=dW, h=headerH, color=btn_color, filled=true
  }
  
  children[#children+1] = {
    type = "label", x=dX + paddingX, y=dY + math.floor((headerH - fontH)/2) + headTextOffY, w=dW-60, 
    text=t("widgets.dashboard.quick_settings", "QUICK SETTINGS"), color=WHITE, align=LEFT, font=titleFont
  }
  
  -- 3. Close Button (X)
  local cx = dX + dW - closeSize - (isLarge and 8 or 1)
  local cy = dY + math.floor((headerH - closeSize)/2)
  
  children[#children+1] = {
    type = "button", x=cx, y=cy, w=closeSize, h=closeSize, color=COLOR_THEME_SECONDARY1 or RED,
    press = pressFor(widget, nil, "done")
  }
  
  children[#children+1] = {
    type = "label", x=cx, y=cy + math.floor((closeSize - fontH)/2) + closeTextOffY, w=closeSize, text="X", color=WHITE, align=CENTER, font=titleFont
  }
  
  -- 4. Content Area
  local contentY = dY + headerH + contentGap
  local entryW = math.floor(dW - paddingX * 2)

  for _, entry in ipairs(entries) do
    if isEntryVisible(entry, widget) then
      if entry.kind == "choice" and entry.view == nil then
        -- 4b. A title over a grid of options.
        contentY = contentY + titleGap - gapY

        children[#children+1] = {
          type = "label", x=dX + paddingX, y=contentY, w=dW-(paddingX*2),
          text=entry.title, color=WHITE, align=LEFT, font=titleFont
        }

        local listY = contentY + titleGap

        local options = entry.options
        if type(options) == "function" then options = options(widget) end
        options = options or {}

        -- Every action row above the grid pushes it down, and an option whose button would
        -- cross the bottom edge is not drawn. Three columns on a wide zone keep six options to
        -- two rows, so they still fit below a longer list of actions.
        local cols = 2
        if dW < 200 then cols = 1 end
        if #options > 4 and dW >= 400 then cols = 3 end
        local btnW = math.floor((dW - paddingX*(cols+1)) / cols)

        for i, option in ipairs(options) do
           local row = math.floor((i-1)/cols)
           local col = (i-1)%cols
           local bx = dX + paddingX + col*(btnW+paddingX)
           local by = listY + row*(btnH+gapY)

           if by + btnH > dY + dH then break end

           local isCurrent = option.current == true
           local bColor = isCurrent and accent_color or btn_color
           local tColor = isCurrent and BLACK or WHITE

           -- Button (Interactive layer)
           children[#children+1] = {
             type = "button", x=bx, y=by, w=btnW, h=btnH, color=bColor,
             press = function() M.run(widget, entry, option) end
           }

           -- Label (visual only)
           local textY = by + math.floor((btnH - fontH)/2) + btnTextOffY
           children[#children+1] = {
             type = "label", x=bx, y=textY, w=btnW, text=option.label, color=tColor, align=CENTER, font=titleFont
           }
        end

        -- The next row starts below the whole grid, the way an action row leaves room for itself.
        contentY = listY + math.ceil(#options / cols) * (btnH + gapY)
      else
        -- 4a. A single button: an action, or the way into the view a choice is drawn in.
        children[#children+1] = {
          type = "button", x=dX + paddingX, y=contentY, w=entryW, h=btnH, color=btn_color,
          press = function() M.run(widget, entry) end
        }
        children[#children+1] = {
          type = "label", x=dX + paddingX, y=contentY + math.floor((btnH - fontH)/2) + btnTextOffY, w=entryW,
          text=entry.title, color=WHITE, align=CENTER, font=titleFont
        }
        contentY = contentY + btnH + gapY
      end
    end
  end
end

return M
