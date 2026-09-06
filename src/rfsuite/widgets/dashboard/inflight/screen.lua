-- The two renderings of the in-flight tuning overlay: the widget zone, and fullscreen.
--
-- Both append node tables to `children`, the idiom widgets/dashboard/fullscreen_menu.lua uses, so
-- the runtime builds them exactly the way it builds the quick settings menu.
--
-- The zone screen carries NO buttons. Whether an LVGL button in a non-fullscreen widget zone ever
-- receives a press is not something this file knows, and a control that may or may not answer is
-- worse on a tuning screen than no control at all: there the pilot's trims are the input and the
-- screen is the read-out.
--
-- Only two things here are reactive closures -- the active value and the active row's colour --
-- and both read the precomputed snapshot on `widget.state.inflight` and nothing else. Everything
-- else is laid down at build time and replaced when the render key moves. That is the rule from
-- GEMINI.md: a closure handed to lvgl.build runs per frame, on whatever instruction budget
-- refresh() left over, outside the widget's own pcall.

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

local Functions = requireModule("widgets/dashboard/inflight/functions.lua")
local Drive = requireModule("widgets/dashboard/inflight/drive.lua")

-- The ground half, loaded only when the ground surface is actually built. It pulls in the MSP
-- runtime and the api modules behind it, and the zone screen -- the one that is built while the
-- pilot is flying -- has no use for any of that.
local PrimeModule = nil
local function prime()
  if PrimeModule == nil then
    PrimeModule = requireModule("widgets/dashboard/inflight/prime.lua") or false
  end
  if PrimeModule == false then return nil end
  return PrimeModule
end

-- How often the setup check is allowed to walk the model again, in getTime ticks. It reads mixer
-- lines and global variable details, which is far too much to pay on a rebuild that happens
-- whenever a value moves.
local CHECK_INTERVAL_TICKS = 200

local UNKNOWN_VALUE = "--"

local function translator(widget)
  return (widget.i18n and type(widget.i18n.t) == "function") and widget.i18n.t
    or function(key, fallback) return fallback or key end
end

local function palette()
  local bg = COLOR_THEME_PRIMARY3 or BLACK
  if bg == BLACK and lcd and type(lcd.RGB) == "function" then
    bg = lcd.RGB(40, 40, 40)
  end
  return bg, COLOR_THEME_SECONDARY1 or WHITE, COLOR_THEME_PRIMARY1 or BLACK
end

-- One layout profile per screen size, the shape widgets/dashboard/fullscreen_menu.lua uses.
-- The tall radios get the generous numbers; everything else gets the compact set, which is what
-- has to survive the shortest screen the suite runs on.
local function metrics(w, h, fullscreen)
  local m = {}
  m.large = h > 350
  if m.large then
    m.pad = 14
    m.headerH = 46
    m.chipH = 40
    m.activeH = 74
    m.hintH = 24
    m.font = MIDSIZE
    m.smallFont = SMLSIZE
    m.bigFont = XXLSIZE
    m.lineH = 26
  else
    m.pad = 5
    m.headerH = 22
    m.chipH = 22
    m.activeH = 46
    m.hintH = 14
    m.font = SMLSIZE
    m.smallFont = SMLSIZE
    m.bigFont = DBLSIZE
    m.lineH = 14
  end
  m.actionH = fullscreen and (m.large and 56 or 34) or 0
  m.checkH = fullscreen and m.hintH or 0
  m.chipW = math.floor((w - m.pad * 2 - 5 * 4) / 6)
  local used = m.headerH + m.chipH + m.activeH + m.actionH + m.checkH + m.hintH + m.pad * 3
  m.rowsH = h - used
  if m.rowsH < 0 then m.rowsH = 0 end
  m.rowH = math.floor(m.rowsH / Functions.ROW_COUNT)
  return m
end

local function appendLabel(children, x, y, w, text, color, font, align)
  children[#children + 1] = {
    type = "label", x = x, y = y, w = w, text = text, color = color, align = align, font = font
  }
end

local function formatValue(value)
  if value == nil then return UNKNOWN_VALUE end
  return tostring(math.floor(value + 0.5))
end

-- ---------------------------------------------------------------------------
-- The setup check, as one line
-- ---------------------------------------------------------------------------

