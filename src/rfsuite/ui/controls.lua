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
-- A sliding toggle for boolean values.
-- Visual: [LABEL]          AUS [====●  ] EIN   (OFF)
--         [LABEL]          AUS [  ●====] EIN   (ON)
--
-- Parameters:
--   children             – LVGL children array
--   x, y, w              – bounds of the full content row
--   labelText            – descriptive label on the left
--   value                – boolean: true = ON
--   labelOff, labelOn    – optional strings for OFF / ON side labels
--   onToggle             – press callback (no arguments)
--   i18n                 – optional i18n context; used when labels are nil

local TRACK_W    = 64   -- track width
local TRACK_H    = 26   -- track height (floats vertically in ROW_H)
local THUMB_SIZE = 20   -- thumb square: fills TRACK_H - 2*THUMB_PAD exactly
local THUMB_PAD  = 3    -- gap between track inner edge and thumb
local SIDE_W     = 40   -- wide enough for "AUS"/"EIN" in SMLSIZE without wrapping
local SIDE_GAP   = 6    -- gap between side label and track edge
local BORDER_W   = 2    -- track border thickness (rectangles drawn on top)

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

  -- Right-aligned control bar: [AUS]<gap>[track]<gap>[EIN]
  local barW   = SIDE_W + SIDE_GAP + TRACK_W + SIDE_GAP + SIDE_W
  local barX   = x + w - barW
  local trackX = barX + SIDE_W + SIDE_GAP
  local einX   = trackX + TRACK_W + SIDE_GAP
  local trackY = y + math.floor((ROW_H - TRACK_H) / 2)
  -- Center SMLSIZE labels (~12 px tall) in the track
  local sideY  = trackY + math.floor((TRACK_H - 20) / 2)

  -- ── Left descriptive label ────────────────────────────────────────────────
  children[#children + 1] = {
    type  = "label",
    x = x, y = y + 12,
    w = barX - x - 8,
    text  = labelText,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE
  }

  -- ── Track: button is the primary click target ─────────────────────────────
  -- Keep the button on top of most visuals so press/focus remains reliable.
  local trackColor = value and COLOR_THEME_SECONDARY1 or WHITE
  local thumbColor = value and WHITE or COLOR_THEME_SECONDARY1
  children[#children + 1] = {
    type  = "button",
    x = trackX, y = trackY,
    w = TRACK_W, h = TRACK_H,
    text  = "",
    press = onToggle,
    color = trackColor
  }

  -- Patch only the left corners when ON to visually square the blue fill
  -- while keeping almost the whole track fully clickable as button area.
  if value then
    children[#children + 1] = {
      type = "rectangle",
      x = trackX,
      y = trackY,
      w = 3,
      h = 3,
      color = trackColor,
      filled = true
    }
    children[#children + 1] = {
      type = "rectangle",
      x = trackX,
      y = trackY + TRACK_H - 3,
      w = 3,
      h = 3,
      color = trackColor,
      filled = true
    }
  end

  -- ── Thumb ─────────────────────────────────────────────────────────────────
  local thumbX = value
    and (trackX + TRACK_W - THUMB_PAD - THUMB_SIZE)
     or (trackX + THUMB_PAD)
  children[#children + 1] = {
    type   = "rectangle",
    x = thumbX, y = trackY + THUMB_PAD,
    w = THUMB_SIZE, h = THUMB_SIZE,
    color  = thumbColor, filled = true
  }

  -- ── Border (drawn last = topmost, always sharp) ───────────────────────────
  for i = 0, BORDER_W - 1 do
    children[#children + 1] = { type = "rectangle", x = trackX + i,               y = trackY + i,               w = TRACK_W - i * 2, h = 1,             color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = trackX + i,               y = trackY + TRACK_H - 1 - i, w = TRACK_W - i * 2, h = 1,             color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = trackX + i,               y = trackY + i,               w = 1, h = TRACK_H - i * 2,              color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = trackX + TRACK_W - 1 - i, y = trackY + i,               w = 1, h = TRACK_H - i * 2,              color = COLOR_THEME_SECONDARY1, filled = true }
  end

  -- ── "AUS" side label ─────────────────────────────────────────────────────
  -- Active side (OFF) → solid theme color; inactive → dimmed
  children[#children + 1] = {
    type  = "label",
    x = barX, y = sideY,
    w = SIDE_W,
    text  = labelOff,
    color = (not value) and COLOR_THEME_PRIMARY1 or COLOR_THEME_SECONDARY1,
    align = RIGHT,
    font  = SMLSIZE
  }

  -- ── "EIN" side label ─────────────────────────────────────────────────────
  children[#children + 1] = {
    type  = "label",
    x = einX, y = sideY,
    w = SIDE_W,
    text  = labelOn,
    color = value and COLOR_THEME_PRIMARY1 or COLOR_THEME_SECONDARY1,
    font  = SMLSIZE
  }

  -- ── Row divider ───────────────────────────────────────────────────────────
  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + ROW_H,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }
end

