-- The three renderings of the in-flight tuning overlay: the widget zone, fullscreen, and the
-- ground surface between flights.
--
-- All three append node tables to `children`, the idiom widgets/dashboard/fullscreen_menu.lua
-- uses, so the runtime builds them exactly the way it builds the quick settings menu.
--
-- The layout is the concept drawing's, and it is laid out in FRACTIONS of the widget's own zone
-- rather than in constants: the reference is 480 x 272, the pilot's radio is 480 x 320 and the
-- large radios are 800 x 480, and a surface a pilot reads at arm's length in sunlight cannot have
-- a row list that runs off the bottom of one of them. Only the fonts step, because the firmware
-- offers a ladder of five and not a size.
--
-- The zone screen carries NO buttons. Whether an LVGL button in a non-fullscreen widget zone ever
-- receives a press is not something this file knows, and a control that may or may not answer is
-- worse on a tuning screen than no control at all: there the pilot's trims are the input and the
-- screen is the read-out.
--
-- What is reactive here is what the FLIGHT CONTROLLER moves -- the value, the value it stepped
-- from, the six row values, the active row's colour and the lines that expire on the clock -- and
-- every one of them reads the precomputed snapshot on `widget.state.inflight` and nothing else.
-- Everything else is laid down at build time and replaced when the render key moves. The division
-- is not a style: the board answers a step while the radio is still holding the pulse that asked
-- for it, and a rebuild in that window costs the pilot a second step he did not ask for. That is the rule from
-- GEMINI.md: a closure handed to lvgl.build runs per frame, on whatever instruction budget
-- refresh() left over, outside the widget's own pcall.

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
local Drive = requireModule("widgets/dashboard/inflight/drive.lua")
local Input = requireModule("widgets/dashboard/inflight/input.lua")

-- A dependency that did not load must not leave a WORKING-LOOKING module behind.
--
-- lib/require.lua caches whatever a chunk RETURNS. Its own load of a dependency goes through
-- pcall, and a pcall catches the firmware's instruction-limit error like any other -- so a widget
-- pass that runs out of budget while one of the files above is being read leaves the require
-- answering nil, this chunk running on to its end with a nil upvalue, and the broken table cached
-- for the rest of the session. Every call into it then raises
--   ?:0: attempt to index a nil value (upvalue '?')
-- on every pass, for ever, and the widget's refresh is abandoned each time. That is what the
-- pilot's card log recorded 913 times after a start with no flight controller: the overlay's
-- modules were first loaded on the pass the connect chain and the theme reload were already
-- filling, and the load that lost the race was cached.
--
-- Raising here instead means the pcall in lib/require.lua fails, NOTHING is cached, and the next
-- pass loads the file again on a budget that may well be quieter. A missing file behaves the same
-- way and is answered by the caller, which keeps its own retry.
if type(Functions) ~= "table" or type(Drive) ~= "table" or type(Input) ~= "table" then
  error("inflight/screen.lua: a dependency did not load", 0)
end

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


local UNKNOWN_VALUE = "--"

local function translator(widget)
  return (widget.i18n and type(widget.i18n.t) == "function") and widget.i18n.t
    or function(key, fallback) return fallback or key end
end

-- ---------------------------------------------------------------------------
-- Colours
-- ---------------------------------------------------------------------------

--- The surface's palette.
--
-- The theme's own constants where the quick settings menu uses them, and named colours where the
-- drawing asks for one the theme does not carry. `lcd.RGB` is the firmware's own mixer and this
-- file is not the first to reach for it: widgets/dashboard/fullscreen_menu.lua builds its
-- background with it, and widgets/dashboard/objects/common.lua wraps it for the gauges.
--
-- Rotorflight's dark surface and blue accent stay local to the overlay. Every colour retains a
-- theme fallback on a firmware build without lcd.RGB.
local function rgb(r, g, b, fallback)
  if lcd and type(lcd.RGB) == "function" then
    local ok, col = pcall(lcd.RGB, r, g, b)
    if ok and col ~= nil then return col end
  end
  return fallback
end

local function palette()
  local p = {}
  p.bg = rgb(20, 25, 30, COLOR_THEME_PRIMARY3 or BLACK)
  p.header = rgb(30, 37, 44, COLOR_THEME_PRIMARY1 or BLACK)
  p.text = rgb(233, 238, 242, WHITE)
  p.dim = rgb(154, 167, 179, COLOR_THEME_DISABLED or WHITE)
  p.accent = rgb(41, 163, 224, COLOR_THEME_SECONDARY1 or BLUE)
  p.onAccent = rgb(11, 18, 24, BLACK)
  p.border = rgb(52, 64, 75, COLOR_THEME_DISABLED or WHITE)
  p.error = rgb(229, 83, 75, RED)
  p.ok = rgb(90, 200, 120, GREEN or WHITE)
  p.warn = rgb(242, 163, 58, COLOR_THEME_WARNING or YELLOW)
  p.button = p.header
  -- The armed row's fill: dark, with just enough of the accent in it that the outline reads as
  -- belonging to the row rather than floating over it.
  p.rowFill = rgb(30, 52, 67, COLOR_THEME_PRIMARY1 or BLACK)
  return p
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

-- The firmware's font ladder, with the heights the layout has to reserve for them.
--
-- There is no way to ask the firmware how tall a font is from a widget, so these are read off a
-- rendered frame -- the title in the header, the parameter name and the value, measured on the
-- simulator at 800 x 480 -- and every vertical stack below is built from them. They are the box
-- the glyphs occupy and not the cap height: a stack built from the cap height puts the next line
-- across the descenders of the one above, which is what the caption did to the parameter name.
local FONT_H = { [SMLSIZE or -1] = 14, [MIDSIZE or -2] = 30, [DBLSIZE or -3] = 40, [XXLSIZE or -4] = 66 }

local function fontHeight(font)
  return FONT_H[font] or 12
end

-- How wide one character of each font is, on average. The firmware will not say, and a label
-- whose text is wider than its box does not clip it -- it WRAPS, onto the row below and off the
-- bottom of the screen. So text that cannot fit is cut here instead.
--
-- MEASURED on a rendered frame, per font, and not derived from the height by one ratio: the
-- small font runs about 8.5 pixels against a box 14 tall and the middle one about 15 against a
-- box of 30, so one ratio over-estimates the larger fonts by a third and cuts titles that fit.
--
-- Each figure is the WIDEST average a string of that font was measured at, not the mean one --
-- `Yaw CCW Stop` runs 10.1 pixels a character where a lowercase sentence runs 8. A budget set at
-- the mean cuts most strings correctly and lets the capital-heavy ones wrap, which is the failure
-- it exists to prevent; set at the maximum it cuts a few strings a character early, which is not
-- a failure at all.
local FONT_W = { [SMLSIZE or -1] = 11, [MIDSIZE or -2] = 16, [DBLSIZE or -3] = 21, [XXLSIZE or -4] = 34 }

local function charWidth(font)
  return FONT_W[font] or 9
end

-- Geometry scales with the surface; fonts use the firmware's discrete size ladder.
local function metrics(w, h, fullscreen)
  local m = {}
  m.large = h > 350
  m.font = m.large and MIDSIZE or SMLSIZE
  m.nameFont = m.large and DBLSIZE or MIDSIZE
  m.small, m.valueFont = SMLSIZE, XXLSIZE
  m.fontH, m.smallH = fontHeight(m.font), fontHeight(m.small)
  m.valueH = m.large and 100 or 66
  m.lineH = m.smallH + 2
  m.textOff = m.large and -6 or -2
  m.pad = math.max(3, math.floor(w * 0.021 + 0.5))
  m.headerH = math.max(16, math.floor(h * 0.125 + 0.5))
  m.chipY = m.headerH + math.max(2, math.floor(h * 0.029 + 0.5))
  m.statusLineH = math.max(m.fontH + 2, math.max(10, math.floor(h * 0.081 + 0.5)))
  m.actionH = fullscreen and math.max(18, math.floor(h * 0.206 + 0.5)) or 0
  m.glyphFont = m.actionH >= 80 and XXLSIZE or DBLSIZE
  m.glyphH = fontHeight(m.glyphFont)
  m.footerH = math.max(22, math.floor(h * 0.081))
  m.browseH = m.large and 54 or 40
  m.listFont = m.large and MIDSIZE or 0
  m.selectedFont = MIDSIZE
  -- The selected browse row is taller than the others so its value can use a larger font.
  m.selectedH = m.large and 80 or 56
  m.selectedValueFont = m.large and XXLSIZE or DBLSIZE
  return m
end

local function appendLabel(children, x, y, w, text, color, font, align)
  children[#children + 1] = {
    type = "label", x = x, y = y, w = w, text = text, color = color, align = align, font = font
  }
end

--- A reactive text of up to two lines as two labels, `step` apart.
--
-- One label holding "a\nb" is laid out with LVGL's own line spacing, which is larger than the
-- font box the rows below are placed by (about 41 px against 32 for the middle font at 800x480),
-- so its second line ran into the row under it. Two labels keep both lines on the measured grid.
-- `textFn` is the row's own cached reader; both labels ask it and split its answer.
local function appendTwoLines(children, x, y, w, textFn, color, font, step)
  local lastText, first, second = nil, "", ""
  local function split()
    local text = textFn()
    if text ~= lastText then
      lastText = text
      local cut = type(text) == "string" and string.find(text, "\n", 1, true) or nil
      if cut then first, second = string.sub(text, 1, cut - 1), string.sub(text, cut + 1)
      else first, second = text or "", "" end
    end
  end
  appendLabel(children, x, y, w, function() split(); return first end, color, font, LEFT)
  appendLabel(children, x, y + step, w, function() split(); return second end, color, font, LEFT)
end

--- A label whose glyphs sit centred in a box `boxH` tall.
local function appendCentredLabel(children, x, y, w, boxH, text, color, font, align, m)
  appendLabel(children, x, y + math.floor((boxH - fontHeight(font)) / 2) + m.textOff,
    w, text, color, font, align)
end


