-- Fired once, right after a model is created from the Rotorflight template.
--
-- EdgeTX runs the script that sits beside a template's yml as a standalone script the moment
-- the template is applied (gui/colorlcd/model/model_select.cpp, the "wizard Lua script" hook).
-- The yml has already delivered everything no script can set later -- the ARM function switch,
-- the warnings, the static reference channels, the dashboard. What is still open is the
-- pilot's half: WHICH switch carries which function. That is asked with the radio's OWN
-- pickers -- the source picker filtered to switches for the four whole-switch answers, the
-- position picker for the one position the reference construction stores, the hold gate --
-- and written in the reference models' shape: plain lines at full weight, active low, the
-- hold as a MAX line gated by the named position, the governor beneath it.
--
-- The setup assistant asks its own position questions later, against a connected flight
-- controller and with a read-back to prove them -- this wizard deliberately stops at the
-- reference-model shape a pilot could also have built by hand.
--
-- Plain English on purpose: a standalone script runs outside the suite, so none of its i18n
-- helpers exist here.

local RADIO_MODULE = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/setup_wizard/radio.lua"

local R = nil          -- the assistant's radio-side module, loaded below
local loadError = nil

-- The five rows. `whole` answers with a SWITCH through the radio's source picker (any of its
-- positions may carry the function -- the reference encodes the rest as convention, active
-- low); the hold row answers with the one POSITION the reference construction stores. `min`
-- is the position count the function needs: governor and profiles carry three values across
-- the travel, arming and rescue work on two or three (the reference arms on a three-position
-- switch).
local ROWS = {
  { key = "arm", whole = true, min = 2, label = "Arming switch" },
  { key = "hold", whole = false, label = "Hold: motor LOCKED at" },
  { key = "gov", whole = true, min = 3, label = "Governor switch (3 pos)" },
  { key = "profile", whole = true, min = 3, label = "Profile switch (3 pos)" },
  { key = "rescue", whole = true, min = 2, label = "Rescue switch" }
}

local answers = {}      -- key -> swsrc: a switch's first position, or the hold position
local message = nil     -- what stands between the pilot and the Create button, in words
local written = nil     -- per-channel results of the write, once it ran
local view = nil        -- nil (not built) | "form" | "done"

-- ---------------------------------------------------------------------------------------------
-- The write: the REFERENCE construction, with the pilot's switches in it.
--
--   input Arm   <arm switch>  +100                   -> CH5 "Arming"
--   input Thr   MAX -100 gated by the hold position,
--               then <governor> +100  ("Hold"/"GOV") -> CH6 "Thr"
--   input Prof  <profile switch> +100 ("Prof")       -> CH7 "Prof"
--   input Res   <rescue switch>  +100 ("Rescue")     -> CH8 "Rescue"
--
-- Expo lines are alternatives: the first line whose gate matches wins, so the hold line rules
-- exactly one position and every other position carries the governor -- the reference's own
-- trick, and the reason the hold is the one position asked for. Active is LOW throughout, as
-- both reference models have it. The assistant recognises the plain lines and re-asks what it
-- cannot read when it later walks the flight-controller half.
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

-- What still stands between the pilot and the write, in one sentence -- or nil, which is what
-- lets the button act.
local function firstProblem()
  for _, row in ipairs(ROWS) do
    local value = answers[row.key]
    if value == nil or value == 0 then
      return row.label .. ": nothing chosen yet."
    end
    if row.min ~= nil then
      local positions = R.switchPositionCount(value) or 0
      if positions < row.min then
        return row.label .. ": that switch has " .. tostring(positions) ..
          " positions, " .. tostring(row.min) .. " are needed."
      end
    end
  end
  return nil
end


-- ---------------------------------------------------------------------------------------------
-- The form, out of the radio's own controls -- the same child tables the suite hands to
-- lvgl.build, source pickers without a `title` (the picker class does not carry the property
-- and raises on it).
-- ---------------------------------------------------------------------------------------------

local COL_TEXT = COLOR_THEME_PRIMARY1 or BLACK or 0

-- The picker filters. The bit values are the firmware's own (dataconstants.h); the source
-- filter is taken from the lvgl module where it exists, because that registered constant
-- already includes the function-switch bit -- the switches this template cares most about.
local SRC_SWITCH_FILTER = (lvgl ~= nil and lvgl.SRC_SWITCH) or 0xFFFFFFFF
local SW_SWITCH = 1
local SW_NONE = 1 << 20

local W = LCD_W or 480
local ROW_H = 36
local PICKER_W = 190
local LEFT = 12

local function sourceRow(children, y, row)
  children[#children + 1] = {
    type = "label", x = LEFT, y = y + 8, w = W - PICKER_W - 2 * LEFT - 8,
    text = row.label, color = COL_TEXT
  }
  children[#children + 1] = {
    type = "source",
    x = W - PICKER_W - LEFT, y = y + 2, w = PICKER_W, h = ROW_H - 6,
    filter = SRC_SWITCH_FILTER,
    get = function()
      local picked = answers[row.key]
      if picked == nil or picked == 0 then return 0 end
      return R.switchSource(picked) or 0
    end,
    set = function(value)
      answers[row.key] = R.switchFromSource(value) or 0
    end
  }
end