--- The verdict, cached on the drive: the walk over mixer lines and variable details is far too
-- expensive to repeat on every rebuild, and nothing it reads changes without the pilot opening
-- the radio's own menus.
function M.checkVerdict(widget)
  local drive = widget and widget._inflight
  if drive == nil then return nil end
  local now = drive.radio.now()
  if drive._checkAt == nil or (now - drive._checkAt) >= CHECK_INTERVAL_TICKS then
    drive._checkAt = now
    drive._checkResult = Drive.check(drive)
  end
  return drive._checkResult
end

--- The verdict in one sentence. Faults are grouped by what the pilot has to go and fix rather
-- than listed one by one: the model has one mixer page, one global variable page and one trim
-- setting, and naming those three is what makes the message actionable on a flight line.
function M.describeCheck(result, t)
  if result == nil then
    return t("widgets.dashboard.inflight_check_unchecked", "Setup not checked")
  end
  if result == "ok" then
    return t("widgets.dashboard.inflight_check_ok", "Setup OK")
  end
  if type(result) ~= "table" then return "" end

  local unset, mix, gvar, trim, claim = false, false, false, false, false
  for i = 1, #result do
    local code = result[i]
    if string.find(code, "mix", 1, true) then
      mix = true
    elseif string.find(code, "gvar_", 1, true) then
      gvar = true
    elseif string.find(code, "trim_mode", 1, true) then
      trim = true
    elseif code == "no_nav_trim" or code == "trim_claimed_twice" then
      claim = true
    else
      unset = true
    end
  end

  local parts = {}
  if unset then parts[#parts + 1] = t("widgets.dashboard.inflight_check_unset", "Switch or variables not set") end
  if mix then parts[#parts + 1] = t("widgets.dashboard.inflight_check_mix", "Mixer line missing or wrong") end
  if gvar then parts[#parts + 1] = t("widgets.dashboard.inflight_check_gvar", "Variable range or precision") end
  if trim then parts[#parts + 1] = t("widgets.dashboard.inflight_check_trim", "Trim still active here") end
  if claim then parts[#parts + 1] = t("widgets.dashboard.inflight_check_claim", "Walk and adjust need two trims") end
  return table.concat(parts, " / ")
end

-- ---------------------------------------------------------------------------
-- The pieces both screens share
-- ---------------------------------------------------------------------------

local function appendHeader(children, widget, m, w, t, accent, btn)
  local snapshot = widget.state.inflight or {}
  children[#children + 1] = {
    type = "rectangle", x = 0, y = 0, w = w, h = m.headerH, color = btn, filled = true
  }
  local textY = math.floor((m.headerH - m.lineH) / 2)
  appendLabel(children, m.pad, textY, math.floor(w / 2),
    t("widgets.dashboard.inflight_title", "IN-FLIGHT TUNING"), WHITE, m.font, LEFT)

  local right = {}
  if snapshot.profile ~= nil then
    right[#right + 1] = t("widgets.dashboard.inflight_profile", "PROFILE") .. " " .. formatValue(snapshot.profile)
  end
  if snapshot.live == true then
    right[#right + 1] = t("widgets.dashboard.inflight_live", "LIVE")
  else
    right[#right + 1] = t("widgets.dashboard.inflight_ground", "GROUND")
  end
  appendLabel(children, math.floor(w / 2), textY, math.floor(w / 2) - m.pad,
    table.concat(right, "  "), snapshot.live == true and accent or WHITE, m.font, RIGHT)
end

--- The six bank chips. `press` is nil on the zone screen, which is what makes them read-outs
-- there and controls in fullscreen.
local function appendChips(children, widget, m, y, t, accent, btn, interactive)
  local snapshot = widget.state.inflight or {}
  local drive = widget._inflight
  for bank = 1, Functions.BANK_COUNT do
    local x = m.pad + (bank - 1) * (m.chipW + 4)
    local isActive = (snapshot.bank == bank)
    local node = {
      type = interactive and "button" or "rectangle",
      x = x, y = y, w = m.chipW, h = m.chipH,
      color = isActive and accent or btn
    }
    -- `filled` belongs to the BORDERED objects -- rectangle, circle, arc
    -- (lua_lvgl_widget.cpp, LvglWidgetBorderedObject::parseParam). A button is built from
    -- LvglWidgetObject and rejects it with `Invalid property 'filled'`, which is raised out of
    -- the build and swallowed by the entry point's pcall: measured on a radio, the live surface
    -- drew its header and nothing below it, and the trace said nothing at all.
    if not interactive then node.filled = true end
    if interactive and drive then
      node.press = function()
        drive:setBank(bank)
        widget.built = false
        widget.renderKey = nil
      end
    end
    children[#children + 1] = node
    appendLabel(children, x, y + math.floor((m.chipH - m.lineH) / 2), m.chipW,
      tostring(bank), isActive and BLACK or WHITE, m.font, CENTER)
  end
  -- Said in words rather than left to the chips: a bank the enable channel is not resting in is
  -- one the flight controller is not listening on, whatever the screen highlights.
  if snapshot.bankShown == nil then
    appendLabel(children, m.pad, y + m.chipH, m.chipW * 6,
      t("widgets.dashboard.inflight_bank_unknown", "Enable channel between banks"), COLOR_THEME_WARNING, m.smallFont, LEFT)
  end
end

--- The parameter the pilot is on, large, with its value.
--
-- The value is the one reactive closure on this screen. It reads the published snapshot and
-- formats one string per change, which is exactly what the reactive-closure rule allows.
local function appendActive(children, widget, m, y, w, t, accent)
  local snapshot = widget.state.inflight or {}
  local name = snapshot.activeName or t("widgets.dashboard.inflight_unassigned", "Unassigned")
  appendLabel(children, m.pad, y, math.floor(w * 0.6) - m.pad, name, WHITE, m.font, LEFT)

  local state = widget.state
  children[#children + 1] = {
    type = "label",
    x = math.floor(w * 0.6), y = y, w = math.floor(w * 0.4) - m.pad,
    color = accent, align = RIGHT, font = m.bigFont,
    text = function()
      local snap = state.inflight
      if type(snap) ~= "table" then return UNKNOWN_VALUE end
      local value = snap.activeValue
      if value == nil then return UNKNOWN_VALUE end
      return tostring(math.floor(value + 0.5))
    end
  }

  local caption = t("widgets.dashboard.inflight_row", "ROW") .. " " .. tostring(snapshot.row)
    .. "  " .. t("widgets.dashboard.inflight_bank", "BANK") .. " " .. tostring(snapshot.bank)
  appendLabel(children, m.pad, y + m.lineH + 2, w - m.pad * 2, caption, WHITE, m.smallFont, LEFT)
end

--- The six rows of the armed bank.
--
-- A row whose trim this radio does not have is hidden on the ZONE screen, where the trim is the
-- only way to reach it; in fullscreen every row is shown, because a tap reaches it there.
local function appendRows(children, widget, m, y, w, t, accent, btn, interactive)
  local snapshot = widget.state.inflight or {}
  local drive = widget._inflight
  local rows = snapshot.rows or {}
  local state = widget.state

  for row = 1, Functions.ROW_COUNT do
    local entry = rows[row] or {}
    local visible = interactive or entry.trim == true
    if visible and m.rowH > 0 then
      local rowY = y + (row - 1) * m.rowH
      local node = {
        type = interactive and "button" or "rectangle",
        x = m.pad, y = rowY, w = w - m.pad * 2, h = m.rowH - 2,
        -- The other reactive closure: which row is armed moves with the pilot's trims, and
        -- repainting the whole scene for it would cost a build per press.
        color = function()
          local snap = state.inflight
          if type(snap) == "table" and snap.row == row then return accent end
          return btn
        end
      }
      -- See appendChips: a button has no `filled`.
      if not interactive then node.filled = true end
      if interactive and drive then
        node.press = function()
          drive:selectRow(row)
          widget.built = false
          widget.renderKey = nil
        end
      end
      children[#children + 1] = node

      local label = entry.name or t("widgets.dashboard.inflight_unassigned", "Unassigned")
      local textY = rowY + math.floor((m.rowH - m.lineH) / 2)
      appendLabel(children, m.pad + 6, textY, math.floor(w * 0.6), label, WHITE, m.smallFont, LEFT)
      appendLabel(children, math.floor(w * 0.6), textY, math.floor(w * 0.4) - m.pad - 6,
        formatValue(entry.value), WHITE, m.smallFont, RIGHT)
    end
  end
end

-- ---------------------------------------------------------------------------
-- The zone screen
-- ---------------------------------------------------------------------------

--- The overlay in the widget's own zone, while the interlock is on. No controls: the trims drive
-- it and this is the read-out.
function M.buildZone(children, widget)
  local w = (widget.zone and widget.zone.w) or LCD_W or 480
  local h = (widget.zone and widget.zone.h) or LCD_H or 272
  local t = translator(widget)
  local bg, accent, btn = palette()
  local m = metrics(w, h, false)

  children[#children + 1] = { type = "rectangle", x = 0, y = 0, w = w, h = h, color = bg, filled = true }
  appendHeader(children, widget, m, w, t, accent, btn)

  local y = m.headerH + m.pad
  appendChips(children, widget, m, y, t, accent, btn, false)
  y = y + m.chipH + m.pad
  appendActive(children, widget, m, y, w, t, accent)
  y = y + m.activeH
  appendRows(children, widget, m, y, w, t, accent, btn, false)

  appendLabel(children, m.pad, h - m.hintH, w - m.pad * 2,
    t("widgets.dashboard.inflight_hint_touch", "Long press for the touch controls"), WHITE, m.smallFont, CENTER)
end

-- ---------------------------------------------------------------------------
-- The fullscreen screen
-- ---------------------------------------------------------------------------

local function appendClose(children, widget, m, w, t)
  local size = m.large and 44 or 20
  local x = w - size - (m.large and 8 or 1)
  local y = math.floor((m.headerH - size) / 2)
  children[#children + 1] = {
    type = "button", x = x, y = y, w = size, h = size, color = COLOR_THEME_SECONDARY1 or RED,
    press = function()
      -- The same three lines widgets/dashboard/fullscreen_menu.lua closes with: drop what is
      -- built, drop the render key, leave fullscreen.
      widget.built = false
      widget.renderKey = nil
      if lcd and type(lcd.exitFullScreen) == "function" then
        lcd.exitFullScreen()
      end
    end
  }
  appendLabel(children, x, y + math.floor((size - m.lineH) / 2), size,
    "X", WHITE, m.font, CENTER)
end

--- The two step controls.
--
-- A momentary button reports its press AND its release, which is what a held control needs: the
-- value stays written for as long as the finger is down and the flight controller repeats its own
-- step. Where the firmware's LVGL build does not offer one -- the table is asked, not assumed --
-- a plain button stands in and a tap is one step.
local function appendActions(children, widget, m, y, w, t, btn)
  local drive = widget._inflight
  if drive == nil then return end
  local momentary = lvgl and type(lvgl.momentaryButton) == "function"
  local buttonW = math.floor((w - m.pad * 3) / 2)

  local specs = {
    { x = m.pad, up = false, label = "-" },
    { x = m.pad * 2 + buttonW, up = true, label = "+" }
  }

  for i = 1, #specs do
    local spec = specs[i]
    local node = {
      type = momentary and "momentaryButton" or "button",
      x = spec.x, y = y, w = buttonW, h = m.actionH, color = btn
    }
    if momentary then
      node.press = function() drive:press(drive.row, spec.up) end
      node.release = function() drive:release() end
    else
      node.press = function() drive:tap(drive.row, spec.up) end
    end
    children[#children + 1] = node
    appendLabel(children, spec.x, y + math.floor((m.actionH - m.lineH) / 2), buttonW,
      spec.label, WHITE, m.bigFont, CENTER)
  end
end

-- ---------------------------------------------------------------------------
-- The ground surface
-- ---------------------------------------------------------------------------

-- What the delta list is written to. There is no scrolling here -- the surface is a read-out a
-- pilot glances at between flights, not a table to be walked -- so what does not fit is COUNTED
-- rather than reachable, and the count is on the screen.
local MAX_DELTA_ROWS = 8

--- Where the ground half has got to, in one phrase.
local function describePrime(snapshot, t)
  local state = snapshot.prime
  if type(state) ~= "table" or state.phase == nil or state.phase == "idle" then
    return t("widgets.dashboard.inflight_prime_never", "Not primed")
  end
  if state.phase == "done" then
    return t("widgets.dashboard.inflight_prime_done", "Primed")
  end
  if state.phase == "error" then
    return t("widgets.dashboard.inflight_prime_failed", "Prime failed")
  end
  return t("widgets.dashboard.inflight_prime_running", "Priming") .. " "
    .. tostring(state.done or 0) .. "/" .. tostring(state.total or 0)
end

--- Which of the two layouts the rows came from. Said in words because a set that quietly fell
-- back to the documented layout and one that came off this board look exactly alike otherwise.
local function describeSet(snapshot, t)
  if snapshot.setSource == "board" then
    return t("widgets.dashboard.inflight_set_board", "Set from the board")
  end
  return t("widgets.dashboard.inflight_set_reference", "Documented layout")
end

--- Whether an undo exists, and what the last attempt at making one did.
local function describeBackup(snapshot, t)
  local transfer = snapshot.transfer
  if type(transfer) == "table" and transfer.state == "busy" then
    return t("widgets.dashboard.inflight_transfer_busy", "Copying profile")
  end
  if type(transfer) == "table" and transfer.state == "error" then
    return t("widgets.dashboard.inflight_transfer_failed", "Profile copy failed")
  end
  local backup = snapshot.backup
  if type(backup) == "table" then
    return t("widgets.dashboard.inflight_backup_held", "Backup in profile") .. " " .. tostring(backup.profile)
  end
  return t("widgets.dashboard.inflight_backup_none", "No backup")
end

--- One action, as the button-with-a-label-over-it their fullscreen menu is built from: an LVGL
-- button carries the press and a label drawn on top of it carries the text.
local function appendAction(children, m, x, y, width, label, btn, press)
  children[#children + 1] = {
    type = "button", x = x, y = y, w = width, h = m.actionH, color = btn, press = press
  }
  appendLabel(children, x, y + math.floor((m.actionH - m.lineH) / 2), width, label, WHITE, m.font, CENTER)
end

--- What the flight changed: every parameter whose cached value has moved away from the snapshot
-- the backup was taken with, largest change first.
--
-- Built into the tree rather than read by a closure. The list only moves when a value does, and
-- a value moving already moves the drive's epoch, which is in the render key -- so the rebuild
-- that puts a new list on screen is the one the key was going to cause anyway.
local function appendDelta(children, widget, m, y, w, h, t, accent)
  local drive = widget._inflight
  local Prime = prime()
  appendLabel(children, m.pad, y, w - m.pad * 2,
    t("widgets.dashboard.inflight_delta_title", "CHANGED SINCE THE BACKUP"), accent, m.smallFont, LEFT)
  y = y + m.lineH + 2

  local list = (drive ~= nil and Prime ~= nil) and Prime.delta(drive) or nil
  if list == nil then
    appendLabel(children, m.pad, y, w - m.pad * 2,
      t("widgets.dashboard.inflight_delta_unprimed", "Prime first: there is nothing to compare against"),
      WHITE, m.smallFont, LEFT)
    return
  end
  if #list == 0 then
    appendLabel(children, m.pad, y, w - m.pad * 2,
      t("widgets.dashboard.inflight_delta_none", "Nothing has changed"), WHITE, m.smallFont, LEFT)
    return
  end

  -- What the screen has room for, and never more than the cap: the shortest radio decides.
  local room = math.floor((h - y - m.pad) / m.lineH)
  if room > MAX_DELTA_ROWS then room = MAX_DELTA_ROWS end
  if room < 1 then room = 1 end
  local shown = (#list < room) and #list or room

  for i = 1, shown do
    local entry = list[i]
    local rowY = y + (i - 1) * m.lineH
    appendLabel(children, m.pad, rowY, math.floor(w * 0.55), entry.name, WHITE, m.smallFont, LEFT)
    appendLabel(children, math.floor(w * 0.55), rowY, math.floor(w * 0.45) - m.pad,
      formatValue(entry.old) .. " -> " .. formatValue(entry.new), accent, m.smallFont, RIGHT)
  end

  if #list > shown then
    appendLabel(children, m.pad, y + shown * m.lineH, w - m.pad * 2,
      "+" .. tostring(#list - shown) .. " " .. t("widgets.dashboard.inflight_delta_more", "more"),
      WHITE, m.smallFont, LEFT)
  end
end

--- The surface the pilot meets between flights: what the overlay knows, what it can undo, and
-- what the last flight moved.
--
-- The tuning controls are not here on purpose. The interlock is open, so nothing could be sent
-- anyway, and the space that the bank chips and the row list would take is what the delta list
-- needs on the shortest screen the suite runs on.
function M.buildGround(children, widget, m, w, h, t, accent, btn)
  local snapshot = widget.state.inflight or {}
  local drive = widget._inflight
  local Prime = prime()
  local armed = (widget.state and widget.state.armed) == true

  local y = m.headerH + m.pad
  appendLabel(children, m.pad, y, w - m.pad * 2,
    t("widgets.dashboard.inflight_check", "SETUP") .. ": " .. M.describeCheck(M.checkVerdict(widget), t),
    WHITE, m.smallFont, LEFT)
  y = y + m.lineH + 2
  appendLabel(children, m.pad, y, w - m.pad * 2,
    describePrime(snapshot, t) .. "  /  " .. describeSet(snapshot, t), WHITE, m.smallFont, LEFT)
  y = y + m.lineH + 2
  appendLabel(children, m.pad, y, w - m.pad * 2, describeBackup(snapshot, t), WHITE, m.smallFont, LEFT)
  y = y + m.lineH + m.pad

  if armed then
    -- Nothing here can reach the board while it is armed -- the MSP runtime clears its queue on
    -- every armed tick -- so the actions are absent rather than present and refusing.
    appendLabel(children, m.pad, y + math.floor(m.actionH / 2) - math.floor(m.lineH / 2), w - m.pad * 2,
      t("widgets.dashboard.inflight_ground_armed", "Disarm to prime or copy a profile"), WHITE, m.smallFont, CENTER)
  elseif drive ~= nil and Prime ~= nil then
    local slot = math.floor(tonumber(drive.settings.backup_profile) or 0)
    local buttonW = math.floor((w - m.pad * 4) / 3)
    appendAction(children, m, m.pad, y, buttonW,
      t("widgets.dashboard.inflight_prime", "Prime"), btn, function()
        Prime.start(widget, drive)
        widget.built = false
        widget.renderKey = nil
      end)
    appendAction(children, m, m.pad * 2 + buttonW, y, buttonW,
      t("widgets.dashboard.inflight_backup", "Backup to") .. " " .. tostring(slot), btn, function()
        Prime.backup(widget, drive)
        widget.built = false
        widget.renderKey = nil
      end)
    appendAction(children, m, m.pad * 3 + buttonW * 2, y, buttonW,
      t("widgets.dashboard.inflight_restore", "Restore from") .. " " .. tostring(slot), btn, function()
        Prime.restore(widget, drive)
        widget.built = false
        widget.renderKey = nil
      end)
  end
  y = y + m.actionH + m.pad

  appendDelta(children, widget, m, y, w, h, t, accent)
end

--- The overlay with its controls. Reached by a long press while the interlock is on, and from the
-- quick settings menu while it is off -- there the drive is inert and what is shown instead is
-- the ground surface.
function M.buildFullscreen(children, widget)
  local w = (widget.zone and widget.zone.w) or LCD_W or 480
  local h = (widget.zone and widget.zone.h) or LCD_H or 272
  local t = translator(widget)
  local bg, accent, btn = palette()
  local m = metrics(w, h, true)

  children[#children + 1] = { type = "rectangle", x = 0, y = 0, w = w, h = h, color = bg, filled = true }
  appendHeader(children, widget, m, w, t, accent, btn)
  appendClose(children, widget, m, w, t)

  local snapshot = widget.state.inflight or {}
  if snapshot.live ~= true then
    M.buildGround(children, widget, m, w, h, t, accent, btn)
    return
  end

  local y = m.headerH + m.pad
  appendChips(children, widget, m, y, t, accent, btn, true)
  y = y + m.chipH + m.pad
  appendActive(children, widget, m, y, w, t, accent)
  y = y + m.activeH
  appendRows(children, widget, m, y, w, t, accent, btn, true)
  y = y + m.rowH * Functions.ROW_COUNT + m.pad

  appendActions(children, widget, m, y, w, t, btn)
  y = y + m.actionH

  local verdict = M.describeCheck(M.checkVerdict(widget), t)
  appendLabel(children, m.pad, y, w - m.pad * 2,
    t("widgets.dashboard.inflight_check", "SETUP") .. ": " .. verdict, WHITE, m.smallFont, LEFT)
end

return M
