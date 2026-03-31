-- ui/controls.lua
-- Reusable UX control components for LVGL declarative UI.
--
-- All functions append LVGL widget entries to a children table.
-- Row height is ROW_H (44 px). Callers advance cursorY by ROW_H + 1.

local Controls = {}

local ROW_H      = 44  -- total row height (the +1 divider is included in each function)

-- ── SectionHeader ─────────────────────────────────────────────────────────────
-- Collapsible accordion section title with a blue bottom bar (like tile highlight).
--
-- Layout (SECTION_H = 40 px total):
--   y+0            title label     MIDSIZE, COLOR_THEME_PRIMARY1
--   y+27           3 px blue bar   COLOR_THEME_SECONDARY1
--   y+39           1 px divider    GREY_DEFAULT
--
-- Controls.SECTION_H is exported so callers stay in sync.

local SECTION_H            = 48
local SECTION_BAR_H        = 3
local SECTION_ARROW_W      = 30
local SECTION_ARROW_H      = 30

Controls.SECTION_H = SECTION_H

function Controls.appendSectionHeader(children, x, y, w, title, expanded, onToggle)
  -- Title label
  children[#children + 1] = {
    type  = "label",
    x = x, y = y + 4,
    text  = title,
    color = COLOR_THEME_PRIMARY1,
    font  = MIDSIZE
  }

  -- Expand/collapse button (styled chevron control)
  local btnX = x + w - SECTION_ARROW_W
  local btnY = y + 4
  local icon = expanded and "v" or ">"
  children[#children + 1] = {
    type  = "button",
    x = btnX,
    y = btnY,
    w = SECTION_ARROW_W,
    h = SECTION_ARROW_H,
    text  = "",
    color = COLOR_THEME_SECONDARY1,
    press = onToggle
  }

  children[#children + 1] = {
    type  = "label",
    x = btnX,
    y = btnY + 3,
    w = SECTION_ARROW_W,
    text  = icon,
    color = WHITE,
    align = CENTER,
    font  = SMLSIZE
  }

  -- Blue accent bar (below title)
  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + SECTION_H - 1 - SECTION_BAR_H,
    w = w, h = SECTION_BAR_H,
    color  = COLOR_THEME_SECONDARY1, filled = true
  }

  -- Divider line (bottom edge)
  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + SECTION_H - 1,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }
end

-- ── RadioSwitch ───────────────────────────────────────────────────────────────
-- Slider-style boolean toggle with dynamic visuals.
-- Visual state updates are driven by getter functions, so callers can avoid
-- full-page rebuilds on each toggle and keep focus stable.
--
-- Parameters:
--   children             – LVGL children array
--   x, y, w              – bounds of the full content row
--   labelText            – descriptive label on the left
--   value                – boolean: true = ON
--   labelOff, labelOn    – optional strings for OFF / ON side labels
--   onToggle             – press callback (no arguments)
--   i18n                 – optional i18n context; used when labels are nil

local TOGGLE_W   = 64
local TOGGLE_H   = 26
local TOGGLE_Y_OFFSET = -6
local SIDE_W     = 40
local SIDE_GAP   = 6

local NUMBER_W        = 172
local NUMBER_H        = 62
local NUMBER_Y_OFFSET = 6

function Controls.appendRadioSwitch(children, x, y, w, labelText, value,
                                     labelOff, labelOn, onToggle, i18n)
  if (not labelOff) and i18n and i18n.t then
    labelOff = i18n.t("app.pages.settings_general.value_off")
  end
  if (not labelOn) and i18n and i18n.t then
    labelOn = i18n.t("app.pages.settings_general.value_on")
  end
  labelOff = labelOff or "AUS"
  labelOn  = labelOn  or "EIN"

  local getValue
  if type(value) == "function" then
    getValue = value
  else
    local localValue = value == true
    getValue = function() return localValue end
    value = function(nextBool)
      localValue = nextBool == true
    end
  end

  local barW   = SIDE_W + SIDE_GAP + TOGGLE_W + SIDE_GAP + SIDE_W
  local barX   = x + w - barW
  local trackX = barX + SIDE_W + SIDE_GAP
  local einX   = trackX + TOGGLE_W + SIDE_GAP
  local rowH   = math.max(ROW_H, NUMBER_H)
  local trackY = y + math.floor((rowH - TOGGLE_H) / 2) + TOGGLE_Y_OFFSET
  local sideY  = y + math.floor((rowH - 20) / 2)
  local labelY = y + math.floor((rowH - 20) / 2)

  children[#children + 1] = {
    type  = "label",
    x = x, y = labelY,
    w = barX - x - 8,
    text  = labelText,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE
  }

  children[#children + 1] = {
    type = "toggle",
    x = trackX,
    y = trackY,
    w = TOGGLE_W,
    h = TOGGLE_H,
    get = function()
      return getValue()
    end,
    set = function(nextVal)
      local nextBool
      if nextVal == nil then
        -- Some EdgeTX builds call toggle.set() without a payload.
        nextBool = not getValue()
      else
        local t = type(nextVal)
        if t == "boolean" then
          nextBool = nextVal
        elseif t == "number" then
          nextBool = nextVal ~= 0
        elseif t == "string" then
          local s = string.lower(nextVal)
          nextBool = s == "1" or s == "true" or s == "on"
        else
          nextBool = not getValue()
        end
      end
      if nextBool ~= getValue() then
        value(nextBool)
        onToggle(nextBool)
      end
    end
  }

  children[#children + 1] = {
    type  = "label",
    x = barX, y = sideY,
    w = SIDE_W,
    text  = labelOff,
    color = function()
      return (not getValue()) and COLOR_THEME_PRIMARY1 or COLOR_THEME_SECONDARY1
    end,
    align = RIGHT,
    font  = SMLSIZE
  }

  children[#children + 1] = {
    type  = "label",
    x = einX, y = sideY,
    w = SIDE_W,
    text  = labelOn,
    color = function()
      return getValue() and COLOR_THEME_PRIMARY1 or COLOR_THEME_SECONDARY1
    end,
    font  = SMLSIZE
  }

  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + rowH,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }

  return rowH + 1
