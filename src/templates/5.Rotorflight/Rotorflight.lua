-- Fired once, right after a model is created from the Rotorflight template.
--
-- EdgeTX runs the script that sits beside a template's yml as a standalone script the moment
-- the template is applied (gui/colorlcd/model/model_select.cpp, the "wizard Lua script" hook).
-- The yml has already delivered everything no script can set later -- the ARM function switch,
-- the warnings, the static reference channels, the dashboard. What is still open is the
-- pilot's half: WHICH switch carries which function. That is asked here, the way a radio asks
-- best -- the pilot moves the switch -- and written in the shape of the reference models this
-- template is derived from: plain lines at full weight, active low, the hold as a MAX line
-- gated by the one position the pilot names. Only the hold asks for a position at all; every
-- other question is settled by naming the switch, because the reference construction encodes
-- the rest as convention.
--
-- The setup assistant asks its own position questions later, against a connected flight
-- controller and with a read-back to prove them -- this wizard deliberately stops at the
-- reference-model shape a pilot could also have built by hand.
--
-- Plain lcd drawing and plain English on purpose: a standalone script runs outside the suite,
-- so none of its i18n or UI helpers exist here.

local RADIO_MODULE = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/setup_wizard/radio.lua"

local R = nil          -- the assistant's radio-side module, loaded below
local loadError = nil

-- The questions. `kind` decides what a moved switch answers: the SWITCH (any movement names
-- it, whatever the position -- the reference lines carry the whole travel), or one POSITION
-- (the hold gate, which is the single place the reference construction stores a position).
-- `min` is the position count the function needs: the governor and the profiles carry three
-- values across the travel, arming and rescue work on two or three (the reference arms on a
-- three-position switch, low position armed).
--
-- The arming prompt NAMES the prepared switch, because the preparation cannot follow the
-- answer: the yml gave SW1 the ARM name and its colours, and no script can move them.
local QUESTIONS = {
  { key = "arm", kind = "switch", min = 2,
    title = "Arming",
    prompt = "Move the switch that should arm the flight controller. "
      .. "SW1 is prepared for it: named ARM, red while armed." },
  { key = "hold", kind = "position", min = 2,
    title = "Throttle hold",
    prompt = "Move the hold switch to the position where the motor is LOCKED." },
  { key = "gov", kind = "switch", min = 3,
    title = "Governor",
    prompt = "Move the governor switch. It needs three positions: off, spool-up, flight." },
  { key = "profile", kind = "switch", min = 3,
    title = "Profiles",
    prompt = "Move the switch that selects the three profiles." },
  { key = "rescue", kind = "switch", min = 2,
    title = "Rescue",
    prompt = "Move the switch that triggers rescue." }
}

