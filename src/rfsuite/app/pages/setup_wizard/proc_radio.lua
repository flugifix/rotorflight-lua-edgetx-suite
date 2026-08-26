-- The radio section of the setup assistant, as PROCEDURES.
--
-- What it establishes is the chain: a switch on this radio reaches a channel, that channel reaches
-- the flight controller, and the flight controller acts on it. Each half exists in the suite
-- already -- the board is told that arming sits on an aux slot, and the radio is told which switch
-- drives which channel -- but nothing today makes the two agree, and a mode configured on a
-- channel no switch reaches looks perfectly configured on its own page.
--
-- The completion criterion of a channel procedure is therefore the END-TO-END, not the half: the
-- mix is present AND the flight controller carries the matching entry. Neither alone is done.
--
-- Every visible string goes through `t(i18n, key, fallback)` with a literal key and a literal
-- one-line fallback, and this file carries its own `pageT` call. That is not style: the build
-- resolves those three things into the locale's own text and leaves anything else as the English
-- fallback in every language.

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local Common = loadModule("app/pages/settings/common.lua")
local Controls = loadModule("ui/controls.lua")
local M_MSP = loadModule("app/pages/setup_wizard/msp.lua")
local t = Common and Common.pageT("setup_wizard") or function(_, _, fb) return fb end

local procs = {}

local SW_SWITCH = 1
local SW_NONE = 1 << 20
local MAX_SWITCH_POSITIONS = 96
local CHAIN_MOVE_US = 150

-- Adjustment functions, from the firmware's own enumeration. One slot each.
local ADJ_RATE_PROFILE = 1
local ADJ_PID_PROFILE = 2
local ADJ_SLOT_COUNT = 42

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, value = pcall(getTime)
    if ok and type(value) == "number" then return value / 100 end
  end
  return 0
end

local function sessionOf()
  local root = _G and _G.rfsuite
  return root and root.session or nil
end

-- The name the pilot recognises. While a link is up the suite may have renamed the model after the
-- craft, keeping the original in the board's own store -- so the presence of that stored name is
-- exactly the test for whether a rename is in effect, and it stays correct even when the restore
-- that should undo it never runs.
local function pilotModelName()
  local session = sessionOf()
  local prefs = session and session.modelPreferences
  local stored = prefs and prefs.model and prefs.model.previous_name
  if type(stored) == "string" and stored ~= "" then return stored end
  local model = _G and _G.model
  if type(model) == "table" and type(model.getInfo) == "function" then
    local ok, info = pcall(model.getInfo)
    if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
  end
  return "?"
end

local function channelName(i18n, key)
  if key == "arm" then return t(i18n, "channel_arm", "Arming") end
  if key == "throttle" then return t(i18n, "channel_throttle", "Throttle hold") end
  if key == "profile" then return t(i18n, "channel_profile", "Profile") end
  if key == "rescue" then return t(i18n, "channel_rescue", "Rescue") end
  if key == "aileron" then return t(i18n, "channel_aileron", "Roll") end
  if key == "elevator" then return t(i18n, "channel_elevator", "Pitch") end
  if key == "collective" then return t(i18n, "channel_collective", "Collective") end
  if key == "rudder" then return t(i18n, "channel_rudder", "Yaw") end
  return key
end

local function pickerName(i18n, key)
  if key == "arm" then return t(i18n, "pick_arm", "Arms at") end
  if key == "throttle" then return t(i18n, "pick_throttle", "Motor released at") end
  if key == "profile" then return t(i18n, "pick_profile", "Profile switch") end
  if key == "rescue" then return t(i18n, "pick_rescue", "Rescue at") end
  return key
end

local function tierName(i18n, tier)
  if tier == "required" then return t(i18n, "tier_required", "required") end
  if tier == "recommended" then return t(i18n, "tier_recommended", "recommended") end
  if tier == "unavailable" then return t(i18n, "tier_unavailable", "not yet") end
  return t(i18n, "tier_optional", "optional")
end

local function entryFor(w, channel)
  for _, entry in ipairs(w.radio.CHANNELS) do
    if entry.channel == channel then return entry end
  end
  return nil
end

local function wanted(w, entry)
  if entry.tier == "unavailable" then return false end
  local selection = w.data.wanted
  if type(selection) ~= "table" then return false end
  return selection[entry.channel] == true
end