-- ── ComboSelect ───────────────────────────────────────────────────────────────
-- Generic dropdown combo. Renders the row, and when open also the popup below.
-- Returns the total height consumed so callers can advance cursorY:
--   closed → ROW_H + 1
--   open   → ROW_H + 1 + #options * COMBO_OPTION_H
--
-- Parameters:
--   options       – array of { value = any, label = string }
--   selectedValue – currently selected value (compared with ==)
--   isOpen        – true when the dropdown is expanded
--   onToggle      – called to open/close (no args)
--   onSelect      – called with (value) when an option is chosen

local COMBO_OPTION_H = 44
local COMBO_H        = 26
local COMBO_BORDER_W = 2

Controls.COMBO_ROW_H    = ROW_H + 1
Controls.COMBO_OPTION_H = COMBO_OPTION_H

function Controls.appendComboSelect(children, x, y, w, labelText, options,
                                     selectedValue, isOpen, onToggle, onSelect)
  -- Find current label
  local currentLabel = ""
  for _, opt in ipairs(options) do
    if opt.value == selectedValue then
      currentLabel = opt.label
      break
    end
  end

  local comboW = 172
  if comboW > w then comboW = w end
  local comboX = x + w - comboW
  local comboY = y + math.floor((ROW_H - COMBO_H) / 2)
  local textY  = comboY + math.floor((COMBO_H - 20) / 2)

  -- Left label (same style as radio rows)
  children[#children + 1] = {
    type  = "label",
    x = x, y = y + 12,
    w = comboX - x - 8,
    text  = labelText,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE
  }

  -- Combo button area (same control height as radio track)
  children[#children + 1] = {
    type  = "button",
    x = comboX, y = comboY,
    w = comboW, h = COMBO_H,
    text  = "",
    press = onToggle,
    color = WHITE
  }

  -- Border drawn last to keep a crisp edge in theme color
  for i = 0, COMBO_BORDER_W - 1 do
    children[#children + 1] = { type = "rectangle", x = comboX + i,               y = comboY + i,               w = comboW - i * 2, h = 1,                  color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = comboX + i,               y = comboY + COMBO_H - 1 - i, w = comboW - i * 2, h = 1,                  color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = comboX + i,               y = comboY + i,               w = 1, h = COMBO_H - i * 2,                   color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = comboX + comboW - 1 - i,  y = comboY + i,               w = 1, h = COMBO_H - i * 2,                   color = COLOR_THEME_SECONDARY1, filled = true }
  end

  -- Current value + arrow
  children[#children + 1] = { type = "label", x = comboX + 8,            y = textY, w = comboW - 28, text = currentLabel, color = COLOR_THEME_PRIMARY1, font = SMLSIZE }
  children[#children + 1] = { type = "label", x = comboX + comboW - 18,  y = textY -2, w = 12,          text = "v",          color = COLOR_THEME_PRIMARY1, align = RIGHT, font = SMLSIZE }

  -- Row divider
  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + ROW_H,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }

  if not isOpen then
    return ROW_H + 1
  end

  -- Popup background
  local popupW = comboW
  local popupX = comboX
  local popupY = y + ROW_H + 1
  local popupH = COMBO_OPTION_H * #options
  children[#children + 1] = { type = "rectangle", x = popupX, y = popupY, w = popupW, h = popupH, color = WHITE, filled = true }

  for i = 0, COMBO_BORDER_W - 1 do
    children[#children + 1] = { type = "rectangle", x = popupX + i,              y = popupY + i,              w = popupW - i * 2, h = 1,                color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = popupX + i,              y = popupY + popupH - 1 - i, w = popupW - i * 2, h = 1,                color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = popupX + i,              y = popupY + i,              w = 1, h = popupH - i * 2,                 color = COLOR_THEME_SECONDARY1, filled = true }
    children[#children + 1] = { type = "rectangle", x = popupX + popupW - 1 - i, y = popupY + i,              w = 1, h = popupH - i * 2,                 color = COLOR_THEME_SECONDARY1, filled = true }
  end

  for i, opt in ipairs(options) do
    local sel = opt.value == selectedValue
    local capturedValue = opt.value
    local rowY = popupY + (i - 1) * COMBO_OPTION_H
    local rowBg = sel and COLOR_THEME_SECONDARY1 or WHITE

    children[#children + 1] = {
      type  = "button",
      x     = popupX,
      y     = rowY,
      w     = popupW,
      h     = COMBO_OPTION_H,
      text  = "",
      color = rowBg,
      press = function() onSelect(capturedValue) end
    }

    children[#children + 1] = {
      type  = "label",
      x     = popupX + 10,
      y     = rowY + 10,
      w     = popupW - 20,
      text  = opt.label,
      color = sel and WHITE or COLOR_THEME_PRIMARY1,
      font  = SMLSIZE
    }

    if i < #options then
      children[#children + 1] = {
        type   = "rectangle",
        x = popupX + COMBO_BORDER_W,
        y = rowY + COMBO_OPTION_H - 1,
        w = popupW - COMBO_BORDER_W * 2,
        h = 1,
        color  = GREY_DEFAULT,
        filled = true
      }
    end
  end

  return ROW_H + 1 + COMBO_OPTION_H * #options
end

return Controls
