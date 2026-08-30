-- Fired once, right after a model is created from the Rotorflight template.
--
-- EdgeTX runs the script that sits beside a template's yml as a standalone script the moment
-- the template is applied (gui/colorlcd/model/model_select.cpp, the "wizard Lua script" hook).
-- The yml has already delivered everything no script can set later -- the ARM function switch,
-- the warnings, the timers, the dashboard. What is still open is the pilot's half: WHICH switch
-- carries which function, and which of its positions means what. That is asked here, the way a
-- radio asks best -- the pilot MOVES the switch into the meant position -- and written with the
-- setup assistant's own construction code, loaded from the suite, so the assistant recognises
-- the layout on its next run and only derives the flight controller's half from it.
--
-- Plain lcd drawing and plain English on purpose: a standalone script runs outside the suite,
-- so none of its i18n or UI helpers exist here.

local RADIO_MODULE = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/setup_wizard/radio.lua"

local R = nil          -- the assistant's radio-side module, loaded below
local loadError = nil

-- The questions, in the order the assistant walks the same channels. `kind` decides what a
-- moved switch answers: a POSITION (the moved-to position is the answer) or a whole SWITCH
-- (the profile channel, whose three positions are all spoken for).
local QUESTIONS = {
  { key = "arm", channel = 5, kind = "position", exact = 2,
    title = "Arming",
    prompt = "Move the switch to the position that should ARM." },
  { key = "hold", channel = 6, kind = "position",
    title = "Throttle hold",
    prompt = "Move the hold switch to the position where the motor may run." },
  { key = "gov", channel = 6, kind = "position", noMiddle = true,
    title = "Governor",
    prompt = "Move the governor switch to the position where the motor is OFF." },
  { key = "profile", channel = 7, kind = "switch", need = 3,
    title = "Profiles",
    prompt = "Move the switch that selects the three profiles." },
  { key = "rescue", channel = 8, kind = "position", exact = 2,
    title = "Rescue",
    prompt = "Move the switch to the position that triggers RESCUE." }
}