end

-- ── NumberField ──────────────────────────────────────────────────────────────
-- Numeric input field using native numberEdit behavior.
-- Focus field and turn wheel to adjust value.
--
-- Parameters:
--   opts - table:
--     enabled=true/false
--     min, max
--     suffix="°"
--     get=function() return number end
--     set=function(number) end

function Controls.appendNumberField(children, x, y, w, labelText, opts)
  opts = opts or {}
  w = tonumber(w) or NUMBER_W
  local enabledGetter
  if type(opts.enabled) == "function" then
    enabledGetter = opts.enabled
  else
    local enabled = opts.enabled ~= false
    enabledGetter = function() return enabled end
  end
  local suffix = opts.suffix or ""
  local minVal = tonumber(opts.min) or 0
  local maxVal = tonumber(opts.max) or 100
  local getter = opts.get or function() return minVal end
  local setter = opts.set or function() end

  local fieldW = NUMBER_W
  if fieldW > w then fieldW = w end
  local fieldX = x + w - fieldW
  local rowH = math.max(ROW_H, NUMBER_H)
  local fieldY = y + math.floor((rowH - NUMBER_H) / 2) + NUMBER_Y_OFFSET

  local bgColor = WHITE
  local textColor = function()
    return enabledGetter() and COLOR_THEME_PRIMARY1 or GREY_DEFAULT
  end

  children[#children + 1] = {
    type  = "label",
    x = x, y = y + 12,
    w = fieldX - x - 8,
    text  = labelText,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE
  }
  children[#children + 1] = {
    type = "numberEdit",
    x = fieldX,
    y = fieldY,
    w = fieldW,
    min = minVal,
    max = maxVal,
    active = function()
      return enabledGetter()
    end,
    get = function()
      local current = tonumber(getter()) or minVal
      if current < minVal then current = minVal end
      if current > maxVal then current = maxVal end
      return current
    end,
    set = function(val)
      local nextVal = tonumber(val) or minVal
      if nextVal < minVal then nextVal = minVal end
      if nextVal > maxVal then nextVal = maxVal end
      setter(nextVal)
    end,
    display = function(val)
      local shown = tonumber(val) or minVal
      return tostring(shown) .. suffix
    end
  }

  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + rowH,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }

  return rowH + 1
end

-- ── ComboSelect ───────────────────────────────────────────────────────────────
-- Generic dropdown using native lvgl.choice.
-- Returns the effective row height + 1 so callers can advance cursorY.
--
-- Parameters:
--   options       – array of { value = any, label = string }
--   selectedValue – currently selected value (compared with ==)
--   onSelect      – called with (value) when an option is chosen

local COMBO_OPTION_H = 44
local COMBO_H        = 36
local COMBO_Y_OFFSET = -2

Controls.COMBO_ROW_H    = math.max(ROW_H, NUMBER_H) + 1
Controls.COMBO_OPTION_H = COMBO_OPTION_H

function Controls.appendComboSelect(children, x, y, w, labelText, options,
                                     selectedValue, onSelect)

  local rowH = math.max(ROW_H, NUMBER_H)
  local comboW = 172
  if comboW > w then comboW = w end
  local comboX = x + w - comboW
  local comboY = y + math.floor((rowH - COMBO_H) / 2) + COMBO_Y_OFFSET
  local labelY = y + math.floor((rowH - 20) / 2)

  local values = {}
  local selectedIndex = 1
  for i, opt in ipairs(options) do
    values[i] = tostring(opt.label or "")
    if opt.value == selectedValue then
      selectedIndex = i
    end
  end
  if #values == 0 then
    values[1] = ""
    selectedIndex = 1
  end

  -- Left label (same style as radio rows)
  children[#children + 1] = {
    type  = "label",
    x = x, y = labelY,
    w = comboX - x - 8,
    text  = labelText,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE
  }

  -- Native choice control with EdgeTX popup behavior/styling.
  children[#children + 1] = {
    type  = "choice",
    x = comboX, y = comboY,
    w = comboW, h = COMBO_H,
    title = tostring(labelText or ""),
    values = values,
    get = function()
      return selectedIndex
    end,
    set = function(nextIndex)
      local idx = tonumber(nextIndex) or selectedIndex
      if idx < 1 then idx = 1 end
      if idx > #options then idx = #options end
      selectedIndex = idx
      local opt = options[idx]
      if opt and onSelect then
        onSelect(opt.value)
      end
    end
  }

  -- Row divider
  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + rowH,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }

  return rowH + 1
end

return Controls
