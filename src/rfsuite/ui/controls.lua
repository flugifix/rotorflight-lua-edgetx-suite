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
local STATIC_SECTION_H     = 50

Controls.SECTION_H = SECTION_H
Controls.STATIC_SECTION_H = STATIC_SECTION_H

local function clampInt(v, lo, hi)
  v = math.floor((tonumber(v) or lo) + 0.5)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- Shared responsive grid metrics for table-like pages (PIDs, rates, etc.).
-- Returns stable spacing/cell widths across different radios.
function Controls.computeGridMetrics(totalW, columns, opts)
  opts = opts or {}
  local colCount = tonumber(columns) or 1
  if colCount < 1 then colCount = 1 end

  local w = tonumber(totalW) or 0
  if w < 1 then w = 1 end

  local labelRatio = tonumber(opts.labelRatio) or 0.24
  local labelMin = tonumber(opts.labelMin) or 72
  local labelMax = tonumber(opts.labelMax) or math.max(labelMin, w - colCount)
  local gapMin = tonumber(opts.gapMin) or 2
  local gapMax = tonumber(opts.gapMax) or 8
  local cellMin = tonumber(opts.cellMin) or 42

  local labelW = clampInt(w * labelRatio, labelMin, labelMax)
  local available = w - labelW
  if available < colCount then
    labelW = math.max(0, w - colCount)
    available = w - labelW
  end

  local gap = clampInt(available * 0.02, gapMin, gapMax)
  local function computeCellWidth()
    return math.floor((w - labelW - (gap * (colCount - 1))) / colCount)
  end

  local cellW = computeCellWidth()
  while cellW < cellMin and gap > gapMin do
    gap = gap - 1
    cellW = computeCellWidth()
  end

  while cellW < cellMin and labelW > labelMin do
    labelW = labelW - 1
    cellW = computeCellWidth()
  end

  if cellW < 1 then cellW = 1 end
  return {
    labelW = labelW,
    gap = gap,
    cellW = cellW
  }
end

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
    color = COLOR_THEME_PRIMARY1,
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

function Controls.appendStaticSectionHeader(children, x, y, w, title)
  children[#children + 1] = {
    type  = "label",
    x = x, y = y + 2,
    text  = title,
    color = COLOR_THEME_PRIMARY1,
    font  = MIDSIZE
  }

  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + STATIC_SECTION_H - 6,
    w = w, h = 3,
    color  = COLOR_THEME_SECONDARY1, filled = true
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
--   onToggle             – press callback (no arguments)

local TOGGLE_W   = 64
local TOGGLE_H   = 26
local TOGGLE_Y_OFFSET = -6


local NUMBER_W        = 172
local NUMBER_H        = 62
local NUMBER_Y_OFFSET = 6
local HELP_BTN_W      = 30
local HELP_BTN_H      = 30
local HELP_BTN_GAP    = 6
Controls.NUMBER_H = NUMBER_H

local function showHelpAlert(helpText, helpTitle)
  if not (lvgl and lvgl.alert) then return end
  lvgl.alert({
    title = helpTitle or "Help",
    message = tostring(helpText or "")
  })
end