-- The prelude, and it belongs to the RUN rather than to the opening screen.
--
-- It establishes the channel selection every later screen reads, and starts the four board reads
-- every completion criterion is derived from. The opening procedure used to own it, which held
-- only while the path was walked in order -- and the comment inside already named the failure it
-- would take: a structure that exists only when one particular procedure ran. The overview makes
-- that real, because a pilot opening one procedure straight from the list never passes the
-- opening at all. So the runner calls this once on load, and the opening screen refreshes it.
local function prime(w)
  local data = w.data
  -- The selection is established HERE and not in the layout procedure, because the layout
  -- procedure is one of the things the quick pass passes over once the board already satisfies
  -- it -- and every channel screen after it reads this table.
  if data.wanted == nil then
    data.wanted = {}
    for _, entry in ipairs(w.radio.CHANNELS) do
      data.wanted[entry.channel] = (entry.tier == "required" or entry.tier == "recommended")
    end
  end
  data.modeRanges = nil
  data.boxIds = nil
  data.boxNames = nil
  data.rxMap = nil
  w.msp.read("rx_map", function(parsed) data.rxMap = parsed w.rebuild() end)
  w.msp.read("boxids", function(parsed)
    data.boxIds = parsed and parsed.box_ids or nil w.rebuild()
  end)
  w.msp.read("boxnames", function(parsed)
    data.boxNames = parsed and parsed.box_names or nil w.rebuild()
  end)
  w.msp.read("mode_ranges", function(parsed)
    data.modeRanges = parsed and parsed.mode_ranges or nil w.rebuild()
  end)
end

procs.prime = prime

-- ---------------------------------------------------------------------------------------------
-- Opening. Not a procedure: it has no completion criterion of its own and nothing to skip, so it
-- is not counted in the section's progress either.
-- ---------------------------------------------------------------------------------------------

procs[#procs + 1] = {
  id = "opening",
  section = "radio",
  counted = false,
  title = function(i18n) return t(i18n, "step_intro", "About") end,
  enter = function(w) prime(w) end,
  screens = {
    {
      id = "about",
      nextLabel = function(i18n) return t(i18n, "begin", "Begin") end,
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y
        y = y + w.paragraph(children, area.x, y, area.w, t(i18n, "intro_p1", "This assistant sets the transmitter model up for the flight controller and configures the flight controller to match it.")) + 10
        y = y + w.paragraph(children, area.x, y, area.w, t(i18n, "intro_p2", "The transmitter setup is needed once per model and survives a change of flight controller. Every flight controller must be set to that layout once.")) + 10
        w.paragraph(children, area.x, y, area.w, t(i18n, "intro_p3", "This part covers the radio and the basics on the board. Drivetrain, servos and mechanics are separate procedures."))
      end
    },
    {
      id = "start",
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y
        local session = sessionOf()

        -- Naming the model IS the disclosure and the whole of the consent, because a write can
        -- only ever land in the model the pilot has open: Lua registers no way to select another.
        y = y + w.row(children, area.x, y, area.w,
          t(i18n, "field_model", "Model"), pilotModelName(), t(i18n, "marker_will_change", "changed"))

        y = y + w.row(children, area.x, y, area.w,
          t(i18n, "field_firmware", "Firmware"), tostring(session and session.fcVersion or "?"), nil)

        -- The derived walk is not free: it is every procedure's criterion against a board that
        -- answers at about six commands a second. So the screen is painted at once and this line
        -- fills itself in.
        local state
        if w.data.modeRanges == nil then
          state = t(i18n, "state_reading", "reading...")
        else
          local open, total = w.walk()
          state = tostring(open) .. "/" .. tostring(total) .. " " .. t(i18n, "state_open", "open")
        end
        y = y + w.row(children, area.x, y, area.w, t(i18n, "field_progress", "Procedures"), state, nil)

        local resume = w.store and w.store.resume() or nil
        if resume then
          w.paragraph(children, area.x, y + 6, area.w,
            t(i18n, "resume_note", "You left this assistant part way through. Next continues where the machine says the work stops."))
        end
      end,
      advance = function(w, done)
        -- Whether the pilot is resuming or starting fresh is not a question: the machine answers
        -- it. Continuing means going to the first procedure the board does not already satisfy,
        -- which on a first run is the first one.
        if w.store then w.store.setSeen() end
        done(true)
      end
    }
  }
}

-- ---------------------------------------------------------------------------------------------
-- 1 -- the channel layout. The target is DECLARED before anything is measured against it;
-- without this the check that follows is a conformance test against an assumption the pilot was
-- never asked about. Ticked means created.
-- ---------------------------------------------------------------------------------------------

