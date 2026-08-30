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

local function drawLines(lines)
  lcd.clear()
  local x = math.floor((LCD_W or 480) / 14)
  local y = 10
  for i = 1, #lines do
    if lines[i] ~= "" then
      lcd.drawText(x, y, lines[i], 0)
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

    local answerLine = "waiting for a switch..."
    if candidate ~= nil then
      if question.kind == "switch" then
        answerLine = "> " .. switchLabel(candidate) .. "   ENTER = take it"
      else
        answerLine = "> " .. positionLabel(candidate) .. "   ENTER = take it"
      end
    elseif rejection ~= nil then
      answerLine = rejection
    end

    drawLines({
      "Rotorflight  -  step " .. tostring(step) .. " of " .. tostring(#QUESTIONS) ..
        "  -  " .. question.title,
      "",
      question.prompt,
      "",
      answerLine,
      "",
      step == 1 and "RTN leaves; the assistant can ask all of"
        or "RTN goes back one question.",
      step == 1 and "this later as well." or ""
    })
    return 0
  end

  -- The closing screen: what was written, and where the other half happens.
  if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then return 1 end
  local lines = {
    "Done. This model now carries:",
    ""
  }
  for _, result in ipairs(written or {}) do
    local mark = result.ok and "ok" or ("FAILED: " .. tostring(result.err))
    lines[#lines + 1] = "  CH" .. tostring(result.channel) .. "  " ..
      tostring(result.name) .. "  -  " .. mark
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Plus, from the template: ARM function switch,"
  lines[#lines + 1] = "switch warnings, flight timer, dashboard."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Next: connect the flight controller and run the"
  lines[#lines + 1] = "setup assistant (SYS > Tools > RFSuite >"
  lines[#lines + 1] = "Configuration > Wizards). It reads this layout"
  lines[#lines + 1] = "back and sets the flight controller to match."
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Put every switch back to its safe position,"
  lines[#lines + 1] = "then press RTN to close."
  drawLines(lines)
  return 0
end

return { init = init, run = run }