function Controls.appendRadioSwitch(children, x, y, w, labelText, value,
                                     onToggle, active)
  local getValue
  local setValue
  if type(value) == "function" then
    getValue = value
  else
    local localValue = value == true
    getValue = function() return localValue end
    setValue = function(nextBool)
      localValue = nextBool == true
    end
  end

  local barW   = TOGGLE_W
  local barX   = x + w - barW - 15
  local trackX = barX
  local rowH   = math.max(ROW_H, NUMBER_H)
  local trackY = y + math.floor((rowH - TOGGLE_H) / 2) + TOGGLE_Y_OFFSET
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
    active = active,
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
        if setValue then setValue(nextBool) end
        onToggle(nextBool)
      end
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
  elseif type(opts.active) == "function" then
    enabledGetter = opts.active
  else
    local enabled = (opts.enabled ~= false) and (opts.active ~= false)
    enabledGetter = function() return enabled end
  end
  local suffix = opts.suffix or ""
  local displayFn = opts.display
  local minVal = tonumber(opts.min) or 0
  local maxVal = tonumber(opts.max) or 100
  local stepVal = tonumber(opts.step) or 1
  local getter = opts.get or function() return minVal end
  local setter = opts.set or function() end

  local fieldW = NUMBER_W
  if fieldW > w then fieldW = w end
  local helpText = opts.helpText
  local helpTitle = opts.helpTitle
  local hasHelp = type(helpText) == "string" and helpText ~= ""
  local fieldX = x + w - fieldW - 10
  if hasHelp then
    fieldX = fieldX - HELP_BTN_W - HELP_BTN_GAP
  end
  local rowH = math.max(ROW_H, NUMBER_H)
  local fieldY = y + math.floor((rowH - NUMBER_H) / 2) + NUMBER_Y_OFFSET
  local labelY = y + math.floor((rowH - 20) / 2)

  children[#children + 1] = {
    type  = "label",
    x = x, y = labelY,
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
    min = math.floor(minVal / stepVal),
    max = math.ceil(maxVal / stepVal),
    active = function()
      return enabledGetter()
    end,
    get = function()
      local current = tonumber(getter()) or minVal
      if current < minVal then current = minVal end
      if current > maxVal then current = maxVal end
      return math.floor(current / stepVal)
    end,
    set = function(val)
      local nextVal = (tonumber(val) or math.floor(minVal / stepVal)) * stepVal
      if nextVal < minVal then nextVal = minVal end
      if nextVal > maxVal then nextVal = maxVal end
      setter(nextVal)
    end,
    display = function(val)
      local shown = (tonumber(val) or math.floor(minVal / stepVal)) * stepVal
      if type(displayFn) == "function" then
        local ok, text = pcall(displayFn, shown)
        if ok and type(text) == "string" then
          return text
        end
      end
      return tostring(shown) .. suffix
    end
  }

  if hasHelp then
    local helpBtnY = y + math.floor((rowH - HELP_BTN_H) / 2)
    children[#children + 1] = {
      type = "button",
      x = fieldX + fieldW + HELP_BTN_GAP,
      y = helpBtnY,
      w = HELP_BTN_W,
      h = HELP_BTN_H,
      text = "?",
      press = function()
        if type(opts.onHelp) == "function" then
          opts.onHelp(helpText, helpTitle)
        else
          showHelpAlert(helpText, helpTitle)
        end
      end
    }
  end

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
                                     selectedValue, onSelect, opts)

  opts = opts or {}

  local rowH = math.max(ROW_H, NUMBER_H)
  local comboW = 172
  if comboW > w then comboW = w end
  local helpText = opts.helpText
  local helpTitle = opts.helpTitle
  local hasHelp = type(helpText) == "string" and helpText ~= ""
  local comboX = x + w - comboW - 10
  if hasHelp then
    comboX = comboX - HELP_BTN_W - HELP_BTN_GAP
  end
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
    active = opts.active,
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

  if hasHelp then
    local helpBtnY = y + math.floor((rowH - HELP_BTN_H) / 2)
    children[#children + 1] = {
      type = "button",
      x = comboX + comboW + HELP_BTN_GAP,
      y = helpBtnY,
      w = HELP_BTN_W,
      h = HELP_BTN_H,
      text = "?",
      press = function()
        if type(opts.onHelp) == "function" then
          opts.onHelp(helpText, helpTitle)
        else
          showHelpAlert(helpText, helpTitle)
        end
      end
    }
  end

  -- Row divider
  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + rowH,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }

  return rowH + 1
end

function Controls.appendTextField(children, x, y, w, labelText, opts)
  opts = opts or {}
  local rowH = math.max(ROW_H, NUMBER_H)
  local labelY = y + math.floor((rowH - 20) / 2)

  local editW = 172
  if editW > w then editW = w end
  local editX = x + w - editW - 10
  local labelW = editX - x - 8

  local getter = opts.get or function() return "" end
  local setter = opts.set or function() end
  local activeGetter = opts.active
  if type(activeGetter) ~= "function" then
    local activeVal = opts.active ~= false
    activeGetter = function() return activeVal end
  end
  local maxLength = tonumber(opts.length) or 32

  -- Left label
  children[#children + 1] = {
    type  = "label",
    x = x, y = labelY,
    w = labelW,
    text  = labelText,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE
  }

  -- Text edit box
  children[#children + 1] = {
    type = "textEdit",
    x = editX,
    y = y + 6,
    w = editW,
    h = 50,
    value = getter(),
    length = maxLength,
    active = activeGetter,
    set = function(newVal)
      setter(newVal)
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