--- `text`, cut to what fits in `width` at `font`. Cut without an ellipsis: three dots cost three
-- of the characters that were the reason to cut, and on a parameter name the front is what
-- identifies it.
local function textFits(text, width, font)
  if type(text) ~= "string" then return true end
  return (#text * charWidth(font)) <= width
end

-- At most `n` bytes of `text`, never ending inside a UTF-8 character: the Configurator's German
-- names carry umlauts, and half of one draws as a broken glyph.
local function cutUtf8(text, n)
  if #text <= n then return text end
  while n > 0 do
    local b = string.byte(text, n + 1)
    if b == nil or b < 128 or b >= 192 then break end
    n = n - 1
  end
  return string.sub(text, 1, n)
end

local function fitText(text, width, font)
  if type(text) ~= "string" then return text end
  local budget = math.floor(width / charWidth(font))
  if budget < 1 then budget = 1 end
  return cutUtf8(text, budget)
end

--- `text` on at most two lines of `width`, broken at the last space that fits; the second line is
-- cut if it still does not fit. The full names are long in German and the selected row has the
-- height for two lines.
local function fitTwoLines(text, width, font)
  if type(text) ~= "string" or textFits(text, width, font) then return text end
  local head = fitText(text, width, font)
  local space
  for i = #head, 2, -1 do
    if string.sub(head, i, i) == " " then space = i; break end
  end
  local first, rest
  if space then first, rest = string.sub(text, 1, space - 1), string.sub(text, space + 1)
  else first, rest = head, string.sub(text, #head + 1) end
  return first .. "\n" .. fitText(rest, width, font)
end

--- `long` where it fits, `short` where it does not, cut only if neither does.
--
-- A caption or a hint carries more on a wide screen than on a narrow one, and the alternative --
-- one wording cut in the middle -- loses the end of the sentence on every radio rather than on
-- the small one. The pair is two i18n keys and the choice is made per screen.
local function pickText(long, short, width, font)
  if textFits(long, width, font) then return long end
  return fitText(short, width, font)
end

local function formatValue(value)
  if value == nil then return UNKNOWN_VALUE end
  return tostring(math.floor(value + 0.5))
end

-- ---------------------------------------------------------------------------
-- The setup check, as one line
-- ---------------------------------------------------------------------------

--- The verdict, walked ONCE and then kept on the drive.
--
-- Two things this is deliberately not. It is not on a timer: with a two-second one it walked the
-- model's mixer lines, its variable details and its flight mode's trim modes over and over for as
-- long as the surface was up -- and in the air that is every couple of seconds, for a verdict
-- about a model that cannot change while the pilot is flying it. And it is not run while the
-- overlay is LIVE at all: the ground surface is the only place the verdict is shown, and it walks
-- nothing while the overlay is up, because the one place that budget must not be spent is the
-- pass that is driving the flight controller.
--
-- The walk is repeated when the settings move, which is the only thing that can change the answer
-- without the pilot leaving this screen; widgets/dashboard/inflight/drive.lua's own settings
-- comparison drops the cache when it re-settles a drive.
--
-- What holds the walk off is the PHASE and not the interlock, and the difference is the whole of
-- the verdict on a great many screens. `live` says the interlock is closed; the phase says the
-- craft is in the air, since it only reaches `live` on the arm reading. A pilot who closes the
-- interlock on the ground -- to look at the surface before he flies, which is what it is for --
-- had a drive whose `live` was already true, so the walk never ran and the one line that exists
-- to tell him whether his model is wired up read "Setup not checked" for the whole session. The
-- reason the walk is held off at all is the pass that is driving the flight controller, and that
-- pass is the airborne one.
function M.checkVerdict(widget)
  local drive = widget and widget._inflight
  if drive == nil then return nil end
  -- One cache, and the drive owns it: the same verdict decides whether the interlock may close at
  -- all, so a walk of this screen's own would be a second answer to a question with one.
  return Drive.verdict(drive)
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
  -- The interlock refused because the trim block is still being walked (inflight/drive.lua,
  -- M.TRIMS_PENDING). Not a fault the pilot has to fix, so it is the whole sentence.
  if result[1] == "trims_pending" then
    return t("widgets.dashboard.inflight_check_trims_pending", "Checking trims")
  end

  local unset, mix, gvar, trim, claim = false, false, false, false, false
  local same, twice, missing = false, false, false
  for i = 1, #result do
    local code = result[i]
    -- The two "one thing doing both jobs" faults are matched FIRST and by name. `same_gvar` reads
    -- as neither a gvar_ fault nor a mixer one, and left to the tests below it would have fallen
    -- through to "not set" -- which is the opposite of what it is.
    if code == "same_gvar" or code == "same_channel" then
      same = true
    elseif code == "trim_claimed_twice" then
      twice = true
    elseif code == "flight_list_missing" then
      missing = true
    elseif string.find(code, "mix", 1, true) then
      mix = true
    elseif string.find(code, "gvar_", 1, true) then
      gvar = true
    elseif string.find(code, "trim_mode", 1, true) then
      trim = true
    elseif code == "no_nav_trim" then
      claim = true
    else
      unset = true
    end
  end

  local parts = {}
  if unset then parts[#parts + 1] = t("widgets.dashboard.inflight_check_unset", "Switch or variables not set") end
  if same then parts[#parts + 1] = t("widgets.dashboard.inflight_check_same", "Bank and value share a variable or a channel") end
  if mix then parts[#parts + 1] = t("widgets.dashboard.inflight_check_mix", "Mixer line missing or wrong") end
  if gvar then parts[#parts + 1] = t("widgets.dashboard.inflight_check_gvar", "Variable range or precision") end
  if trim then parts[#parts + 1] = t("widgets.dashboard.inflight_check_trim", "Trim still active") end
  if claim then parts[#parts + 1] = t("widgets.dashboard.inflight_check_claim", "Walk and adjust need two trims") end
  if twice then parts[#parts + 1] = t("widgets.dashboard.inflight_check_twice", "One trim is claimed twice") end
  if missing then
    local names = {}
    for i = 1, #(result.missing or {}) do names[i] = Functions.nameOf(result.missing[i]) end
    parts[#parts + 1] = t("widgets.dashboard.inflight_check_flight_list", "Flight list contains unavailable parameters")
      .. ": " .. table.concat(names, ", ")
  end
  return table.concat(parts, " / ")
end

-- ---------------------------------------------------------------------------
-- The pieces the three surfaces share
-- ---------------------------------------------------------------------------

--- The header bar: what this surface is, which profile it is tuning, and whether it is live.
--
-- The set the rows come from is named HERE rather than left to the ground surface, because a
-- standard set and a set read off the board name the same six banks differently and the chips
-- immediately below carry the difference.
local function appendHeader(children, widget, m, w, t, p, closeW)
  local snapshot = widget.state.inflight or {}
  children[#children + 1] = {
    type = "rectangle", x = 0, y = 0, w = w, h = m.headerH, color = p.header, filled = true
  }

  -- The headline is the PROFILE, and that is the pilot's own ruling after the third radio round.
  -- The firmware's adjustments act on whichever PID profile is active, he chooses that with a
  -- switch of his own, and everything else on this surface is true of that one profile and of no
  -- other -- so it is the one thing on the screen that must not need looking for. It used to be
  -- dim text beside a title that said "TUNING - set: standard"; the set moved to the ground
  -- surface, which is where it can be acted on, and the profile took the room.
  local titleW = w - closeW - m.pad * 4 - 84
  appendCentredLabel(children, m.pad, 0, titleW, m.headerH,
    function() local snap = widget.state.inflight; return snap and snap.profileText or "" end,
    p.text, m.large and MIDSIZE or 0, LEFT, m)

  -- Which of the three phases this is, in one word. The switch is one, so the word is what says
  -- which surface the pilot is looking at.
  local liveText, liveColor
  if snapshot.phase == "live" and snapshot.profileRefusal ~= nil then
    liveText, liveColor = t("widgets.dashboard.inflight_paused", "PAUSED"), p.error
  elseif snapshot.phase == "live" then
    liveText, liveColor = t("widgets.dashboard.inflight_live", "LIVE"), p.ok
  elseif snapshot.phase == "post" then
    liveText, liveColor = t("widgets.dashboard.inflight_after", "AFTER"), p.accent
  else
    liveText, liveColor = t("widgets.dashboard.inflight_ground", "GROUND"), p.dim
  end
  -- Wide enough for the LONGER of the two words in the SMALL font, which is what it is drawn in:
  -- in the middle font `GROUND` needs a hundred pixels and wrapped into `GRO` over `UND`, and the
  -- room to widen the box is room the profile beside it needs.
  local liveW = math.max(math.floor(w * 0.09), 6 * charWidth(m.small) + 6)
  local liveX = w - closeW - m.pad - liveW
  local dotR = math.max(3, math.floor(m.headerH * 0.12))
  children[#children + 1] = {
    type = "circle", x = liveX - m.pad - dotR, y = math.floor(m.headerH / 2),
    radius = dotR, color = liveColor, filled = true
  }
  appendCentredLabel(children, liveX, 0, liveW, m.headerH, liveText, liveColor, m.small, LEFT, m)


end

-- The group title opens the radio's own menu of every group, so the pilot jumps straight to one
-- instead of paging through them. The arrows beside it walk the functions of the group. Without
-- a native menu the title steps to the next group, as before.
local function openGroupMenu(widget, groups, t)
  local drive = widget._inflight
  if drive == nil then return end
  -- The same fence every other touch action passes (Input.dispatch): the encoder's next sensor
  -- return after the popup closes is not a detent.
  local sensor = widget._inflightSensor
  if sensor then sensor.index = nil end
  if not (lvgl and type(lvgl.menu) == "function") or #groups < 2 then
    Input.dispatch(widget, "group", 1, "touch")
    return
  end
  Input.rebuild(widget)
  local names = {}
  for i, group in ipairs(groups) do names[i] = group.name end
  lvgl.menu({
    title = t("widgets.dashboard.inflight_choose_group", "Choose group"),
    values = names,
    get = function() return drive.group or 1 end,
    set = function(index)
      -- The menu can outlive the flight it was opened in; a choice made after landing does nothing.
      if widget._inflight ~= drive or drive.phase ~= "live" then return end
      local delta = (tonumber(index) or 0) - (drive.group or 1)
      if delta ~= 0 then Input.dispatch(widget, "group", delta, "touch")
      else Input.dispatch(widget, "function", nil, "touch", 1) end
    end
  })
end

-- The title is the only group selector. Rows retain full names and their hidden cell address;
-- the native focus ring supplies browse feedback without changing the FC table. Value reports
-- replace snapshot strings only, never the objects that receive a press or an encoder detent.
local function appendFlight(children, widget, m, w, h, t, p, interactive)
  local snapshot = widget.state.inflight or {}
  local drive, state = widget._inflight, widget.state
  local group = snapshot.groups and snapshot.groups[snapshot.group or 1]
  local groups = snapshot.groups or {}
  local groupY = m.headerH + 6
  local groupH = m.large and 48 or 36
  local arrowW = m.large and 60 or 44
  local lineW = w - m.pad * 2
  local footerY = h - m.footerH
  local function action(name, direction, index)
    return function() Input.dispatch(widget, name, direction, "touch", index) end
  end
  local function button(target, x, y, width, height, text, press, color)
    target[#target + 1] = {
      type = "button", x = x, y = y, w = width, h = height, color = color or p.button,
      text = text, textColor = p.text, press = press
    }
  end
  local title = group and group.name or t("widgets.dashboard.inflight_no_parameters", "No driveable parameters")
  local titleX, titleW = m.pad + arrowW + 4, lineW - arrowW * 2 - 8
  local contentY = groupY + groupH + 4
  local paused = snapshot.profileRefusal ~= nil
  local hint = snapshot.valueMode
    and t("widgets.dashboard.inflight_value_controls", "Rotate +/- step / Press or RTN done")
    or t("widgets.dashboard.inflight_browse_controls", "PAGE group / Rotate function / Press tune")
  children[#children + 1] = {type = "rectangle", x = 0, y = footerY, w = w, h = m.footerH, color = p.header, filled = true}
  appendCentredLabel(children, m.pad, footerY, lineW, m.footerH,
    pickText(hint, snapshot.valueMode
      and t("widgets.dashboard.inflight_value_controls_short", "Rotate +/- / Press or RTN done")
      or t("widgets.dashboard.inflight_browse_controls_short", "PAGE group / Rotate / Press tune"), lineW, m.small),
    p.dim, m.small, CENTER, m)

  if paused then
    children[#children + 1] = {type = "rectangle", x = m.pad, y = contentY, w = lineW,
      h = footerY - contentY - 4, color = p.header, filled = true}
    local y = contentY + m.pad
    appendLabel(children, m.pad * 2, y, lineW - m.pad * 2,
      t("widgets.dashboard.inflight_paused", "PAUSED"), p.error, MIDSIZE, LEFT)
    y = y + 32
    local reasons = {
      pid_unread = t("widgets.dashboard.inflight_pid_unread", "PID profile not read"),
      rate_unread = t("widgets.dashboard.inflight_rate_unread", "Rate profile not read"),
      profile_unknown = t("widgets.dashboard.inflight_profile_unknown", "PID# or RTE# unknown"),
      board_unknown = t("widgets.dashboard.inflight_board_identity_pending", "Waiting for FC identity"),
      profile_reading = t("widgets.dashboard.inflight_profile_reading", "Profile read/return pending")
    }
    appendLabel(children, m.pad * 2, y, lineW - m.pad * 2, reasons[snapshot.profileRefusal] or "", p.warn, m.listFont, LEFT)
    y = y + math.max(22, m.fontH)
    for _, field in ipairs({"pauseActive", "pauseSession"}) do
      appendLabel(children, m.pad * 2, y, lineW - m.pad * 2,
        function() local snap = state.inflight; return snap and snap[field] or "" end, p.text, m.listFont, LEFT)
      y = y + math.max(22, m.fontH)
    end
    local instruction
    if snapshot.restorePending then
      instruction = t("widgets.dashboard.inflight_return_disarm", "Disarm to return to original profiles")
    elseif snapshot.profileRefusal == "board_unknown" then
      instruction = ""
    elseif snapshot.profileRefusal == "session_unread" or snapshot.profileRefusal == "profile_reading" then
      instruction = t("widgets.dashboard.inflight_read_ground", "Read values on the ground before tuning")
    else
      instruction = t("widgets.dashboard.inflight_resume_read", "Return to a read profile; new session adds profiles")
    end
    local width, line = lineW - m.pad * 2, ""
    for word in string.gmatch(instruction, "%S+") do
      local candidate = line == "" and word or line .. " " .. word
      if not textFits(candidate, width, m.small) and line ~= "" then
        appendLabel(children, m.pad * 2, y, width, line, p.warn, m.small, LEFT)
        y, line = y + m.lineH, word
      else line = candidate end
    end
    appendLabel(children, m.pad * 2, y, width, line, p.warn, m.small, LEFT)
  -- The viewport initially shows the selection; the first focus move scrolls to its neighbour.
  elseif snapshot.valueMode then
    local nameH = m.large and 48 or 32
    local stackH = m.valueH + 2 + (m.large and 28 or 20)
    local valueY = contentY + nameH + math.max(0,
      math.floor((footerY - m.lineH - 4 - contentY - nameH - stackH) / 2))
    local nameFont = m.nameFont
    for _, entry in ipairs(group and group.entries or {}) do
      if not textFits(entry.name, lineW, nameFont) then nameFont = m.large and MIDSIZE or 0 end
    end
    local lastName, fittedName
    local nameText = function()
      local snap = state.inflight
      local name = snap and snap.activeName or ""
      if name ~= lastName then lastName, fittedName = name, fitText(name, lineW, nameFont) end
      return fittedName or ""
    end
    if interactive and drive then
      local ladderRows = Input.LADDER_ROWS
      local sensor = Input.sensor(widget, nameH, ladderRows, true)
      local forward, reverse = sensor.windows()
      local ladder, previous = {}, {}
      local first, leave = sensor.first, sensor.leave
      local color, textColor = p.header, p.text
      -- The transparent resting window still participates in pointer hit testing.
      previous[1] = {
        type = "button", y = first * nameH, w = lineW, h = nameH,
        pos = function() return 0, sensor.positions[first - 1] + nameH * 2 end,
        color = color, textColor = textColor, font = nameFont, text = nameText, press = leave
      }
      local function guard(list, index)
        list[#list + 1] = {
          type = "button", x = 0, y = index * nameH, w = lineW, h = nameH,
          color = p.header, textColor = p.text, font = m.font,
          text = t("widgets.dashboard.inflight_encoder", "Encoder"), press = sensor.leave
        }
      end
      guard(previous, 0)
      local list, window = previous, reverse
      local position = window.position
      for index = 1, ladderRows do
        if index == first then list, window, position = ladder, forward, forward.position end
        list[#list + 1] = {
          type = "button", y = index * nameH, w = lineW, h = nameH,
          pos = position(index), color = color, textColor = textColor, font = nameFont,
          text = nameText, press = leave
        }
      end
      guard(ladder, ladderRows + 1)
      ladder[#ladder + 1] = previous[#previous]
      guard(ladder, ladderRows + 2)
      children[#children + 1] = {
        type = "box", x = m.pad, y = contentY, w = lineW, h = nameH, borderPad = 0,
        scrollDir = (lvgl and lvgl.SCROLL_VER) or 12, scrollBar = false, color = p.bg,
        scrolled = forward.scrolled, scrollTo = forward.scrollTo, opacity = forward.opacity, children = ladder
      }
      previous[#previous + 1] = {type = "rectangle", x = 0, y = (ladderRows + 2) * nameH,
        w = 1, h = 1, color = p.bg}
      widget._inflightReverseNode = {
        type = "box", x = m.pad, y = contentY, w = lineW, h = nameH, borderPad = 0,
        scrollDir = (lvgl and lvgl.SCROLL_VER) or 12, scrollBar = false, color = p.bg,
        scrolled = reverse.scrolled, scrollTo = reverse.scrollTo, opacity = reverse.opacity, children = previous
      }
    else
      appendLabel(children, m.pad, contentY, lineW, nameText, p.text, nameFont, CENTER)
    end
    -- Plus and minus stacked in one column on the right, as large as the surface allows, and in
    -- two different colours, so the thumb finds the right one without reading the glyph. The value
    -- and its comparison take the left side.
    local stepW = math.floor(lineW * 0.42)
    local centreX, centreW = m.pad, lineW - stepW - m.pad
    appendLabel(children, centreX, valueY, centreW,
      function() local snap = state.inflight; return snap and snap.activeValueText or UNKNOWN_VALUE end,
      p.accent, m.valueFont, CENTER)
    local compareY = valueY + m.valueH + 2
    appendLabel(children, centreX, compareY, centreW,
      function() local snap = state.inflight; return snap and snap.activeComparison or "" end,
      p.accent, m.large and 0 or m.small, CENTER)
    local refusals = {
      cooling = t("widgets.dashboard.inflight_too_fast", "too fast - one step at a time"),
      range = t("widgets.dashboard.inflight_custom_range", "Row cannot be stepped"),
      list_end = t("widgets.dashboard.inflight_list_end", "End of list"),
      report_sync = t("widgets.dashboard.inflight_report_sync", "Waiting for fresh adjustment telemetry"),
      hold_limit = t("widgets.dashboard.inflight_hold_limit_short", "5 s over - press again"),
      bounds = t("widgets.dashboard.inflight_bounds_refused", "Beyond the FC limits: set up the FC again")
    }
    appendLabel(children, m.pad, footerY - m.lineH - 2, lineW,
      function() local snap = state.inflight; return snap and refusals[snap.stepRefusedReason] or "" end,
      p.warn, m.small, CENTER)
    local buttonY = contentY + nameH + 2
    local columnH = footerY - buttonY - m.lineH - 4
    local buttonH = math.floor((columnH - m.pad) / 2)
    for i = 1, 2 do
      -- Plus on top in the accent colour, minus below in the warning colour.
      local direction = i == 1 and 1 or -1
      local node = {
        type = (lvgl and type(lvgl.momentaryButton) == "function") and "momentaryButton" or "button",
        x = w - m.pad - stepW, y = buttonY + (i - 1) * (buttonH + m.pad), w = stepW, h = buttonH,
        color = i == 1 and p.accent or p.warn,
        children = {
          {type = "label", x = 0, y = math.floor((buttonH - m.glyphH) / 2) + m.textOff,
            w = stepW, text = i == 1 and "+" or "-", color = p.onAccent, font = m.glyphFont, align = CENTER}
        }
      }
      if node.type == "momentaryButton" then
        node.press = function() Input.dispatch(widget, "step", direction, "touch_hold") end
        node.release = function() Input.dispatch(widget, "release", nil, "touch_hold") end
      else node.press = action("step", direction) end
      children[#children + 1] = node
    end
  else
    local rows = snapshot.groupRows or {}
    local rowH = m.browseH
    -- The selected row is taller than its neighbours: its value is the one the pilot reads.
    local selH = interactive and m.selectedH or rowH
    local hintH = m.smallH + 2
    local visible = math.max(1, 1 + math.floor((footerY - contentY - hintH * 2 - selH) / rowH))
    local anchor = math.min(2, visible)
    local listY = contentY + hintH
    local selectedY = listY + (anchor - 1) * rowH
    local valueW = m.large and 140 or 84
    local diffW = m.large and 86 or 44
    local nameW = lineW - valueW - diffW - 20
    local selValueW = interactive and (m.large and 190 or 120) or valueW
    local selNameW = lineW - selValueW - diffW - 20
    local list, scrollRows = {}, {}
    local selectedButton
    local sensor = interactive and #rows > 0 and Input.sensor(widget, selH, #rows, false) or nil
    local previous, forward, reverse = {}
    if sensor then
      forward, reverse = sensor.windows()
      button(previous, 0, 0, lineW, selH,
        t("widgets.dashboard.inflight_list_end", "End of list"), sensor.press(0))
    end
    local nameFont = m.selectedFont
    for _, entry in ipairs(rows) do
      if not textFits(entry.name, selNameW, nameFont) then nameFont = 0 end
    end
    local lastName, fittedName
    local rowChildren
    -- Native TextButton padding is not changed by borderPad. Include its two-pixel border
    -- and the firmware's scaled horizontal/vertical padding in child coordinates.
    local buttonX, buttonY = w == 800 and 10 or (w == 320 and 7 or 8), w == 800 and 5 or 4
    local function selectedName()
      local snap = state.inflight
      local entry = snap and snap.groupRows and snap.groupRows[snap.entry]
      local name = entry and entry.name or ""
      if name ~= lastName then lastName, fittedName = name, fitTwoLines(name, selNameW, nameFont) end
      return fittedName or ""
    end
    for offset = 0, #rows - 1 do
      local index = offset + 1
      local target = sensor and index < sensor.first and previous or list
      local entry, rowY = rows[index], (index - 1) * selH
      scrollRows[index] = rowY
      local function field(key, fallback)
        return function()
          local snap = state.inflight
          local current = snap and snap.groupRows and snap.groupRows[sensor and snap.entry or index]
          return current and current[key] or fallback
        end
      end
      button(target, 0, sensor and rowY + selH or rowY, lineW, selH, "", sensor and sensor.press(index) or nil, p.rowFill)
      local node = target[#target]
      if sensor and index == sensor.first - 1 then selectedButton = node end
      node.borderPad = 0
      if rowChildren == nil or not sensor then rowChildren = {
        {type = "rectangle", x = -buttonX, y = -buttonY, w = lineW, h = selH, color = p.accent, thickness = 2, rounded = 6},
        {type = "label", x = 8 - buttonX, y = 0, w = selNameW,
          text = sensor and selectedName or fitTwoLines(entry.name, selNameW, nameFont), color = p.text, font = nameFont, align = VCENTER},
        {type = "label", x = selNameW + 10 - buttonX, y = 0, w = diffW,
          text = field("differenceText", ""), color = p.accent, font = m.small, align = RIGHT + VCENTER},
        {type = "label", x = lineW - selValueW - 16 - buttonX, y = 0,
          w = selValueW, text = field("valueText", UNKNOWN_VALUE), color = p.text, font = m.selectedValueFont, align = RIGHT + VCENTER}
      } end
      node.children = rowChildren
      if sensor and index == #rows then
        button(list, 0, (#rows + 1) * selH, lineW, selH,
          t("widgets.dashboard.inflight_list_end", "End of list"), sensor.press(#rows + 1))
      end
    end
    if sensor then
      local first = sensor.first
      table.insert(previous, 1, {
        type = "button", x = 0, y = first * selH, w = lineW, h = selH, borderPad = 0,
        pos = function() return 0, sensor.positions[first - 1] + selH * 2 end,
        text = "", color = p.rowFill, children = selectedButton.children, press = sensor.press(first - 1)
      })
      list[#list + 1] = selectedButton
      button(list, 0, (#rows + 2) * selH, lineW, selH,
        t("widgets.dashboard.inflight_list_end", "End of list"), sensor.press(#rows + 2))
    end
    -- Neighbour slots read the semantic selection, while the native sensor stays at a fixed row.
    if interactive then
      children[#children + 1] = {
        type = "box", x = m.pad, y = selectedY, w = lineW, h = selH, borderPad = 0,
        scrollDir = (lvgl and lvgl.SCROLL_VER) or 12, scrollBar = false, color = p.bg, children = list,
        scrolled = forward and forward.scrolled, opacity = forward and forward.opacity,
        scrollTo = forward and forward.scrollTo or function()
          local snap = state.inflight; return 0, snap and scrollRows[snap.entry] or 0
        end
      }
      if sensor then
        previous[#previous + 1] = {type = "rectangle", x = 0, y = (#rows + 2) * selH,
          w = 1, h = 1, color = p.bg}
        widget._inflightReverseNode = {
          type = "box", x = m.pad, y = selectedY, w = lineW, h = selH, borderPad = 0,
          scrollDir = (lvgl and lvgl.SCROLL_VER) or 12, scrollBar = false, color = p.bg,
          scrolled = reverse.scrolled, scrollTo = reverse.scrollTo, opacity = reverse.opacity, children = previous
        }
      end
    end
    for slot = 1, visible do
      if slot ~= anchor or not interactive then
        local offset = slot - anchor
        local rowY = listY + (slot - 1) * rowH + (slot > anchor and selH - rowH or 0)
        local function field(key, fallback)
          return function()
            local snap = state.inflight
            local row = snap and snap.groupRows and snap.groupRows[(snap.entry or 1) + offset]
            return row and row[key] or fallback
          end
        end
        appendCentredLabel(children, m.pad + 8, rowY, nameW, rowH, field("name", ""), p.text, m.listFont, LEFT, m)
        appendCentredLabel(children, m.pad + nameW + 10, rowY, diffW, rowH,
          field("differenceText", ""), p.accent, m.small, RIGHT, m)
        appendCentredLabel(children, w - m.pad - valueW - 8, rowY, valueW, rowH,
          field("valueText", ""), p.text, m.listFont, RIGHT, m)
      end
    end
    local more = t("widgets.dashboard.inflight_more", "more")
    for index = 1, 2 do
      appendLabel(children, m.pad, index == 1 and contentY or listY + (visible - 1) * rowH + selH, lineW,
        function()
          local snap = state.inflight
          local selected = snap and snap.entry or 1
          local count = index == 1 and selected - anchor or #rows - selected - (visible - anchor)
          return count > 0 and ((index == 1 and "^ " or "v ") .. count .. " " .. more) or ""
        end, p.dim, m.small, CENTER)
    end
    local endText = t("widgets.dashboard.inflight_list_end", "End of list")
    local busyText = t("widgets.dashboard.inflight_too_fast", "too fast - one step at a time")
    appendLabel(children, m.pad, footerY - m.lineH, lineW, function()
      local snap = state.inflight
      return snap and (snap.stepRefusedReason == "list_end" and endText or snap.stepRefusedReason == "cooling" and busyText) or ""
    end, p.warn, m.small, CENTER)
  end
  if interactive then
    button(children, m.pad, groupY, arrowW, groupH, "<", action("function", -1), p.accent)
    button(children, titleX, groupY, titleW, groupH, title, function() openGroupMenu(widget, groups, t) end)
    button(children, w - m.pad - arrowW, groupY, arrowW, groupH, ">", action("function", 1), p.accent)
  else appendCentredLabel(children, m.pad, groupY, lineW, groupH, title, p.accent, m.font, CENTER, m) end
end

-- ---------------------------------------------------------------------------
-- The zone screen
-- ---------------------------------------------------------------------------

--- The overlay in the widget's own zone, while the interlock is on.
--
-- No controls out here: the trims drive it and this is the read-out. WHICH read-out is the phase's
-- to say, and that is the pilot's core change after the third radio round. The interlock is the
-- one entry he has, and what it shows follows the flight rather than the switch -- the preflight
-- read-out on the ground, the tuning surface in the air, and the delta and the undo on the ground
-- after a flight that moved something. Three screens on one switch, and nothing to remember.
local appendBusy

function M.buildZone(children, widget)
  local w = (widget.zone and widget.zone.w) or LCD_W or 480
  local h = (widget.zone and widget.zone.h) or LCD_H or 272
  local t = translator(widget)
  local p = palette()
  local m = metrics(w, h, false)
  local snapshot = widget.state.inflight or {}

  children[#children + 1] = { type = "rectangle", x = 0, y = 0, w = w, h = h, color = p.bg, filled = true }
  appendHeader(children, widget, m, w, t, p, 0)

  if widget._inflight and widget._inflight.profileJob and snapshot.phase ~= "live" then
    appendBusy(children, widget, m, w, h, t, p, false)
    return
  end
  if snapshot.phase == "post" then
    M.buildPost(children, widget, m, w, h, t, p, false)
    return
  end
  if snapshot.phase ~= "live" then
    M.buildGround(children, widget, m, w, h, t, p, false)
    return
  end

  appendFlight(children, widget, m, w, h, t, p, false)

end

-- ---------------------------------------------------------------------------
-- The fullscreen screen
-- ---------------------------------------------------------------------------

local function closeWidth(m)
  return m.large and 44 or 28
end

local function appendClose(children, widget, m, w, p)
  local size = closeWidth(m)
  local x = w - size - (m.large and 8 or 1)
  local y = math.floor((m.headerH - size) / 2)
  children[#children + 1] = {
    type = "button", x = x, y = y, w = size, h = size, color = p.error,
    press = function() Input.dispatch(widget, "close", nil, "touch") end
  }
  appendCentredLabel(children, x, y, size, size, "X", p.text, m.font, CENTER, m)
end

-- ---------------------------------------------------------------------------
-- The ground surface
-- ---------------------------------------------------------------------------

-- The cap on the delta list is gone with the pilot's third radio round. It used to be eight rows
-- with "+9 more" under them, on a board that has ALREADY written all of them to its own storage --
-- so the ones the cap hid were the ones nobody would ever see again. The postflight surface pages
-- the whole list instead, with the walk trim; see M.buildPost.

--- The usable set comes only from the completed board slot read.
local function describeSet(snapshot, t)
  local text
  if snapshot.setSource == "board" then
    text = string.format(t("widgets.dashboard.inflight_board_parameters", "%d parameters from the board"), snapshot.cellCount or 0)
  elseif snapshot.setSource == "unavailable" then
    text = t("widgets.dashboard.inflight_board_no_slots", "No usable slots on the board")
  else
    return t("widgets.dashboard.inflight_board_unread", "Not read yet")
  end
  local skipped = snapshot.prime and snapshot.prime.skipped or 0
  if skipped > 0 then
    text = text .. string.format(t("widgets.dashboard.inflight_board_skipped", " (%d skipped)"), skipped)
  end
  return text
end

local function displayTimestamp(stamp)
  local year, month, day, hour, minute = string.match(stamp or "", "^(%d%d%d%d)(%d%d)(%d%d)(%d%d)(%d%d)")
  if year then return year .. "-" .. month .. "-" .. day .. " " .. hour .. ":" .. minute end
  if string.match(stamp or "", "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d") then return string.sub(stamp, 1, 16) end
  return stamp or ""
end

local function describeBackup(snapshot, t)
  -- While the slot table is read the session line is the read's progress.
  local status = snapshot.prime
  local phase = type(status) == "table" and status.phase or nil
  if phase ~= nil and phase ~= "idle" and phase ~= "error" and phase ~= "done" then
    return t("widgets.dashboard.inflight_prime_running", "Reading") .. " "
      .. tostring(status.done or 0) .. "/" .. tostring(status.total or 0)
  end
  if snapshot.restorePending then
    return t("widgets.dashboard.inflight_return_pending", "Original profiles: return pending; disarm/reconnect")
  end
  local transfer = snapshot.transfer
  if transfer then
    if transfer.state == "busy" then return t("widgets.dashboard.inflight_restore_busy", "Restoring tracked values") end
    if transfer.state == "ok" then return t("widgets.dashboard.inflight_restore_ok", "Restored and verified") .. " " .. (snapshot.restoreSummary or "") end
    return t("widgets.dashboard.inflight_restore_failed", "Restore refused/failed") .. ": "
      .. M.restoreReason(transfer.reason, t) .. " " .. (snapshot.restoreSummary or "")
  end
  if snapshot.baseline then
    local stamp = displayTimestamp(snapshot.baseline.timestamp)
    if snapshot.sessionMode == "resume" then
      return string.format(t("widgets.dashboard.inflight_session_continued", "Continued, start values from %s"), stamp)
    elseif snapshot.sessionMode == "new" then
      return string.format(t("widgets.dashboard.inflight_session_new", "New, start values from %s"), stamp)
    end
    return t("widgets.dashboard.inflight_baseline_sd", "SD baseline") .. " " .. stamp
  end
  local state = snapshot.prime
  if state and state.phase == "error" then
    return t("widgets.dashboard.inflight_prime_failed", "Reading failed") .. ": " .. M.restoreReason(state.error, t)
  end
  return t("widgets.dashboard.inflight_prime_never", "Values not read")
end

function M.restoreReason(reason, t)
  if type(reason) == "table" and reason.kind == "firmware_range" then
    return string.format(t("widgets.dashboard.inflight_firmware_range", "%s: value %s outside firmware range"), reason.name, tostring(reason.value))
  end
  if reason == "baseline_identity" then return t("widgets.dashboard.inflight_baseline_identity", "Baseline belongs to another FC") end
  if reason == "baseline_incomplete" or reason == "baseline_missing" then return t("widgets.dashboard.inflight_baseline_incomplete", "Baseline missing or incomplete") end
  if reason == "baseline_io" then return t("widgets.dashboard.inflight_baseline_io", "SD baseline write/read failed") end
  if reason == "verify_failed" then return t("widgets.dashboard.inflight_verify_failed", "Read-back differs") end
  if reason == "armed" then return t("widgets.dashboard.inflight_ground_armed", "Disarm to read or restore") end
  if reason == "reading" then return t("widgets.dashboard.inflight_profile_reading", "Profile read/return pending") end
  if reason == "no_link" then return t("widgets.dashboard.inflight_no_link", "No FC link") end
  if reason == "profile_count" or reason == "profile_changed" then return t("widgets.dashboard.inflight_profile_changed", "FC profile/count changed during read") end
  return t("widgets.dashboard.inflight_transaction_failed", "FC transaction failed")
end

local function appendAction(children, m, x, y, width, label, p, press)
  children[#children + 1] = {
    type = "button", x = x, y = y, w = width, h = m.actionH, color = p.button, press = press
  }
  appendCentredLabel(children, x, y, width, m.actionH, fitText(label, width, m.small), p.text, m.small, CENTER, m)
end

-- Preserve every word on setup surfaces; the plan paginates these measured lines.
local function wrapSetup(text, width, font)
  local lines = {}
  for paragraph in string.gmatch(text .. "\n", "([^\n]*)\n") do
    local line = ""
    for word in string.gmatch(paragraph, "%S+") do
      local candidate = line == "" and word or line .. " " .. word
      if line ~= "" and not textFits(candidate, width, font) then
        lines[#lines + 1], line = line, word
      else line = candidate end
    end
    lines[#lines + 1] = line
  end
  return lines
end

--- The ground surface shows model readiness, board slots and the stored session.
function M.buildGround(children, widget, m, w, h, t, p, interactive)
  local drive = widget._inflight
  local Prime = prime()
  local armed = (widget.state and widget.state.armed) == true
  local state = widget.state
  local empty = {}
  local y, lineW = m.chipY, w - m.pad * 2
  local lineFont = m.font
  local wrap = h >= 320
  local statusH = (fontHeight(lineFont) + 2) * (wrap and 2 or 1)
  local fit = wrap and fitTwoLines or fitText
  -- One status row at the current y; where rows wrap, its two lines are two labels `step` apart.
  local function row(textFn, color, font, step)
    if wrap then appendTwoLines(children, m.pad, y, lineW, textFn, color, font, step)
    else appendLabel(children, m.pad, y, lineW, textFn, color, font, LEFT) end
  end
  local lineStep = fontHeight(lineFont) + 2

  local lastVerdict, modelText
  row(function()
    local verdict = state.inflight and state.inflight.setupVerdict
    if modelText == nil or verdict ~= lastVerdict then
      lastVerdict = verdict
      modelText = fit(t("widgets.dashboard.inflight_model_status", "Model") .. ": " .. M.describeCheck(verdict, t), lineW, lineFont)
    end
    return modelText
  end, p.text, lineFont, lineStep)
  y = y + statusH

  -- Snapshots are replaced on publication; cache the scalar inputs rather than their tables.
  local lastSource, lastCount, lastSkipped, setText
  row(function()
    local snap = state.inflight or empty
    local skipped = snap.prime and snap.prime.skipped
    if setText == nil or snap.setSource ~= lastSource or snap.cellCount ~= lastCount or skipped ~= lastSkipped then
      lastSource, lastCount, lastSkipped = snap.setSource, snap.cellCount, skipped
      setText = fit(t("widgets.dashboard.inflight_slots_status", "FC slots") .. ": " .. describeSet(snap, t), lineW, lineFont)
    end
    return setText
  end, p.text, lineFont, lineStep)
  y = y + statusH

  local lastMode, lastTimestamp, lastPending, lastTransfer, lastReason, lastSummary, lastPhase, lastError, lastDone, sessionText
  row(function()
    local snap = state.inflight or empty
    local timestamp = snap.baseline and snap.baseline.timestamp
    local transfer, status = snap.transfer, snap.prime
    local transferState, reason = transfer and transfer.state, transfer and transfer.reason
    local phase, err, done = status and status.phase, status and status.error, status and status.done
    if sessionText == nil or snap.sessionMode ~= lastMode or timestamp ~= lastTimestamp
      or snap.restorePending ~= lastPending or transferState ~= lastTransfer or reason ~= lastReason
      or snap.restoreSummary ~= lastSummary or phase ~= lastPhase or err ~= lastError or done ~= lastDone then
      lastMode, lastTimestamp, lastPending = snap.sessionMode, timestamp, snap.restorePending
      lastTransfer, lastReason, lastSummary = transferState, reason, snap.restoreSummary
      lastPhase, lastError, lastDone = phase, err, done
      sessionText = fit(t("widgets.dashboard.inflight_session_status", "Session") .. ": " .. describeBackup(snap, t), lineW, lineFont)
    end
    return sessionText
  end, p.text, lineFont, lineStep)
  y = y + statusH

  -- Reserve this row at build time; a completed ground read rebuilds the surface.
  if (state.inflight and state.inflight.boundsCount or 0) > 0 then
    local lastBounds, warning
    row(function()
      local count = state.inflight and state.inflight.boundsCount or 0
      if count ~= lastBounds then
        lastBounds = count
        warning = count > 0 and fit(string.format(t("widgets.dashboard.inflight_bounds_warning",
          "%d beyond the FC limits: set up the FC again"), count), lineW, m.small) or ""
      end
      return warning
    end, p.warn, m.small, m.lineH)
    y = y + m.lineH * (wrap and 2 or 1)
  end
  -- A model-default save that failed says so until the next build that has nothing to report.
  if drive and drive.saveResult and drive.saveResult ~= "ok" then
    appendLabel(children, m.pad, y, lineW, fitText(t("widgets.dashboard.inflight_save_failed",
      "Not saved as the model default:") .. " " .. drive.saveResult, lineW, m.small), p.warn, m.small, LEFT)
    y = y + m.lineH
  end
  y = y + 4

  -- Why the ground half is refusing, when it is not simply that the board is armed. The one case
  -- so far is the arm sensor never having answered: the ground half then refuses everything,
  -- because a model whose sensor 99 is not in the telemetry list reads as disarmed for ever and
  -- MSP sent on that reading goes to a helicopter in the air.
  local refusal = (Prime ~= nil and type(Prime.groundRefusal) == "function") and Prime.groundRefusal(widget) or nil

  local blocked = false
  if armed then
    -- Nothing here can reach the board while it is armed -- the MSP runtime clears its queue on
    -- every armed tick -- so the actions are absent rather than present and refusing.
    appendLabel(children, m.pad, y, lineW,
      fitText(t("widgets.dashboard.inflight_ground_armed", "Disarm to read or restore"),
              lineW, lineFont),
      p.text, lineFont, LEFT)
    y = y + m.statusLineH
    blocked = true
  elseif refusal == "no_arm_sensor" then
    appendLabel(children, m.pad, y, lineW,
      fitText(t("widgets.dashboard.inflight_ground_no_arm", "Arm sensor not seen: is sensor 99 selected?"),
              lineW, lineFont),
      p.warn, lineFont, LEFT)
    y = y + m.statusLineH
    blocked = true
  end

  if not interactive then
    -- The zone screen has no buttons at all -- whether an LVGL button in a widget zone even takes
    -- a press is unmeasured -- so it says where the actions are instead. It says it whatever
    -- else stands above it: the two states that used to return before this line are exactly the
    -- ones a pilot is looking for something to do about, and the hint is the only thing on the
    -- zone that tells him this screen has more on it than he can see.
    appendLabel(children, m.pad, y, lineW,
      fitText(t("widgets.dashboard.inflight_hint_touch", "long press for touch controls"), lineW, m.small),
      p.dim, m.small, LEFT)
    return
  end
  if blocked then return end
  if drive == nil or Prime == nil then return end

  local gap = m.large and 8 or 4
  local action = {actionH = m.large and 56 or 40, small = m.large and m.font or m.small, textOff = m.textOff}
  local available = not Prime.isRunning(drive) and not drive.profileJob and not drive.restorePending
  local snapshot = state.inflight or {}
  local completed = snapshot.prime and snapshot.prime.phase == "done"
  local emptyBoard = completed and (snapshot.setSource ~= "board" or (snapshot.cellCount or 0) == 0)
  local function openSetup()
    if drive.fcSetupOpen or widget.state.armed == true or Prime.isRunning(drive) or drive.profileJob or drive.restorePending then return end
    drive.fcSetupOpen = true
    drive.valueEpoch = drive.valueEpoch + 1
    widget._tuningKeyDirty = true
  end
  if emptyBoard and available then
    appendLabel(children, m.pad, y, lineW,
      t("widgets.dashboard.inflight_fc_no_functions", "The FC has no adjustment functions for in-flight tuning."),
      p.text, m.small, LEFT)
    y = y + m.lineH
  end
  local chooseActive = function()
    local snap = state.inflight
    return snap ~= nil and snap.setSource == "board" and (snap.cellCount or 0) > 0
  end
  appendAction(children, action, m.pad, y, lineW,
    emptyBoard and t("widgets.dashboard.inflight_fc_setup_action", "Set up suggested functions")
      or t("widgets.dashboard.inflight_choose_parameters", "Choose parameters"), p, function()
      if not available or drive.fcSetupOpen or widget.state.armed == true then return end
      if emptyBoard then openSetup(); return end
      drive.sessionPickerOpen = true
      drive.valueEpoch = drive.valueEpoch + 1
      widget._tuningKeyDirty = true
    end)
  local primaryActive = function() return available and (emptyBoard or chooseActive()) end
  children[#children - 1].active = primaryActive
  children[#children - 1].visible = primaryActive
  children[#children - 1].color = p.accent
  children[#children].color = p.onAccent
  children[#children].visible = primaryActive
  y = y + action.actionH + gap

  action.actionH, action.small = m.large and 32 or (h >= 320 and 24 or 32), m.small
  if not emptyBoard and available then
    appendAction(children, action, m.pad, y, lineW,
      t("widgets.dashboard.inflight_fc_setup_action", "Set up suggested functions"), p, openSetup)
    y = y + action.actionH + gap
  end
  action.actionH = m.large and 24 or 26
  local buttonW = math.floor((lineW - m.pad) / 2)
  appendAction(children, action, m.pad, y, buttonW,
    t("widgets.dashboard.inflight_read_again", "Read again"), p, function()
      if drive.fcSetupOpen then return end
      if drive.restorePending then Prime.retryReturn(drive)
      elseif drive.setSource ~= "board" then
        -- No set from the board (never read, or the channels changed since): read the slot table
        -- again too, continuing the stored session rather than replacing its start values.
        Prime.start(widget, drive, true)
      else Prime.refreshValues(widget, drive) end
      widget._tuningKeyDirty = true
    end)
  appendAction(children, action, m.pad * 2 + buttonW, y, buttonW,
    t("widgets.dashboard.inflight_reset_start", "Reset start values"), p, function()
      if drive.fcSetupOpen then return end
      drive.resetConfirm = true
      drive.valueEpoch = drive.valueEpoch + 1
      widget._tuningKeyDirty = true
    end)
  appendAction(children, action, m.pad, h - m.pad - action.actionH, lineW,
    t("widgets.dashboard.inflight_restore_all", "Restore all"), p, function()
      if drive.fcSetupOpen then return end
      if Prime.isRunning(drive) then return end
      drive.restoreConfirm = {all = true}
      drive.valueEpoch = drive.valueEpoch + 1
      widget._tuningKeyDirty = true
    end)
  children[#children - 1].color = p.error
end

-- ---------------------------------------------------------------------------
-- The postflight surface
-- ---------------------------------------------------------------------------

-- Each page repeats its profile/group heading so a continued group retains its identity.
function M.buildPost(children, widget, m, w, h, t, p, interactive)
  local drive, Prime = widget._inflight, prime()
  local lineW, y = w - m.pad * 2, m.chipY
  local footerY = h - m.footerH
  local list = drive and Prime and Prime.delta(drive)
  local actionY = interactive and footerY - m.actionH - m.pad or footerY
  local rowH = m.large and 32 or 24
  local rowFont = m.large and MIDSIZE or 0
  local footer = interactive and t("widgets.dashboard.inflight_post_controls", "RTN close / Board has saved")
    or t("widgets.dashboard.inflight_post_saved_zone", "board has saved - restore: full screen")
  children[#children + 1] = {type = "rectangle", x = 0, y = footerY, w = w, h = m.footerH, color = p.header, filled = true}
  appendCentredLabel(children, m.pad, footerY, lineW, m.footerH, footer, p.dim, m.small, LEFT, m)

  if drive and drive.postActionsOpen then
    local target = drive.postActionsOpen
    local bw = math.floor((lineW - m.pad) / 2)
    appendLabel(children, m.pad, y, lineW, t("widgets.dashboard.inflight_post_actions", "Restore / read values"), p.accent, rowFont, LEFT)
    y = y + rowH
    local menuGap = math.max(4, math.floor(m.pad / 2))
    appendAction(children, m, m.pad, y, bw, t("widgets.dashboard.inflight_restore_all", "Restore all"), p, function()
      if Prime.isRunning(drive) then return end
      drive.postActionsOpen = nil
      drive.restoreConfirm = {all = true}; drive.valueEpoch = drive.valueEpoch + 1
      widget._tuningKeyDirty = true
    end)
    appendAction(children, m, m.pad * 2 + bw, y, bw, t("widgets.dashboard.inflight_read_again", "Read again"), p, function()
      drive.postActionsOpen = nil
      if drive.restorePending then Prime.retryReturn(drive) else Prime.refreshValues(widget, drive) end
      widget._tuningKeyDirty = true
    end)
    y = y + m.actionH + menuGap
    local label = target.kind == "global" and t("widgets.dashboard.inflight_restore_global", "Restore global")
      or t("widgets.dashboard.inflight_restore_profile", "Restore profile") .. " "
        .. (target.kind == "pid" and "PID " or "RTE ") .. tostring(target.index)
    appendAction(children, m, m.pad, y, lineW, label, p, function()
      if Prime.isRunning(drive) then return end
      drive.postActionsOpen = nil
      drive.restoreConfirm = target; drive.valueEpoch = drive.valueEpoch + 1
      widget._tuningKeyDirty = true
    end)
    y = y + m.actionH + menuGap
    appendAction(children, m, m.pad, y, lineW, t("widgets.dashboard.inflight_post_back", "Back to changes"), p, function()
      drive.postActionsOpen = nil; drive.valueEpoch = drive.valueEpoch + 1
      widget._tuningKeyDirty = true
    end)
    return
  end

  appendLabel(children, m.pad, y, lineW, list and string.format(
    t("widgets.dashboard.inflight_changed_count", "%d parameters changed"), #list)
    or t("widgets.dashboard.inflight_delta_unprimed", "Read the values first: nothing to compare against"), p.accent, rowFont, LEFT)
  y = y + rowH + 4
  local capacity = math.max(2, math.floor((actionY - m.lineH - 2 - y) / rowH))
  local pageRows = {}
  local pages = {pageRows}
  local heading, previousScope, previousProfile, previousGroup, title
  for _, entry in ipairs(list or {}) do
    local newProfile = entry.scope ~= previousScope or entry.profile ~= previousProfile
    if newProfile or entry.group ~= previousGroup then
      title = (entry.scope == "global" and t("widgets.dashboard.inflight_global", "Global")
        or (entry.scope == "pid" and "PID " or t("widgets.dashboard.inflight_rate_label", "Rate") .. " ") .. entry.profile)
        .. " / " .. Functions.GROUPS[entry.group].name
      previousScope, previousProfile, previousGroup = entry.scope, entry.profile, entry.group
    end
    if #pageRows > 0 and (newProfile or #pageRows >= capacity or (title ~= heading and #pageRows + 2 > capacity)) then
      pageRows, heading = {}, nil; pages[#pages + 1] = pageRows
    end
    if title ~= heading then
      pageRows[#pageRows + 1] = {heading = title, target = entry}; heading = title
    end
    pageRows[#pageRows + 1] = entry
  end
  local page = math.max(1, math.min(drive and drive.deltaPage or 1, #pages))
  if drive then drive.deltaPages, drive.deltaPage = #pages, page end
  local target = pages[page][1] and pages[page][1].target or {scope = "global"}
  local nameW = math.floor(lineW * 0.52)
  for index, entry in ipairs(pages[page]) do
    local rowY = y + (index - 1) * rowH
    if entry.heading then
      children[#children + 1] = {type = "rectangle", x = m.pad, y = rowY, w = lineW, h = rowH, color = p.rowFill, filled = true}
      appendCentredLabel(children, m.pad + 4, rowY, lineW - 8, rowH,
        fitText(entry.heading, lineW - 8, rowFont), p.accent, rowFont, LEFT, m)
    else
      appendCentredLabel(children, m.pad + 4, rowY, nameW - 4, rowH, fitText(entry.name, nameW - 4, rowFont), p.text, rowFont, LEFT, m)
      appendCentredLabel(children, m.pad + nameW, rowY, lineW - nameW - 4, rowH,
        formatValue(entry.old) .. " -> " .. formatValue(entry.new) .. "  " .. string.format("%+d", entry.new - entry.old), p.accent, rowFont, RIGHT, m)
    end
  end
  local note = target.scope == "rate" and t("widgets.dashboard.inflight_rate_restore_note", "PID restore does not cover rate profiles")
    or t("widgets.dashboard.inflight_delta_title", "CHANGED SINCE SD BASELINE")
  appendLabel(children, m.pad, actionY - m.lineH - 2, lineW, note, p.dim, m.small, LEFT)
  if not interactive or not drive or not Prime then return end
  local arrowW = m.large and 72 or 48
  local buttonW = lineW - arrowW * 2 - m.pad * 2
  appendAction(children, m, m.pad, actionY, buttonW, t("widgets.dashboard.inflight_post_actions", "Restore / read values"), p, function()
    drive.postActionsOpen = {kind = target.scope, index = target.profile}
    drive.valueEpoch = drive.valueEpoch + 1; widget._tuningKeyDirty = true
  end)
  for index = 1, 2 do
    local direction = index == 1 and -1 or 1
    children[#children + 1] = {
      type = "button", x = w - m.pad - arrowW * (3 - index), y = actionY,
      w = arrowW - 4, h = m.actionH, color = p.accent, textColor = p.onAccent,
      text = index == 1 and "<" or ">", press = function() Input.dispatch(widget, "group", direction, "touch") end
    }
  end
  appendLabel(children, w - m.pad - 80, footerY + 2, 80, page .. "/" .. #pages, p.text, m.small, RIGHT)
end

local function appendRestoreConfirmation(children, widget, m, w, t, p)
  local drive, Prime = widget._inflight, prime()
  local request = drive.restoreConfirm
  local names = {}
  if request.all then
    for _, kind in ipairs({"pid", "rate"}) do
      for index = 1, 6 do
        if drive.baseline and drive.baseline[kind .. index] then
          names[#names + 1] = (kind == "pid" and "PID " or "RTE ") .. index
        end
      end
    end
    names[#names + 1] = t("widgets.dashboard.inflight_global", "Global")
  else
    names[1] = request.kind == "global" and t("widgets.dashboard.inflight_global", "Global")
      or (request.kind == "pid" and "PID " or "RTE ") .. tostring(request.index)
  end
  local y, width = m.headerH + m.pad, w - m.pad * 2
  appendLabel(children, m.pad, y, width, t("widgets.dashboard.inflight_restore_confirm", "Restore SD start values?"), p.warn, m.small, LEFT)
  y = y + m.lineH
  -- Three targets per line also fits the German 480x320 surface.
  for first = 1, #names, 3 do
    appendLabel(children, m.pad, y, width, table.concat(names, ", ", first, math.min(#names, first + 2)), p.text, m.small, LEFT)
    y = y + m.lineH
  end
  y = y + m.pad
  local bw = math.floor((width - m.pad) / 2)
  appendAction(children, m, m.pad, y, bw, t("widgets.dashboard.inflight_restore_yes", "Restore"), p, function()
    if drive.restoreConfirm ~= request then return end
    drive.restoreConfirm = nil
    local target
    if not request.all then target = request end
    Prime.restore(widget, drive, target)
    drive.valueEpoch = drive.valueEpoch + 1; widget._tuningKeyDirty = true
  end)
  appendAction(children, m, m.pad * 2 + bw, y, bw, t("widgets.dashboard.inflight_restore_cancel", "Cancel"), p, function()
    drive.restoreConfirm = nil
    drive.valueEpoch = drive.valueEpoch + 1; widget._tuningKeyDirty = true
  end)
end

local function appendResetConfirmation(children, widget, m, w, t, p)
  local drive, Prime = widget._inflight, prime()
  local y, width = m.headerH + m.pad, w - m.pad * 2
  appendLabel(children, m.pad, y, width, fitTwoLines(t("widgets.dashboard.inflight_reset_start_confirm",
    "Replace the stored start values with the current values?"), width, m.small), p.warn, m.small, LEFT)
  y = y + m.lineH * 2
  appendLabel(children, m.pad, y, width, fitTwoLines(t("widgets.dashboard.inflight_reset_start_restore",
    "Restore all will then return to these new values."), width, m.small), p.text, m.small, LEFT)
  y = y + m.lineH * 2 + m.pad
  local bw = math.floor((width - m.pad) / 2)
  appendAction(children, m, m.pad, y, bw, t("widgets.dashboard.inflight_reset_start_yes", "Reset"), p, function()
    if not drive.resetConfirm then return end
    drive.resetConfirm = nil
    Prime.start(widget, drive)
    drive.valueEpoch = drive.valueEpoch + 1; widget._tuningKeyDirty = true
  end)
  appendAction(children, m, m.pad * 2 + bw, y, bw, t("widgets.dashboard.inflight_reset_start_cancel", "Cancel"), p, function()
    drive.resetConfirm = nil
    drive.valueEpoch = drive.valueEpoch + 1; widget._tuningKeyDirty = true
  end)
end

-- ---------------------------------------------------------------------------
-- The session's parameter choice
-- ---------------------------------------------------------------------------

local PICK_ROWS = 6

--- Pages of at most six rows over the board's groups, in their order.
local function pickerPages(groups)
  local pages = {}
  for index, group in ipairs(groups) do
    for offset = 1, #group.entries, PICK_ROWS do pages[#pages + 1] = { group = index, offset = offset } end
  end
  return pages
end

--- The ground "Choose parameters": everything the board carries, a tap toggles a parameter.
-- Apply keeps the choice for this session only; Save as model default also stores it as the
-- model's flight list. Rebuilt on every toggle and page turn: six rows are a small tree.
local function appendSessionPicker(children, widget, m, w, h, t, p)
  local drive = widget._inflight
  local groups = drive.allGroups or {}
  local pick = drive.sessionPick
  if pick == nil then
    -- Starts from what is offered now: the session's choice, else the model's list, else all.
    local list = Functions.flightList(drive:activeList())
    local any, wanted = next(list) ~= nil, {}
    for _, group in ipairs(groups) do
      for _, entry in ipairs(group.entries) do
        if not any or list[entry.id] then wanted[entry.id] = true end
      end
    end
    pick = { page = 1, wanted = wanted }
    drive.sessionPick = pick
  end
  local pages = pickerPages(groups)
  if pick.page > #pages then pick.page = math.max(1, #pages) end
  local page = pages[pick.page]
  local function refresh()
    drive.valueEpoch = drive.valueEpoch + 1
    widget._tuningKeyDirty = true
  end
  local function close()
    drive.sessionPickerOpen, drive.sessionPick = nil, nil
    refresh()
  end
  -- The chosen ids as the flight list stores them: empty when everything is chosen.
  local function stored()
    local ids, all = {}, true
    for _, group in ipairs(groups) do
      for _, entry in ipairs(group.entries) do
        if pick.wanted[entry.id] then ids[#ids + 1] = entry.id else all = false end
      end
    end
    if all then return "" end
    table.sort(ids)
    for i = 1, #ids do ids[i] = tostring(ids[i]) end
    return table.concat(ids, ",")
  end

  local lineW = w - m.pad * 2
  local gap = m.large and 6 or 3
  local selectorH = m.large and 48 or (h > 280 and 36 or 30)
  local actionH = m.large and 48 or (h > 280 and 36 or 30)
  local y = m.headerH + gap
  local arrowW = m.large and 60 or 44
  local title = page and groups[page.group].name or t("widgets.dashboard.inflight_no_parameters", "No driveable parameters")
  if page and #groups[page.group].entries > PICK_ROWS then
    title = title .. " " .. tostring(math.floor((page.offset - 1) / PICK_ROWS) + 1) .. "/"
      .. tostring(math.ceil(#groups[page.group].entries / PICK_ROWS))
  end
  local function turn(delta)
    return function()
      local target = pick.page + delta
      if target >= 1 and target <= #pages then pick.page = target; refresh() end
    end
  end
  children[#children + 1] = { type = "button", x = m.pad, y = y, w = arrowW, h = selectorH, color = p.accent,
    text = "<", textColor = p.text, press = turn(-1) }
  appendCentredLabel(children, m.pad + arrowW, y, lineW - arrowW * 2, selectorH,
    fitText(title, lineW - arrowW * 2, m.font), p.text, m.font, CENTER, m)
  children[#children + 1] = { type = "button", x = w - m.pad - arrowW, y = y, w = arrowW, h = selectorH, color = p.accent,
    text = ">", textColor = p.text, press = turn(1) }
  y = y + selectorH + gap

  local actionY = h - m.pad - actionH
  local rowH = math.min(m.large and 48 or 36, math.floor((actionY - gap - y) / PICK_ROWS))
  if page then
    local entries = groups[page.group].entries
    for i = page.offset, math.min(#entries, page.offset + PICK_ROWS - 1) do
      local entry = entries[i]
      local on = pick.wanted[entry.id] == true
      children[#children + 1] = {
        type = "button", x = m.pad, y = y, w = lineW, h = rowH - 2,
        color = on and p.accent or p.rowFill, textColor = on and p.onAccent or p.text,
        text = fitText((on and "[x] " or "[  ] ") .. entry.name, lineW - 16, m.listFont),
        press = function()
          if pick.wanted[entry.id] then
            -- At least one parameter stays chosen: an empty choice would offer nothing in the air.
            local count = 0
            for _ in pairs(pick.wanted) do count = count + 1 end
            if count <= 1 then return end
            pick.wanted[entry.id] = nil
          else
            pick.wanted[entry.id] = true
          end
          refresh()
        end
      }
      y = y + rowH
    end
  end

  local buttonW = math.floor((lineW - m.pad * 2) / 3)
  appendAction(children, { actionH = actionH, small = m.small, textOff = m.textOff }, m.pad, actionY, buttonW,
    t("widgets.dashboard.inflight_pick_cancel", "Cancel"), p, close)
  appendAction(children, { actionH = actionH, small = m.small, textOff = m.textOff }, m.pad * 2 + buttonW, actionY, buttonW,
    t("widgets.dashboard.inflight_pick_apply", "Apply"), p, function()
      if widget.state and widget.state.armed == true then return end
      drive:setSessionList(stored())
      close()
    end)
  children[#children - 1].color = p.accent
  children[#children].color = p.onAccent
  appendAction(children, { actionH = actionH, small = m.small, textOff = m.textOff }, m.pad * 3 + buttonW * 2, actionY, buttonW,
    t("widgets.dashboard.inflight_pick_save", "Save default"), p, function()
      local list = stored()
      -- Stored on the ground only: the store write goes to the card, and nothing of the overlay's
      -- ground half runs while the model is armed.
      if widget.state and widget.state.armed == true then return end
      drive:setSessionList(list)
      -- Written on the drive's next pass, which then reports the result on the ground surface.
      local session = _G.rfsuite and _G.rfsuite.session
      drive.pendingSave = { list = list, mcu = session and session.mcu_id }
      drive.saveResult = nil
      close()
    end)
end

local function appendRestoreResults(children, widget, m, w, h, t, p)
  local drive = widget._inflight
  local transfer = drive.transfer or {}
  local rows = {}
  for _, kind in ipairs({"pid", "rate", "global"}) do
    for index = 1, kind == "global" and 1 or 6 do
      local result = transfer.results and transfer.results[kind == "global" and "global" or kind .. index]
      if result then
        local name = kind == "global" and t("widgets.dashboard.inflight_global", "Global")
          or (kind == "pid" and "PID " or "RTE ") .. index
        local word = result == "ok" and t("widgets.dashboard.inflight_restore_ok", "Restored and verified")
          or result == "ram_ok" and t("widgets.dashboard.inflight_restore_ram", "Restored, not saved")
          or result == "saved" and t("widgets.dashboard.inflight_restore_saved", "Saved, check pending")
          or result == "not_restored" and t("widgets.dashboard.inflight_not_restored", "Not attempted")
          or M.restoreReason(result, t)
        rows[#rows + 1] = name .. ": " .. word
      end
    end
  end
  local pages = math.max(1, math.ceil(#rows / 5))
  local page = math.min(drive.restoreResultOpen, pages)
  local y, width = m.headerH + m.pad, w - m.pad * 2
  appendLabel(children, m.pad, y, width, t("widgets.dashboard.inflight_restore_results", "Restore results")
    .. " " .. page .. "/" .. pages, p.accent, m.small, LEFT)
  y = y + m.lineH
  if transfer.reason then
    appendLabel(children, m.pad, y, width, fitText(M.restoreReason(transfer.reason, t), width, m.small), p.warn, m.small, LEFT)
    y = y + m.lineH
  end
  for index = (page - 1) * 5 + 1, math.min(#rows, page * 5) do
    appendLabel(children, m.pad, y, width, fitText(rows[index], width, m.small), p.text, m.small, LEFT)
    y = y + m.lineH
  end
  local by = h - m.actionH - m.pad
  local bw = math.floor((width - m.pad * 2) / 3)
  for index, label in ipairs({"<", ">", t("widgets.dashboard.inflight_restore_cancel", "Cancel")}) do
    appendAction(children, m, m.pad + (index - 1) * (bw + m.pad), by, bw, label, p, function()
      if index == 3 then drive.restoreResultOpen = nil
      else drive.restoreResultOpen = math.max(1, math.min(pages, page + (index == 1 and -1 or 1))) end
      drive.valueEpoch = drive.valueEpoch + 1; widget._tuningKeyDirty = true
    end)
  end
end

local function busyStepText(op, original, t, checking)
  local name, kind, index = op.op, op.kind, op.index
  if name == "initial" then
    -- The saved session is validated from the SD card before the first message goes out, a slice
    -- per pass; that is the long wait on this step, and no link is being set up during it.
    if checking then return t("widgets.dashboard.inflight_progress_checking", "Checking the saved session") end
    return t("widgets.dashboard.inflight_progress_connecting", "Reading the active profiles")
  elseif name == "returnSelect" or name == "returnCheck" or name == "returnStatus" then
    return string.format(t("widgets.dashboard.inflight_progress_return", "Back to PID %s / RTE %s"),
      original and original.pid or UNKNOWN_VALUE, original and original.rate or UNKNOWN_VALUE)
  elseif name == "eeprom" or name == "savedStatus" or name == "persistDone" then
    return t("widgets.dashboard.inflight_progress_saving", "Saving on the flight controller")
  end
  if name == "select" or name == "status" or name == "read" then
    if kind == "pid" and index then
      return string.format(t("widgets.dashboard.inflight_progress_pid_read", "PID profile %d: reading values"), index)
    elseif kind == "rate" and index then
      return string.format(t("widgets.dashboard.inflight_progress_rate_read", "Rate profile %d: reading values"), index)
    elseif kind == "global" then
      return t("widgets.dashboard.inflight_progress_global_read", "Global values: reading")
    end
  elseif name == "write" then
    if kind == "pid" and index then
      return string.format(t("widgets.dashboard.inflight_progress_pid_write", "PID profile %d: writing values"), index)
    elseif kind == "rate" and index then
      return string.format(t("widgets.dashboard.inflight_progress_rate_write", "Rate profile %d: writing values"), index)
    elseif kind == "global" then
      return t("widgets.dashboard.inflight_progress_global_write", "Global values: writing values")
    end
  elseif name == "verify" or name == "persistVerify" then
    if kind == "pid" and index then
      return string.format(t("widgets.dashboard.inflight_progress_pid_check", "PID profile %d: checking values"), index)
    elseif kind == "rate" and index then
      return string.format(t("widgets.dashboard.inflight_progress_rate_check", "Rate profile %d: checking values"), index)
    elseif kind == "global" then
      return t("widgets.dashboard.inflight_progress_global_check", "Global values: checking values")
    end
  end
end

-- Hide both the button and its separate caption when the action is unavailable.
local function appendBusyAction(children, m, x, y, width, label, p, active, press)
  appendAction(children, m, x, y, width, label, p, press)
  children[#children - 1].active = active
  children[#children - 1].visible = active
  children[#children].visible = active
end

-- Zone and fullscreen draw the same busy surface; only fullscreen has the two actions.
appendBusy = function(children, widget, m, w, h, t, p, interactive)
  local drive = widget._inflight
  local job = drive.profileJob
  local restoring = drive.transfer and drive.transfer.state == "busy" and drive.transfer.kind == "restore"
  local title = restoring and t("widgets.dashboard.inflight_progress_restoring", "Restoring")
    or t("widgets.dashboard.inflight_prime_running", "Reading")
  local width = w - m.pad * 2
  local barY = m.chipY + math.max(m.statusLineH, fontHeight(m.nameFont) + m.pad)
  local barH = math.max(3, math.floor(m.statusLineH / 3))
  local stepY = barY + barH + m.pad
  local actionY = h - m.actionH - m.pad
  appendLabel(children, m.pad, m.chipY, width, title, p.accent, m.nameFont, LEFT)
  children[#children + 1] = {
    type = "rectangle", x = m.pad, y = barY, w = width, h = barH, color = p.border, filled = true
  }
  children[#children + 1] = {
    type = "rectangle", x = m.pad, y = barY, w = 0, h = barH, color = p.accent, filled = true,
    size = function()
      local total = #job.plan
      if total == 0 then return 0, barH end
      local done = math.max(0, math.min(total, (job.at or 1) - 1))
      return math.floor(width * done / total), barH
    end
  }
  local stepFormat = t("widgets.dashboard.inflight_progress_step", "Step %d of %d")
  local lastAt, lastTotal, stepText
  appendLabel(children, m.pad, stepY, width, function()
    local total = #job.plan
    local at = math.max(0, math.min(total, job.at or 1))
    if at ~= lastAt or total ~= lastTotal then
      lastAt, lastTotal, stepText = at, total, string.format(stepFormat, at, total)
    end
    return stepText
  end, p.dim, m.small, LEFT)
  local lastOp, lastKind, lastIndex, lastChecking, progress
  appendLabel(children, m.pad, stepY + m.statusLineH, width, function()
    local op = job.plan[job.at]
    local name, kind, index = op and op.op, op and op.kind, op and op.index
    local checking = job.recovery ~= nil or job.validation ~= nil
    if name ~= lastOp or kind ~= lastKind or index ~= lastIndex or checking ~= lastChecking then
      if op then progress = busyStepText(op, job.original, t, checking) or progress end
      lastOp, lastKind, lastIndex, lastChecking = name, kind, index, checking
    end
    return progress or ""
  end, p.text, m.listFont, LEFT)
  -- Reserve the warning row even while the return is proceeding normally.
  local lastError, warning
  appendLabel(children, m.pad, stepY + m.statusLineH * 2, width, function()
    if not job.returnBlocked then return "" end
    if warning == nil or job.error ~= lastError then
      lastError, warning = job.error, fitText(M.restoreReason(job.error, t), width, m.small)
    end
    return warning
  end, p.warn, m.small, LEFT)
  if not interactive then return end
  local retryActive = function() return drive.profileJob == job and job.returnBlocked == true end
  appendBusyAction(children, m, m.pad, actionY, width,
    t("widgets.dashboard.inflight_read_again", "Read again"), p, retryActive, function()
      if drive.profileJob == job and job.returnBlocked then
        prime().retryReturn(drive)
        widget._tuningKeyDirty = true
      end
    end)
  -- Only a READ may be cancelled, and only while it is reading: a restore stopped between its
  -- writes would leave the board holding some restored values in RAM and some not, and the return
  -- to the original profiles always runs to its end.
  local CANCELLABLE = { initial = true, select = true, status = true, read = true, targetDone = true }
  local cancelActive = function()
    if drive.profileJob ~= job or job.returnBlocked or restoring then return false end
    local op = job.plan[job.at]
    return op ~= nil and CANCELLABLE[op.op] == true
  end
  appendBusyAction(children, m, m.pad, actionY, width,
    t("widgets.dashboard.inflight_restore_cancel", "Cancel"), p, cancelActive, function()
      if cancelActive() then job.cancelled = true end
    end)
end

--- The overlay with its controls. Reached by a long press while the interlock is on, and from the
-- quick settings menu while it is off -- there the drive is inert and what is shown instead is
-- the ground surface.
function M.buildFullscreen(children, widget)
  widget._inflightReverseNode = nil
  widget._inflightSensor = nil
  local w = (widget.zone and widget.zone.w) or LCD_W or 480
  local h = (widget.zone and widget.zone.h) or LCD_H or 272
  local t = translator(widget)
  local p = palette()
  local m = metrics(w, h, true)

  children[#children + 1] = { type = "rectangle", x = 0, y = 0, w = w, h = h, color = p.bg, filled = true }
  local early = widget.state.inflight or {}
  -- In the air there is no Close: one tap in the header must not end the tuning.
  local flying = early.live == true and early.phase == "live"
    and not (widget._inflight and (widget._inflight.restoreResultOpen or widget._inflight.restoreConfirm))
  appendHeader(children, widget, m, w, t, p, flying and 0 or closeWidth(m))

  -- The same three phases the zone screen picks between, with the touch controls added. Reached
  -- from the quick settings menu as well, with the interlock OFF: there the drive is inert, the
  -- phase is nil, and what stands is the ground surface -- which is exactly right, because the
  -- ground actions are the only ones that could do anything without an interlock.
  local snapshot = widget.state.inflight or {}
  if widget._inflight and widget._inflight.fcSetupOpen and widget.state.armed ~= true then
    local surface = widget._inflight.fcSurface
    if surface then surface.build(children, widget, m, w, h, t, p, appendLabel, appendAction, wrapSetup) end
    return
  end
  if widget._inflight and widget._inflight.profileJob and snapshot.phase ~= "live" then
    appendBusy(children, widget, m, w, h, t, p, true)
    appendClose(children, widget, m, w, p)
    return
  end
  if widget._inflight and widget._inflight.restoreResultOpen then
    appendRestoreResults(children, widget, m, w, h, t, p)
    return
  end
  if widget._inflight and widget._inflight.restoreConfirm then
    appendRestoreConfirmation(children, widget, m, w, t, p)
    return
  end
  if widget._inflight and widget._inflight.resetConfirm then
    appendResetConfirmation(children, widget, m, w, t, p)
    return
  end
  if widget._inflight and widget._inflight.sessionPickerOpen and snapshot.phase ~= "live" then
    appendSessionPicker(children, widget, m, w, h, t, p)
    return
  end
  if snapshot.phase == "post" then
    M.buildPost(children, widget, m, w, h, t, p, true)
    appendClose(children, widget, m, w, p)
    return
  end
  if snapshot.live ~= true or snapshot.phase ~= "live" then
    M.buildGround(children, widget, m, w, h, t, p, true)
    appendClose(children, widget, m, w, p)
    return
  end

  -- No setup verdict on the LIVE surface. It is a sentence about a model that cannot change while
  -- the pilot is flying it, it belongs to the ground surface where he can act on it, and on the
  -- shortest radio the line it needed was the line the parameter name was drawn on.
  appendFlight(children, widget, m, w, h, t, p, true)
  if widget._inflightReverseNode then children[#children + 1] = widget._inflightReverseNode end
end

M.ready = Input.ready
M.renderKey = Input.renderKey

return M