procs[#procs + 1] = {
  id = "layout",
  section = "radio",
  title = function(i18n) return t(i18n, "step_layout", "Layout") end,
  skippable = true,
  isComplete = function(w)
    -- Realised rather than declared: every channel this layout asks for carries mixes. A layout
    -- that is only an intention is not something the board can confirm.
    for _, entry in ipairs(w.radio.CHANNELS) do
      if entry.tier == "required" or entry.tier == "recommended" then
        local count = w.radio.mixesCount(entry.channel)
        if count == nil then return nil end
        if count == 0 then return false end
      end
    end
    return true
  end,
  screens = {
    {
      id = "pick",
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y
        y = y + w.paragraph(children, area.x, y, area.w, t(i18n, "layout_intro", "The four sticks are laid out in the next step. Choose what else this run lays out.")) + 8

        for _, entry in ipairs(w.radio.CHANNELS) do
          local name = "CH" .. tostring(entry.channel) .. "  " .. channelName(i18n, entry.key)
          if entry.tier == "required" or entry.tier == "unavailable" then
            y = y + w.row(children, area.x, y, area.w, name, tierName(i18n, entry.tier), nil)
          else
            local channel = entry.channel
            y = y + Controls.appendRadioSwitch(children, area.x, y, area.w, name,
              function() return w.data.wanted[channel] == true end,
              function(value) w.data.wanted[channel] = value end)
          end
        end
      end
    }
  }
}

-- ---------------------------------------------------------------------------------------------
-- 2 -- the channel check. Two screens, because the two halves need different instruments and
-- would not fit on one: what is CONFIGURED is read, and only what cannot be read is measured.
-- ---------------------------------------------------------------------------------------------