local step = 1          -- 1..#QUESTIONS, then the write, then the closing screen
local answers = {}      -- key -> swsrc (a switch's first position, or the hold position)
local candidate = nil   -- what the last switch movement proposes for the current question
local rejection = nil   -- why the candidate cannot be taken, said in words
local written = nil     -- per-channel results of the write, once it ran
local rest = {}         -- switch number -> the position it was last seen resting in

-- Watch every switch and answer with the one the pilot moves. The baseline is where each
-- switch rested when last looked at; a switch whose active position changed is the answer to
-- the question on screen. Deliberately not a picker: moving the real switch is the one gesture
-- that cannot name the wrong hardware.
local function watchSwitches()
  local moved = nil
  for _, sw in ipairs(R.switches(2)) do
    local number = R.switchNumber(sw.swsrc)
    local position = R.activePosition(sw.swsrc)
    if position ~= nil then
      if rest[number] ~= nil and rest[number] ~= position then
        moved = sw.swsrc + position
      end
      rest[number] = position
    end
  end
  return moved
end

local function considerCandidate(question, moved)
  local positions = R.switchPositionCount(moved) or 0
  if positions < question.min then
    -- A switch that cannot carry the function replaces NOTHING: a valid candidate already on
    -- screen survives a stray movement, and the shortfall is said beneath it instead.
    rejection = "That switch has " .. tostring(positions) .. " positions; this function needs "
      .. tostring(question.min) .. "."
    return
  end
  rejection = nil
  if question.kind == "switch" then
    candidate = R.firstPositionOf(moved)
  else
    candidate = moved
  end
end

-- ---------------------------------------------------------------------------------------------
-- The write: the REFERENCE construction, with the pilot's switches in it.
--
--   input Arm   <arm switch>  +100                   -> CH5 "Arming"
--   input Thr   MAX -100 gated by the hold position,
--               then <governor> +100  ("Hold"/"GOV") -> CH6 "Thr"
--   input Prof  <profile switch> +100                -> CH7 "Prof"
--   input Res   <rescue switch>  +100 ("Rescue")     -> CH8 "Rescue"
--
-- Expo lines are alternatives: the first line whose gate matches wins, so the hold line rules
-- exactly one position and every other position carries the governor -- the reference's own
-- trick, and the reason the hold is the one position asked for. Active is LOW throughout,
-- as both reference models have it. The assistant recognises the plain lines and re-asks
-- what it cannot read when it later walks the flight-controller half.
-- ---------------------------------------------------------------------------------------------

local function sourceByName(name)
  local id = getSourceIndex ~= nil and getSourceIndex(name) or nil
  if id ~= nil then return tonumber(id) end
  local info = getFieldInfo ~= nil and getFieldInfo(name) or nil
  if type(info) == "table" and info.id ~= nil then return tonumber(info.id) end
  return nil
end

local function clearInput(index)
  for _ = 1, (model.getInputsCount(index) or 0) do
    model.deleteInput(index, 0)
  end
end

local function putLine(index, lineNo, inputName, source, weight, gate, lineName)
  model.insertInput(index, lineNo, {
    name = lineName or "",
    inputName = inputName,
    source = source,
    weight = weight,
    offset = 0,
    switch = gate or 0,
    curveType = 0,
    curveValue = 0,
    scale = 0,
    side = 3,
    trimSource = R.TRIM_OFF,
    flightModes = 0
  })
end

local function wire(channel, input, channelName)
  if not R.clearChannel(channel) then return false, "clear_failed" end
  local ok = pcall(model.insertMix, channel - 1, 0, {
    source = R.inputSource(input),
    weight = 100,
    offset = 0,
    switch = 0,
    multiplex = 0,
    curveType = 0,
    curveValue = 0,
    flightModes = 0
  })
  if not ok then return false, "insert_failed" end
  R.setChannelName(channel, channelName)
  return true
end

local function writeAnswers()
  written = {}
  local maxSource = sourceByName("MAX")

  local function record(channel, name, ok, err)
    written[#written + 1] = { channel = channel, name = name, ok = ok and true or false, err = err }
  end

  local function simple(channel, input, inputName, channelName, swsrc, lineName)
    local source = R.switchSource(swsrc)
    if source == nil then record(channel, channelName, false, "no_source") return end
    clearInput(input)
    local okLine = pcall(putLine, input, 0, inputName, source, 100, 0, lineName)
    if not okLine then record(channel, channelName, false, "input_failed") return end
    local ok, err = wire(channel, input, channelName)
    record(channel, channelName, ok, err)
  end

  simple(5, 4, "Arm", "Arming", answers.arm)

  -- The throttle input, two alternative lines: the hold rules its one position, the governor
  -- carries every other.
  local govSource = R.switchSource(answers.gov)
  if maxSource == nil or govSource == nil then
    record(6, "Thr", false, maxSource == nil and "no_max" or "no_source")
  else
    clearInput(5)
    local okHold = pcall(putLine, 5, 0, "Thr", maxSource, -100, answers.hold, "Hold")
    local okGov = okHold and pcall(putLine, 5, 1, "Thr", govSource, 100, 0, "GOV")
    if not (okHold and okGov) then
      record(6, "Thr", false, "input_failed")
    else
      local ok, err = wire(6, 5, "Thr")
      record(6, "Thr", ok, err)
    end
  end

  simple(7, 6, "Prof", "Prof", answers.profile, "Prof")
  simple(8, 7, "Res", "Rescue", answers.rescue, "Rescue")
end

local function positionWord(swsrc)
  local words = { [0] = "up", [1] = "middle", [2] = "down" }
  return words[R.switchPosition(swsrc)] or "?"
end

local function switchLabel(swsrc)
  return R.switchBaseName(swsrc) or tostring(swsrc)
end

-- Does the arming answer sit on a function switch OTHER than the one the template prepared?
-- The name and the colours cannot be moved by any script -- that gap is why this template
-- exists -- so the one honest thing to do is say so.
local function armNamingHint()
  if answers.arm == nil then return nil end
  local base = R.switchBaseName(answers.arm)
  if type(base) == "string" and string.sub(base, 1, 2) == "SW" and base ~= "SW1" then
    return "SW1 carries the ARM name and colours; move them to " .. base ..
      " by hand (Model setup, function switches)."
  end
  return nil
end

-- ---------------------------------------------------------------------------------------------
-- Drawing. Plain lcd calls, arranged rather than listed: a dark header naming the wizard and
-- the step, the question at reading size, the candidate in a box of its own so the thing that
-- will be taken is the thing the eye is on, and the actions as BUTTONS at the bottom edge --
-- tappable on a touch radio, mirrored on ENTER and RTN everywhere. Colours come from the
-- radio's own theme where the constants exist and fall back to plain drawing where they do
-- not -- a standalone script cannot assume a theme.
-- ---------------------------------------------------------------------------------------------

local COL_HEADER = COLOR_THEME_SECONDARY1 or BLACK or 0
local COL_HEADER_TEXT = COLOR_THEME_PRIMARY2 or WHITE or 0
local COL_TEXT = COLOR_THEME_PRIMARY1 or BLACK or 0
local COL_BOX = COLOR_THEME_FOCUS or BLACK or 0

local function screenWidth() return LCD_W or 480 end
local function screenHeight() return LCD_H or 320 end

local function textWidth(text, flags)
  if lcd.sizeText ~= nil then
    local w = lcd.sizeText(text, flags or 0)
    if type(w) == "number" then return w end
  end
  return #text * 8
end

local function centered(y, text, flags)
  lcd.drawText(math.floor((screenWidth() - textWidth(text, flags)) / 2), y, text, flags or 0)
end

-- Greedy wrap against the real text width, so a sentence survives every screen size the
-- template may meet.
local function wrapped(x, y, width, text, flags, lineH)
  local line = ""
  for word in string.gmatch(text, "%S+") do
    local candidateLine = line == "" and word or (line .. " " .. word)
    if textWidth(candidateLine, flags) > width and line ~= "" then
      lcd.drawText(x, y, line, flags)
      y = y + lineH
      line = word
    else
      line = candidateLine
    end
  end
  if line ~= "" then
    lcd.drawText(x, y, line, flags)
    y = y + lineH
  end
  return y
end

local function drawFrame(title, right)
  lcd.clear()
  lcd.drawFilledRectangle(0, 0, screenWidth(), 36, COL_HEADER)
  lcd.drawText(10, 8, title, COL_HEADER_TEXT + (BOLD or 0))
  if right ~= nil then
    lcd.drawText(screenWidth() - 10 - textWidth(right, 0), 8, right, COL_HEADER_TEXT)
  end
end

-- The two actions as drawn buttons, remembered for the tap test. A touch radio taps them; the
-- keys do the same thing everywhere, and the labels say so.
local buttons = {}

local function drawButtons(leftLabel, rightLabel)
  buttons = {}
  local h = 30
  local y = screenHeight() - h - 6
  if leftLabel ~= nil then
    local w = textWidth(leftLabel, 0) + 24
    lcd.drawRectangle(10, y, w, h, COL_BOX)
    lcd.drawText(22, y + 7, leftLabel, COL_TEXT)
    buttons.left = { x = 10, y = y, w = w, h = h }
  end
  if rightLabel ~= nil then
    local w = textWidth(rightLabel, 0) + 24
    local x = screenWidth() - 10 - w
    lcd.drawFilledRectangle(x, y, w, h, COL_HEADER)
    lcd.drawText(x + 12, y + 7, rightLabel, COL_HEADER_TEXT + (BOLD or 0))
    buttons.right = { x = x, y = y, w = w, h = h }
  end
end

local function tapped(box, touch)
  return box ~= nil and touch ~= nil and touch.x ~= nil
    and touch.x >= box.x and touch.x <= box.x + box.w
    and touch.y >= box.y and touch.y <= box.y + box.h
end

local function drawQuestion(question, stepText)
  drawFrame("Rotorflight", stepText)
  local x = 14
  local w = screenWidth() - 2 * x
  local y = 50
  lcd.drawText(x, y, question.title, COL_TEXT + (MIDSIZE or 0) + (BOLD or 0))
  y = y + 34
  y = wrapped(x, y, w, question.prompt, COL_TEXT, 20)

  -- The candidate box: what will be taken, or the invitation to move something; a refusal is
  -- said BENEATH the box and leaves a valid candidate standing.
  local boxY = y + 12
  local boxH = 56
  lcd.drawRectangle(x, boxY, w, boxH, COL_BOX)
  if candidate ~= nil then
    local label = switchLabel(candidate)
    if question.kind == "position" then
      label = label .. "  " .. positionWord(candidate)
    end
    centered(boxY + 8, label, COL_TEXT + (DBLSIZE or MIDSIZE or 0) + (BOLD or 0))
  else
    centered(boxY + math.floor((boxH - 16) / 2), "move a switch...", COL_TEXT)
  end
  if rejection ~= nil then
    wrapped(x, boxY + boxH + 4, w, rejection, COL_TEXT, 18)
  end

  drawButtons(step == 1 and "RTN  leave" or "RTN  back",
              candidate ~= nil and "ENTER  take it" or nil)
end

local function drawLines(lines)
  lcd.clear()
  local x = math.floor(screenWidth() / 14)
  local y = 10
  for i = 1, #lines do
    if lines[i] ~= "" then
      lcd.drawText(x, y, lines[i], COL_TEXT)
    end
    y = y + 18
  end
end

local function init()
end

local function run(event, touch)
  -- Without the suite there is no radio module to borrow, and half a wizard would leave half
  -- a layout. The template's yml part is already in the model either way.
  if R == nil then
    if loadError == nil then
      local chunk = loadScript(RADIO_MODULE, "t")
      if type(chunk) == "function" then
        local ok, mod = pcall(chunk)
        if ok and type(mod) == "table" then R = mod else loadError = "load" end
      else
        loadError = "missing"
      end
    end
    if R == nil then
      if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then return 1 end
      drawLines({
        "Model created from the Rotorflight template.",
        "",
        "RFSuite is not installed on this card, so the",
        "switch questions cannot be asked here.",
        "The ARM switch, warnings and dashboard are",
        "already in the model.",
        "",
        "Press RTN to close."
      })
      return 0
    end
  end

  local isTap = EVT_TOUCH_TAP ~= nil and event == EVT_TOUCH_TAP
  local question = QUESTIONS[step]

  if question ~= nil then
    local takeIt = event == EVT_VIRTUAL_ENTER or (isTap and tapped(buttons.right, touch))
    local goBack = event == EVT_VIRTUAL_EXIT or (isTap and tapped(buttons.left, touch))

    if goBack then
      -- Back walks the questions; leaving is only offered at the first one. Nothing has been
      -- written yet, so leaving early costs nothing but the answers given so far.
      if step == 1 then return 1 end
      step = step - 1
      answers[QUESTIONS[step].key] = nil
      candidate, rejection = nil, nil
      return 0
    end
    if takeIt and candidate ~= nil then
      answers[question.key] = candidate
      candidate, rejection = nil, nil
      step = step + 1
      if QUESTIONS[step] == nil then writeAnswers() end
      return 0
    end

    local moved = watchSwitches()
    if moved ~= nil then considerCandidate(question, moved) end

    drawQuestion(question, tostring(step) .. " / " .. tostring(#QUESTIONS))
    return 0
  end

  -- The closing screen: what was written, and where the other half happens.
  if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER
     or (isTap and tapped(buttons.right, touch)) then
    return 1
  end
  drawFrame("Rotorflight", "done")
  local x = 14
  local w = screenWidth() - 2 * x
  local y = 44
  for _, result in ipairs(written or {}) do
    local mark = result.ok and "ok" or ("FAILED: " .. tostring(result.err))
    lcd.drawText(x, y, "CH" .. tostring(result.channel), COL_TEXT + (BOLD or 0))
    lcd.drawText(x + 52, y, tostring(result.name), COL_TEXT)
    lcd.drawText(x + 150, y, mark, COL_TEXT + (result.ok and 0 or (BOLD or 0)))
    y = y + 20
  end
  y = y + 6
  local hint = armNamingHint()
  if hint ~= nil then
    y = wrapped(x, y, w, hint, COL_TEXT, 18) + 4
  end
  y = wrapped(x, y, w, "Next: connect the flight controller and run the setup assistant "
    .. "(SYS > Tools > RFSuite > Configuration > Wizards). It reads this layout back and "
    .. "sets the flight controller to match.", COL_TEXT, 18)
  drawButtons(nil, "RTN  close")
  return 0
end

return { init = init, run = run }