local step = 1          -- 1..#QUESTIONS, then the write, then the closing screen
local answers = {}      -- key -> swsrc (a position, or a switch's first position)
local candidate = nil   -- what the last switch movement proposes for the current question
local rejection = nil   -- why the candidate cannot be taken, said in words
local written = nil     -- per-channel results of the write, once it ran
local rest = {}         -- switch number -> the position it was last seen resting in

local function entryFor(channel)
  for _, entry in ipairs(R.CHANNELS) do
    if entry.channel == channel then return entry end
  end
  return nil
end

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
  rejection = nil
  local positions = R.switchPositionCount(moved) or 0
  if question.exact ~= nil and positions ~= question.exact then
    candidate = nil
    rejection = "That switch has " .. tostring(positions) ..
      " positions. This function takes a two-position switch: on, or not."
    return
  end
  if question.need ~= nil and positions < question.need then
    candidate = nil
    rejection = "That switch has " .. tostring(positions) ..
      " positions. The profile channel needs three, one per profile."
    return
  end
  if question.noMiddle and R.switchPosition(moved) == R.POSITION_MIDDLE then
    candidate = nil
    rejection = "The motor cannot be off in the middle position. Pick an end position."
    return
  end
  if question.kind == "switch" then
    candidate = R.firstPositionOf(moved)
  else
    candidate = moved
  end
end

-- The write, in one act after the last answer, with the assistant's own construction
-- functions -- so what lands in the model is byte for byte what the assistant would have
-- written, and its read-back proposes every answer given here.
local function writeAnswers()
  written = {}
  local order = {
    { channel = 5, kind = "condition", swsrc = answers.arm },
    { channel = 6, kind = "throttle", swsrc = answers.hold, gov = answers.gov },
    { channel = 7, kind = "travel", swsrc = answers.profile },
    { channel = 8, kind = "condition", swsrc = answers.rescue }
  }
  for _, action in ipairs(order) do
    local entry = entryFor(action.channel)
    local ok, err
    if entry == nil then
      ok, err = false, "no_entry"
    elseif action.kind == "throttle" then
      ok, err = R.writeThrottleChannel(entry, action.swsrc, action.gov)
    elseif action.kind == "travel" then
      ok, err = R.writeTravelChannel(entry, action.swsrc)
    else
      ok, err = R.writeConditionChannel(entry, action.swsrc)
    end
    written[#written + 1] = {
      channel = action.channel,
      name = entry and entry.channelName or ("CH" .. tostring(action.channel)),
      ok = ok and true or false,
      err = err
    }
  end
end

local function positionLabel(swsrc)
  return R.switchPositionName(swsrc) or tostring(swsrc)
end

local function switchLabel(swsrc)
  return R.switchBaseName(swsrc) or tostring(swsrc)
end

-- ---------------------------------------------------------------------------------------------
-- Drawing. Plain lcd calls, arranged rather than listed: a dark header naming the wizard and
-- the step, the question at reading size, the candidate in a box of its own so the thing ENTER
-- will take is the thing the eye is on, and the key hints at the bottom edge. Colours come from
-- the radio's own theme where the constants exist and fall back to plain drawing where they do
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

local function drawFooter(left, right)
  local y = screenHeight() - 24
  if left ~= nil then
    lcd.drawText(10, y, left, COL_TEXT + (SMLSIZE or 0))
  end
  if right ~= nil then
    lcd.drawText(screenWidth() - 10 - textWidth(right, SMLSIZE or 0), y, right,
      COL_TEXT + (SMLSIZE or 0))
  end
end

local function drawQuestion(question, stepText)
  drawFrame("Rotorflight", stepText)
  local x = 14
  local w = screenWidth() - 2 * x
  local y = 50
  lcd.drawText(x, y, question.title, COL_TEXT + (MIDSIZE or 0) + (BOLD or 0))
  y = y + 34
  y = wrapped(x, y, w, question.prompt, COL_TEXT, 20)

  -- The candidate box: what ENTER will take, or why the last movement was refused, or the
  -- invitation to move something -- one box, three states, so the eye has one place to look.
  local boxY = y + 12
  local boxH = 56
  lcd.drawRectangle(x, boxY, w, boxH, COL_BOX)
  if candidate ~= nil then
    -- The position as a WORD beside the name: the position glyphs live in the small fonts and
    -- silently vanish from the large one, and a candidate whose position cannot be read is
    -- half an answer.
    local label
    if question.kind == "switch" then
      label = switchLabel(candidate)
    else
      local words = { [0] = "up", [1] = "middle", [2] = "down" }
      label = switchLabel(candidate) .. "  " .. (words[R.switchPosition(candidate)] or "?")
    end
    centered(boxY + 8, label, COL_TEXT + (DBLSIZE or MIDSIZE or 0) + (BOLD or 0))
    centered(boxY + boxH + 6, "ENTER takes it", COL_TEXT + (SMLSIZE or 0))
  elseif rejection ~= nil then
    wrapped(x + 10, boxY + 10, w - 20, rejection, COL_TEXT, 18)
  else
    centered(boxY + math.floor((boxH - 16) / 2), "move a switch...", COL_TEXT)
  end

  if step == 1 then
    drawFooter("RTN leaves -- the assistant can ask all of this later", nil)
  else
    drawFooter("RTN goes back one question", nil)
  end
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

local function run(event)
  -- Without the suite there is no construction code to borrow, and half a wizard would leave
  -- half a layout. The template's yml part is already in the model either way.
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
        "The ARM switch, warnings, timers and dashboard",
        "are already in the model.",
        "",
        "Press RTN to close."
      })
      return 0
    end
  end

  local question = QUESTIONS[step]

  if question ~= nil then
    if event == EVT_VIRTUAL_EXIT then
      -- Back walks the questions; leaving is only offered at the first one. Nothing has been
      -- written yet, so leaving early costs nothing but the answers given so far.
      if step == 1 then return 1 end
      step = step - 1
      answers[QUESTIONS[step].key] = nil
      candidate, rejection = nil, nil
      return 0
    end
    if event == EVT_VIRTUAL_ENTER and candidate ~= nil then
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
  if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then return 1 end
  drawFrame("Rotorflight", "done")
  local x = 14
  local w = screenWidth() - 2 * x
  local y = 46
  for _, result in ipairs(written or {}) do
    local mark = result.ok and "ok" or ("FAILED: " .. tostring(result.err))
    lcd.drawText(x, y, "CH" .. tostring(result.channel), COL_TEXT + (BOLD or 0))
    lcd.drawText(x + 52, y, tostring(result.name), COL_TEXT)
    lcd.drawText(x + 150, y, mark, COL_TEXT + (result.ok and 0 or (BOLD or 0)))
    y = y + 20
  end
  y = y + 8
  y = wrapped(x, y, w, "Plus, from the template: ARM function switch, switch warnings, "
    .. "flight timer, dashboard.", COL_TEXT, 18) + 8
  y = wrapped(x, y, w, "Next: connect the flight controller and run the setup assistant "
    .. "(SYS > Tools > RFSuite > Configuration > Wizards). It reads this layout back and "
    .. "sets the flight controller to match.", COL_TEXT, 18)
  drawFooter("put every switch back to its safe position", "RTN closes")
  return 0
end

return { init = init, run = run }