procs[#procs + 1] = {
  id = "sticks",
  section = "radio",
  title = function(i18n) return t(i18n, "step_sticks", "Sticks") end,
  -- The one screen of this procedure that WRITES is the reason it has a criterion at all: a stick
  -- layout is a state of the model, so the machine can answer whether it is there. The chain
  -- screen beside it is a measurement and leaves no mark, which is why the procedure as a whole
  -- stays skippable.
  skippable = true,
  isComplete = function(w)
    local cache = w.radio.controlSources()
    for _, entry in ipairs(w.radio.STICK_INPUTS) do
      local info = w.radio.describeStick(entry, cache)
      if info == nil then return nil end
      if not info.ok then return false end
    end
    return true
  end,
  enter = function(w)
    -- Captured once, before anything is written: the first write rearranges the very
    -- inputs this mapping is read from.
    local cache = w.radio.controlSources()
    w.data.controls = cache
    local rows = {}
    for _, entry in ipairs(w.radio.STICK_INPUTS) do
      rows[#rows + 1] = w.radio.describeStick(entry, cache)
    end
    w.data.sticks = rows
    w.data.sticksError = nil

    local axes = {}
    for _, entry in ipairs(w.radio.STICK_INPUTS) do
      axes[entry.stick] = { seen = false, min = nil, max = nil }
    end
    w.data.chain = { axes = axes, pending = false, last = 0, replied = false }
  end,
  screens = {
    {
      id = "layout",
      nextLabel = function(i18n) return t(i18n, "sticks_write", "Set up") end,
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y

        y = y + w.paragraph(children, area.x, y, area.w, t(i18n, "sticks_intro", "The four sticks are laid out for the flight controller: roll, pitch, collective, yaw.")) + 8

        for _, info in ipairs(w.data.sticks or {}) do
          local entry = info.entry
          local value = tostring(info.sourceName or t(i18n, "finding_no_input", "no input"))
          local marker
          if info.ok then
            marker = t(i18n, "marker_ok", "ok")
          else
            -- What it will become, not what is wrong with it. The pilot is being shown a plan,
            -- and a plan reads forwards.
            marker = entry.channelName
          end
          y = y + w.row(children, area.x, y, area.w,
            "CH" .. tostring(entry.channel) .. "  " .. entry.channelName, value, marker)
        end

        if w.data.sticksError then
          w.paragraph(children, area.x, y + 6, area.w,
            t(i18n, "write_failed", "The write did not complete.") .. " " .. tostring(w.data.sticksError))
        end
      end,
      advance = function(w, done)
        -- Nothing to do is not a write. A model that already carries the layout is left alone
        -- rather than rebuilt, so a second run does not churn the pilot's inputs.
        local pending = {}
        for _, info in ipairs(w.data.sticks or {}) do
          if not info.ok then pending[#pending + 1] = info.entry end
        end
        if #pending == 0 then
          done(true)
          return
        end

        w.setBusy(t(w.i18n, "writing_title", "Writing"), t(w.i18n, "sticks_writing", "Laying out the sticks"))
        for _, entry in ipairs(pending) do
          local ok, err = w.radio.writeStick(entry, w.data.controls)
          if not ok then
            w.data.sticksError = err or "model"
            done(false)
            return
          end
        end

        local rows = {}
        for _, entry in ipairs(w.radio.STICK_INPUTS) do
          rows[#rows + 1] = w.radio.describeStick(entry, w.data.controls)
        end
        w.data.sticks = rows
        done(true)
      end
    },
    {
      id = "chain",
      wakeup = function(w)
        local chain = w.data.chain
        if not chain or chain.pending then return end
        local now = nowSeconds()
        if now - (chain.last or 0) < 0.2 then return end
        chain.last = now
        chain.pending = true
        w.msp.read("rc", function(parsed)
          chain.pending = false
          if type(parsed) ~= "table" then return end
          -- Repaint only where something CHANGED. A poll that rebuilds the page on every reply
          -- destroys and recreates the controls several times a second, and a press that straddles
          -- one of those rebuilds is lost.
          local changed = not chain.replied
          chain.replied = true
          for _, stick in ipairs(w.radio.STICKS) do
            local value = tonumber(parsed[stick.key])
            -- The board reports its channels by FUNCTION, and so does this table, so the two
            -- meet without a label in between.
            local axis = chain.axes[({ aileron = 3, elevator = 1, collective = 2, rudder = 0 })[stick.key]]
            if value ~= nil and axis then
              if axis.min == nil or value < axis.min then axis.min = value changed = true end
              if axis.max == nil or value > axis.max then axis.max = value changed = true end
              if not axis.seen and axis.min and axis.max and (axis.max - axis.min) >= CHAIN_MOVE_US then
                axis.seen = true
                changed = true
              end
            end
          end
          if changed then w.rebuild() end
        end)
      end,
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y
        local chain = w.data.chain or { axes = {} }

        for _, entry in ipairs(w.radio.STICK_INPUTS) do
          local axis = chain.axes[entry.stick] or {}
          local value = "-"
          if axis.min ~= nil and axis.max ~= nil then
            value = tostring(axis.min) .. " .. " .. tostring(axis.max)
          elseif not chain.replied then
            value = t(i18n, "state_reading", "reading...")
          end
          local marker = t(i18n, "marker_move", "move it")
          if axis.seen then marker = t(i18n, "marker_arrives", "arrives") end
          y = y + w.row(children, area.x, y, area.w,
            "CH" .. tostring(entry.channel) .. "  " .. entry.channelName, value, marker)
        end
      end
    }
  }
}

-- ---------------------------------------------------------------------------------------------
-- 3 to 6 -- one procedure per channel. Each shows its own FINDING with equally weighted actions,
-- collects a switch, and is complete only when both halves are on the machine.
--
-- The write itself is not here. Arming written while the throttle channel is still unassigned
-- leaves a channel at centre, which the flight controller reads as half throttle rather than as
-- off -- so the set is written once, by the procedure that follows these.
-- ---------------------------------------------------------------------------------------------

local function boxIdFor(w, name)
  local ids, names = w.data.boxIds, w.data.boxNames
  if type(ids) ~= "table" or type(names) ~= "table" then return nil end
  for i = 1, #names do
    if names[i] == name and ids[i] ~= nil then return tonumber(ids[i]) end
  end
  return nil
end

local function modeRangeFor(w, boxId, aux)
  local ranges = w.data.modeRanges
  if type(ranges) ~= "table" or boxId == nil then return nil end
  for index, range in ipairs(ranges) do
    if tonumber(range.id) == boxId and tonumber(range.auxChannelIndex) == aux then
      local from = range.range and tonumber(range.range.start)
      local to = range.range and tonumber(range.range["end"])
      if from ~= nil and to ~= nil and from < to then return index, range end
    end
  end
  return nil
end

local function freeModeSlot(w, boxId, aux)
  local ranges = w.data.modeRanges
  if type(ranges) ~= "table" then return nil end
  local index = modeRangeFor(w, boxId, aux)
  if index then return index end
  for i, range in ipairs(ranges) do
    if tonumber(range.id) == boxId then return i end
    local from = range.range and tonumber(range.range.start)
    local to = range.range and tonumber(range.range["end"])
    if from ~= nil and to ~= nil and from >= to then return i end
  end
  return nil
end

-- The throttle channel is complete when BOTH of its lines force the minimum, which is what makes
-- the state it leaves behind safe on its own. A single line, or a line that does not, is not.
local function throttleComplete(w, channel)
  local info = w.radio.describeChannel(channel)
  if info == nil then return nil end
  if info.count < 2 then return false end
  for _, mix in ipairs(info.lines) do
    if (tonumber(mix.weight) or 0) ~= 0 then return false end
    if (tonumber(mix.offset) or 0) > -100 then return false end
  end
  return true
end

local function makeChannelProcedure(channel, order)
  local proc = {
    id = "ch" .. tostring(channel),
    section = "radio",
    title = function(i18n)
      local entry = { key = ({ [5] = "arm", [6] = "throttle", [7] = "profile", [8] = "rescue" })[channel] }
      return "CH" .. tostring(channel) .. " " .. channelName(i18n, entry.key)
    end,
    skippable = true
  }

  proc.isComplete = function(w)
    local entry = entryFor(w, channel)
    if entry == nil then return nil end
    if not wanted(w, entry) then return true end

    local role = w.radio.firstRole(entry)
    local count = w.radio.mixesCount(channel)
    if count == nil then return nil end
    if count == 0 then return false end

    if role and role.kind == "throttle" then return throttleComplete(w, channel) end

    if role and role.kind == "condition" then
      if w.data.modeRanges == nil or w.data.boxNames == nil then return nil end
      local aux = w.msp.wireChannelToAux(channel, w.data.rxMap)
      if aux == nil then return false end
      local boxId = boxIdFor(w, role.box)
      if boxId == nil then return false end
      return modeRangeFor(w, boxId, aux) ~= nil
    end

    if role and role.kind == "adjustment" then
      -- Only the profile channel gets here, and its slots are read by its own screen because the
      -- table is 42 records long and reading it costs seconds.
      local found = w.data.adjustments
      if found == "unavailable" then return false end
      if type(found) ~= "table" then return nil end
      for _, fn in ipairs(role.functions) do
        if found[fn] == nil then return false end
      end
      return true
    end

    return nil
  end

  proc.enter = function(w)
    local data = w.data
    data.picked = data.picked or {}
    data.found = data.found or {}
    local info = w.radio.describeChannel(channel)
    data.found[channel] = info

    -- Where a mix is already there the switch is read out of it, but WHICH of its positions carries
    -- the function is not in the mix at all -- a mix maps every position. So the found switch is
    -- proposed and the position stays the pilot's answer.
    if data.picked[channel] == nil and info and info.state == "derived" and info.source then
      for swsrc = 1, MAX_SWITCH_POSITIONS do
        local source = w.radio.switchSource(swsrc)
        if source ~= nil and source == info.source then
          data.picked[channel] = w.radio.firstPositionOf(swsrc)
          break
        end
      end
    end

    local entry = entryFor(w, channel)
    local role = entry and w.radio.firstRole(entry) or nil
    if role and role.kind == "adjustment" and data.adjustments == nil then
      -- The single-slot accessor arrived with API 12.09. Below it the command does not
      -- exist, and asking anyway does not fail loudly -- it stalls the queue behind a
      -- request nothing will answer, which is what took a whole run's write down with it.
      if w.msp.hasPagedReads() ~= true then
        data.adjustments = "unavailable"
        return
      end
      data.adjustments = false
      local found = {}
      local slot = 1
      local function readNext()
        if slot > ADJ_SLOT_COUNT then
          w.data.adjustments = found
          w.rebuild()
          return
        end
        local index = slot
        slot = slot + 1
        w.msp.readIndexed("get_adjustment_range", { index - 1 }, function(parsed)
          local record = parsed and parsed.adjustment_range or nil
          if record and tonumber(record.adjFunction) ~= 0 then
            found[tonumber(record.adjFunction)] = { slot = index, record = record }
          elseif record then
            found.free = found.free or index
          end
          readNext()
        end)
      end
      readNext()
    end
  end

  proc.screens = {
    {
      id = "assign",
      canAdvance = function(w)
        local entry = entryFor(w, channel)
        if entry == nil or not wanted(w, entry) then return true end
        local picked = w.data.picked and w.data.picked[channel]
        if picked == nil or picked == 0 then return false end
        if entry.needsPositions and (w.radio.switchPositionCount(picked) or 0) < entry.needsPositions then
          return false
        end
        return true
      end,
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y
        local entry = entryFor(w, channel)
        if entry == nil then return end
        local info = w.data.found and w.data.found[channel] or nil

        -- The finding, with two actions of equal weight. "No mix" is not a defect on a board the
        -- pilot has just replaced under a transmitter they set up years ago, and a screen with one
        -- button has already decided that it is.
        local state = t(i18n, "finding_no_mix", "no mix")
        if info and info.state == "derived" then
          state = t(i18n, "finding_found", "mix found") .. " " .. tostring(info.sourceName or "")
        elseif info and info.state == "found" then
          state = t(i18n, "finding_complex", "mix found, not derived")
        end

        local isWanted = wanted(w, entry)
        y = y + w.findingRow(children, area.x, y, area.w,
          "CH" .. tostring(channel), state,
          {
            { text = t(i18n, "action_create", "Set up"),
              active = function() return not isWanted end,
              press = function() w.data.wanted[channel] = true w.rebuild() end },
            { text = t(i18n, "action_leave", "Leave alone"),
              active = function() return isWanted end,
              press = function() w.data.wanted[channel] = false w.rebuild() end }
          })

        if not isWanted then
          w.paragraph(children, area.x, y + 6, area.w,
            t(i18n, "leave_note", "This channel is left as it is. The flight controller is not told about it either."))
          return
        end

        -- One field either way, and it starts EMPTY -- there is no defensible default for a
        -- safety function, and a pre-filled form is how a pilot ends up with one they never chose.
        local pickerW = 150
        w.label(children, area.x, y + 9, area.w - pickerW - 8,
          pickerName(i18n, entry.key), SMLSIZE, COLOR_THEME_PRIMARY1)

        -- Two picker kinds for two channel kinds. Where the function sits AT a position -- arming,
        -- the throttle hold, rescue -- the radio's own picker is exactly right: which switch and
        -- which state collapse into the one answer the pilot already knows from their transmitter.
        --
        -- Where the channel carries a VALUE across the whole travel there is no position to name,
        -- because all three are in use, one per profile. Asked with the position picker the pilot
        -- had to pick one of three answers that all mean the same thing, and `proc.enter` then
        -- normalised two of them away with `firstPositionOf`. So that channel gets a list of
        -- SWITCHES, filtered to the ones that can carry it.
        if entry.needsPositions then
          local switches = w.radio.switches(entry.needsPositions)
          w.mark(y + w.ROW_H)

          if #switches == 0 then
            w.paragraph(children, area.x, y + w.ROW_H + 6, area.w,
              t(i18n, "no_switch_for_profiles",
                "This radio has no three-position switch, so it cannot carry one profile per position."))
            return
          end

          local values = { t(i18n, "pick_empty", "-") }
          for _, sw in ipairs(switches) do values[#values + 1] = sw.name end

          children[#children + 1] = {
            type = "choice",
            x = area.x + area.w - pickerW, y = y + 2, w = pickerW, h = w.ROW_H - 6,
            title = pickerName(i18n, entry.key),
            values = values,
            get = function()
              local picked = w.radio.firstPositionOf(w.data.picked[channel] or 0)
              for index, sw in ipairs(switches) do
                if sw.swsrc == picked then return index + 1 end
              end
              return 1
            end,
            set = function(value)
              local sw = switches[(tonumber(value) or 1) - 1]
              w.data.picked[channel] = sw and sw.swsrc or 0
            end
          }
          return
        end

        children[#children + 1] = {
          type = "switch",
          x = area.x + area.w - pickerW, y = y + 2, w = pickerW, h = w.ROW_H - 6,
          filter = SW_SWITCH | SW_NONE,
          get = function() return w.data.picked[channel] or 0 end,
          -- No repaint on a change. The button that gates this screen asks a FUNCTION whether it
          -- may be pressed, so it follows the field without the page being rebuilt -- and a rebuild
          -- would throw the focus back to the first row after every choice.
          set = function(value) w.data.picked[channel] = tonumber(value) or 0 end
        }
        w.mark(y + w.ROW_H)
      end
    }
  }

  return proc
end

for order, channel in ipairs({ 5, 6, 7, 8 }) do
  procs[#procs + 1] = makeChannelProcedure(channel, order)
end

-- ---------------------------------------------------------------------------------------------
-- 7 -- the write, and it is one act for the whole set. Everything before it read; this is where
-- that changes, so the screen is not "are you sure" but a list of what is about to happen, naming
-- both targets: the model on this radio, and this flight controller.
-- ---------------------------------------------------------------------------------------------

local function toS8Byte(value)
  value = math.floor((tonumber(value) or 0) + 0.5)
  if value < -128 then value = -128 end
  if value > 127 then value = 127 end
  if value < 0 then return value + 256 end
  return value
end

local function toS16Bytes(value)
  value = math.floor((tonumber(value) or 0) + 0.5)
  if value < 0 then value = value + 0x10000 end
  return value & 0xFF, (value >> 8) & 0xFF
end

local function stepOf(us)
  local step = (tonumber(us) or 1500) - 1500
  step = step / 5
  if step < -125 then step = -125 end
  if step > 125 then step = 125 end
  return step
end

local function plannedActions(w)
  local actions = {}
  for _, entry in ipairs(w.radio.CHANNELS) do
    if wanted(w, entry) then
      local swsrc = w.data.picked and w.data.picked[entry.channel]
      if swsrc ~= nil and swsrc ~= 0 then
        local role = w.radio.firstRole(entry)
        local action = {
          entry = entry,
          role = role,
          swsrc = swsrc,
          switchName = w.radio.switchPositionName(swsrc),
          aux = w.msp.wireChannelToAux(entry.channel, w.data.rxMap)
        }
        if role and role.kind == "condition" then
          action.boxId = boxIdFor(w, role.box)
          action.window = w.radio.windowFor(swsrc)
          if action.boxId and action.aux then
            action.slot = freeModeSlot(w, action.boxId, action.aux)
          end
        elseif role and role.kind == "adjustment" then
          action.travel = w.radio.travelRange(swsrc)
          action.slots = {}
          local found = w.data.adjustments
          if type(found) == "table" then
            local nextFree = found.free
            for _, fn in ipairs(role.functions) do
              local hit = found[fn]
              if hit then
                action.slots[fn] = hit.slot
              elseif nextFree then
                action.slots[fn] = nextFree
                nextFree = nextFree + 1
              end
            end
          end
        end
        actions[#actions + 1] = action
      end
    end
  end
  return actions
end

local function actionBlocked(action)
  local role = action.role
  if role == nil then return true end
  -- Both surfaces index the same array in the firmware, so both take the same bound, and
  -- neither write path enforces it. A field past the end is not refused and not clamped;
  -- it is stored and then read out of bounds on every evaluation.
  if role.kind ~= "throttle" and not M_MSP.auxFieldUsable(action.aux) then return true end
  if role.kind == "condition" then
    return action.boxId == nil or action.slot == nil
  end
  if role.kind == "adjustment" then
    if action.travel == nil then return true end
    for _, fn in ipairs(role.functions) do
      if action.slots == nil or action.slots[fn] == nil then return true end
    end
    return false
  end
  return false
end

procs[#procs + 1] = {
  id = "commit",
  section = "radio",
  title = function(i18n) return t(i18n, "step_write", "Write") end,
  isComplete = function(w)
    -- Derived from the channel procedures rather than from a flag: the set is written when every
    -- channel it covers is complete on both sides.
    local anyUnknown = false
    for _, proc in ipairs(w.procedures()) do
      if proc.section == "radio" and string.sub(tostring(proc.id), 1, 2) == "ch" then
        local value = w.isComplete(proc)
        if value == nil then anyUnknown = true end
        if value == false and not w.isSkipped(proc) then return false end
      end
    end
    if anyUnknown then return nil end
    return true
  end,
  enter = function(w)
    w.data.actions = plannedActions(w)
    w.data.writeError = nil
  end,
  screens = {
    {
      id = "plan",
      nextLabel = function(i18n) return t(i18n, "write_now", "Write") end,
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y

        for _, action in ipairs(w.data.actions or {}) do
          local target = tostring(action.switchName or "?")
          local role = action.role
          if role and role.kind == "throttle" then
            target = target .. "  " .. t(i18n, "note_motor_off", "motor off in every position")
          elseif role and role.kind == "condition" and action.window then
            target = target .. "  " .. tostring(role.box) .. " " ..
              tostring(action.window.start) .. "-" .. tostring(action.window["end"])
          elseif role and role.kind == "adjustment" then
            target = target .. "  " .. t(i18n, "note_profiles", "profiles 1-3")
          end
          local marker = t(i18n, "marker_ready", "ready")
          if actionBlocked(action) then marker = t(i18n, "marker_blocked", "blocked") end
          y = y + w.row(children, area.x, y, area.w,
            "CH" .. tostring(action.entry.channel), target, marker)
        end

        if w.data.writeError then
          w.paragraph(children, area.x, y + 6, area.w,
            t(i18n, "write_failed", "The write did not complete.") .. " " .. tostring(w.data.writeError))
        end
      end,
      advance = function(w, done)
        local actions = w.data.actions or {}
        w.data.writeError = nil

        -- Nothing writable means nothing to write. Committing anyway would send a lone
        -- persist for a change that was never made, and a failure of it would be reported
        -- as if the plan had failed.
        local writable = false
        for _, action in ipairs(actions) do
          if not actionBlocked(action) then writable = true break end
        end
        if not writable then
          done(true)
          return
        end

        w.setBusy(t(w.i18n, "writing_title", "Writing"), t(w.i18n, "writing_message", "Writing the model and the flight controller"))

        -- The radio half first, and as one act. Nothing is committed to the board until every
        -- mixer line of the set is in place.
        for _, action in ipairs(actions) do
          if not actionBlocked(action) then
            local ok, err
            if action.role.kind == "throttle" then
              ok, err = w.radio.writeThrottleChannel(action.entry.channel, action.swsrc)
            else
              ok, err = w.radio.writeConditionChannel(action.entry.channel, action.swsrc)
            end
            if not ok then
              w.data.writeError = err or "model"
              done(false)
              return
            end
          end
        end

        local queue = {}
        for _, action in ipairs(actions) do
          if not actionBlocked(action) then
            local role = action.role
            if role.kind == "condition" then
              local slot, boxId, aux, window = action.slot, action.boxId, action.aux, action.window
              queue[#queue + 1] = function(nextStep)
                w.msp.write(35, {
                  slot - 1, boxId, aux,
                  toS8Byte(stepOf(window.start)), toS8Byte(stepOf(window["end"])), 0, 0
                }, function(ok, err) nextStep(ok, err) end)
              end
            elseif role.kind == "adjustment" then
              for _, fn in ipairs(role.functions) do
                local slot, aux, travel = action.slots[fn], action.aux, action.travel
                queue[#queue + 1] = function(nextStep)
                  local minLo, minHi = toS16Bytes(role.min)
                  local maxLo, maxHi = toS16Bytes(role.max)
                  -- Always enabled, and the firmware has a sentinel for exactly that:
                  -- `enaChannel == 0xFF` means the enable window is not consulted at all.
                  -- That is how a profile selector ships on a craft that does not gate it
                  -- behind a switch. Reproducing it as a wide window on the same channel
                  -- would look equivalent and is not: it would still be evaluated.
                  w.msp.write(53, {
                    slot - 1, fn, 0xFF,
                    toS8Byte(-125), toS8Byte(125),
                    aux,
                    toS8Byte(stepOf(travel.start)), toS8Byte(stepOf(travel["end"])),
                    toS8Byte(0), toS8Byte(0),
                    minLo, minHi, maxLo, maxHi,
                    0
                  }, function(ok, err) nextStep(ok, err) end)
                end
              end
            end
          end
        end
        queue[#queue + 1] = function(nextStep) w.msp.commit(function(ok, err) nextStep(ok, err) end) end

        w.msp.sequence(queue, function(ok, err)
          if not ok then
            w.data.writeError = err or "msp"
            done(false)
            return
          end
          -- What was just written is now what the next derivation must see, so the board is asked
          -- again rather than the screen assuming.
          w.msp.read("mode_ranges", function(parsed)
            w.data.modeRanges = parsed and parsed.mode_ranges or w.data.modeRanges
            done(true)
          end)
        end)
      end
    },
    {
      id = "verify",
      wakeup = function(w)
        local verify = w.data.verify
        if verify == nil then
          verify = { pending = false, last = 0, replied = false }
          w.data.verify = verify
        end
        if verify.pending then return end
        local now = nowSeconds()
        if now - (verify.last or 0) < 0.2 then return end
        verify.last = now
        verify.pending = true
        w.msp.read("rc", function(parsed)
          verify.pending = false
          if type(parsed) ~= "table" then return end
          local changed = not verify.replied
          verify.replied = true
          local previous = verify.channels
          if type(previous) ~= "table" then
            changed = true
          else
            for i = 1, 18 do
              if previous[i] ~= (parsed.channels and parsed.channels[i]) then changed = true break end
            end
          end
          verify.channels = parsed.channels
          if changed then w.rebuild() end
        end)
      end,
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y
        local verify = w.data.verify or {}

        -- The read-back must not require ENTERING the state it verifies. What has to be proven is
        -- that the switch reaches the channel and the board sees it on the right aux slot, and
        -- that holds in every switch position -- so the value is watched wherever the switch is,
        -- and the position that would arm is computed rather than entered.
        for _, action in ipairs(w.data.actions or {}) do
          local value = "-"
          local marker = t(i18n, "marker_waiting", "waiting")
          if action.aux ~= nil and type(verify.channels) == "table" then
            local us = tonumber(verify.channels[5 + action.aux + 1])
            if us ~= nil then
              value = tostring(us)
              marker = t(i18n, "marker_arrives", "arrives")
              if action.window and us >= action.window.start and us <= action.window["end"] then
                marker = t(i18n, "marker_in_window", "in window")
              end
            end
          elseif action.role and action.role.kind == "throttle" then
            value = t(i18n, "note_motor_off", "motor off in every position")
            marker = t(i18n, "marker_written", "written")
          end
          y = y + w.row(children, area.x, y, area.w,
            "CH" .. tostring(action.entry.channel), value, marker)
        end
      end
    }
  }
}

return procs