local function positionRow(children, y, row)
  children[#children + 1] = {
    type = "label", x = LEFT, y = y + 8, w = W - PICKER_W - 2 * LEFT - 8,
    text = row.label, color = COL_TEXT
  }
  children[#children + 1] = {
    type = "switch",
    x = W - PICKER_W - LEFT, y = y + 2, w = PICKER_W, h = ROW_H - 6,
    filter = SW_SWITCH | SW_NONE,
    get = function() return answers[row.key] or 0 end,
    set = function(value) answers[row.key] = tonumber(value) or 0 end
  }
end

local function buildForm()
  lvgl.clear()
  local children = {}
  children[#children + 1] = {
    type = "label", x = LEFT, y = 6, w = W - 2 * LEFT,
    text = "Rotorflight - pick your switches", color = COL_TEXT
  }
  local y = 34
  for _, row in ipairs(ROWS) do
    if row.whole then sourceRow(children, y, row) else positionRow(children, y, row) end
    y = y + ROW_H
  end

  -- The one sentence that stands between the pilot and the button; the button's press
  -- rebuilds this form, which is what puts the sentence on screen.
  if message ~= nil then
    children[#children + 1] = {
      type = "label", x = LEFT, y = y + 4, w = W - 2 * LEFT,
      color = COL_TEXT, text = message
    }
  end

  children[#children + 1] = {
    type = "button", x = LEFT, y = y + 30, w = 200, h = 34,
    text = "Create switch setup",
    press = function()
      message = firstProblem()
      -- Either way the view is rebuilt: with the write done it becomes the closing screen,
      -- with a problem it comes back carrying the sentence -- a live label alone stayed
      -- blank here, and a refusal nobody can read is a button that does nothing.
      if message == nil then writeAnswers() end
      view = nil
    end
  }
  children[#children + 1] = {
    type = "label", x = LEFT + 212, y = y + 38, w = W - LEFT - 212,
    text = "RTN skips this - the assistant can ask later", color = COL_TEXT
  }
  lvgl.build(children)
end

local function buildDone()
  lvgl.clear()
  local children = {}
  children[#children + 1] = {
    type = "label", x = LEFT, y = 6, w = W - 2 * LEFT,
    text = "Rotorflight - done", color = COL_TEXT
  }
  local y = 32
  for _, result in ipairs(written or {}) do
    children[#children + 1] = {
      type = "label", x = LEFT, y = y, w = W - 2 * LEFT, color = COL_TEXT,
      text = "CH" .. tostring(result.channel) .. "  " .. tostring(result.name) .. "  -  "
        .. (result.ok and "ok" or ("FAILED: " .. tostring(result.err)))
    }
    y = y + 20
  end
  y = y + 6
  children[#children + 1] = {
    type = "label", x = LEFT, y = y, w = W - 2 * LEFT, color = COL_TEXT,
    text = "Next: connect the flight controller and run the setup assistant"
  }
  children[#children + 1] = {
    type = "label", x = LEFT, y = y + 20, w = W - 2 * LEFT, color = COL_TEXT,
    text = "(SYS > Tools > RFSuite > Configuration > Wizards)."
  }
  children[#children + 1] = {
    type = "label", x = LEFT, y = y + 48, w = W - 2 * LEFT,
    text = "RTN closes.", color = COL_TEXT
  }
  lvgl.build(children)
end

local function init()
end

local function run(event)
  if event == EVT_VIRTUAL_EXIT then return 1 end

  -- Without the suite there is no radio module to borrow, and half a wizard would leave half
  -- a layout. The template's yml part is already in the model either way. And without lvgl
  -- there is no picker to offer -- the same honest exit.
  if R == nil then
    if loadError == nil then
      local chunk = loadScript(RADIO_MODULE, "t")
      if type(chunk) == "function" then
        local ok, mod = pcall(chunk)
        if ok and type(mod) == "table" then R = mod else loadError = "load" end
      else
        loadError = "missing"
      end
      if lvgl == nil or type(lvgl.build) ~= "function" then loadError = "no_lvgl" end
      if R ~= nil and loadError == nil and (answers.arm == nil or answers.arm == 0) then
        -- SW1 is the switch the template PREPARED -- named ARM, red while armed -- so it is
        -- the one picker that starts filled. Everything else starts empty: those answers are
        -- not prepared anywhere.
        -- Every function switch arrives identically arm-ready; SW1 is preselected only
        -- because a filled picker is one decision fewer, not because it is special.
        for _, sw in ipairs(R.switches(2)) do
          if sw.name == "SW1" then answers.arm = sw.swsrc break end
        end
      end
    end
    if R == nil or loadError ~= nil then
      if event == EVT_VIRTUAL_ENTER then return 1 end
      if lcd ~= nil and lcd.clear ~= nil then
        lcd.clear()
        lcd.drawText(30, 40, "Model created from the Rotorflight template.", 0)
        lcd.drawText(30, 70, "The switch questions need RFSuite on the card;", 0)
        lcd.drawText(30, 90, "the ARM switch, warnings and dashboard are", 0)
        lcd.drawText(30, 110, "already in the model.", 0)
        lcd.drawText(30, 150, "Press RTN to close.", 0)
      end
      return 0
    end
  end

  if written ~= nil and view ~= "done" then
    buildDone()
    view = "done"
  elseif written == nil and view ~= "form" then
    buildForm()
    view = "form"
  end

  return 0
end

return { init = init, run = run }
