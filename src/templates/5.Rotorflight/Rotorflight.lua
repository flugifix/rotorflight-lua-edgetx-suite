-- Shown once, right after a model is created from the Rotorflight template.
--
-- EdgeTX fires the script that sits beside a template's yml as a standalone script the moment
-- the template is applied (gui/colorlcd/model/model_select.cpp, the "wizard Lua script" hook).
-- Everything structural is already in the model at that point -- the template's yml carried it --
-- so this script only has to say what the pilot has and what comes next. It deliberately does
-- not reach for the suite: at model creation there is usually no powered flight controller, and
-- the suite's own entry point guards that case far better than a wizard could.
--
-- Plain lcd drawing on purpose: a standalone script runs outside the suite, so none of the
-- suite's i18n or UI helpers exist here, and the classic API works on every colour radio.

local lines = {
  "Model created from the Rotorflight template.",
  "",
  "Already set up for you:",
  "  - ARM function switch, red while armed",
  "  - switch warnings, throttle warning off",
  "  - flight timer (runs while hold is off)",
  "  - RFSuite dashboard as the main view",
  "",
  "Next: connect the flight controller, then run",
  "the setup assistant:",
  "  SYS > Tools > RFSuite",
  "  > Configuration > Wizards",
  "",
  "Press RTN to close."
}

local function init()
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER then
    return 1
  end

  lcd.clear()

  local width = LCD_W or 480
  local x = math.floor(width / 12)
  local y = 12
  for i = 1, #lines do
    if lines[i] ~= "" then
      lcd.drawText(x, y, lines[i], 0)
    end
    y = y + 18
  end

  return 0
end

return { init = init, run = run }
