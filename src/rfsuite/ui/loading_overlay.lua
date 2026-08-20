local M = {}

local function clamp01(v)
  local n = tonumber(v) or 0
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

-- The measured width and line height of a string in one font. `lcd.sizeText(text, flags)` is
-- the EdgeTX name and it takes the font flags, so the answer is for the font the label is
-- actually drawn in; it is not gated on a drawing context, so it may be called while the child
-- list is being built. The fallback is deliberately crude and only has to be safe on a build
-- that does not offer the call at all.
local function textSize(text, font, fallbackCharW, fallbackLineH)
  local fn = lcd and lcd.sizeText
  if type(fn) == "function" then
    local ok, tw, th = pcall(fn, tostring(text or ""), font)
    tw, th = tonumber(tw), tonumber(th)
    if ok and tw and th and th > 0 then
      return tw, th
    end
  end

  return #tostring(text or "") * fallbackCharW, fallbackLineH
end

function M.append(children, opts)
  if type(children) ~= "table" or type(opts) ~= "table" then return end

  local x = tonumber(opts.x) or 0
  local y = tonumber(opts.y) or 0
  local w = tonumber(opts.w) or 0
  local h = tonumber(opts.h) or 0
  if w <= 0 or h <= 0 then return end

  local title = tostring(opts.title or "Loading")
  local message = tostring(opts.message or "")
  local progress = clamp01(opts.progress)

  local action = type(opts.action) == "table" and opts.action or nil

  -- A box that reports no progress. A notice waiting to be acknowledged has none to
  -- report, and a bar sitting at zero or at full under it says something untrue; without
  -- one the box is the same shape, one row shorter.
  local showBar = opts.bar ~= false

  local boxW = math.min(420, math.max(220, w - 40))
  local innerW = boxW - 28

  -- The title is drawn in MIDSIZE into `innerW` and wraps when it does not fit, while
  -- everything under it sat at a fixed offset from the top of the box -- so a title of two
  -- lines was drawn ON the message. Each extra line now moves the message, the bar and the
  -- button down by one line height and makes the box that much taller. A one-line title, which
  -- is what every caller in the tree passes, leaves `extra` at 0 and reproduces the geometry
  -- this file had before, arithmetic for arithmetic.
  local titleW, titleLineH = textSize(title, MIDSIZE, 12, 24)
  local titleLines = 1
  if innerW > 0 and titleW > innerW then
    titleLines = math.ceil(titleW / innerW)
  end
  local extra = (titleLines - 1) * titleLineH

  local barBlock = showBar and 0 or -32
  local boxH = (action and 208 or 154) + extra + barBlock
  local boxX = x + math.floor((w - boxW) / 2)
  local boxY = y + math.floor((h - boxH) / 2) - 64
  if boxY < y + 8 then
    boxY = y + 8
  end

  local barX = boxX + 16
  local barY = boxY + 110 + extra
  local barW = boxW - 32
  local barH = 16
  local fillW = math.floor((barW - 4) * progress + 0.5)

  children[#children + 1] = {
    type = "rectangle",
    x = boxX,
    y = boxY,
    w = boxW,
    h = boxH,
    color = COLOR_THEME_PRIMARY2,
    filled = true
  }

  children[#children + 1] = {
    type = "label",
    x = boxX + 14,
    y = boxY + 10,
    w = innerW,
    text = title,
    color = COLOR_THEME_PRIMARY1,
    font = MIDSIZE
  }

  children[#children + 1] = {
    type = "label",
    x = boxX + 14,
    y = boxY + 42 + extra,
    w = innerW,
    text = message,
    color = COLOR_THEME_PRIMARY1,
    font = SMLSIZE
  }

  -- The track, and it needs a colour of its own. GREY_DEFAULT is exported to Lua only when
  -- LCD_DEPTH > 1 and COLORLCD is NOT defined (radio/src/lua/api_general.cpp), so on every
  -- radio this overlay can run on it is nil -- and a rectangle with no colour is drawn in
  -- COLOR_THEME_SECONDARY1, which is what the filled part uses. Track and fill were therefore
  -- the same colour, and the bar read as full from the first frame to the last.
  if showBar then
    children[#children + 1] = {
      type = "rectangle",
      x = barX,
      y = barY,
      w = barW,
      h = barH,
      color = COLOR_THEME_SECONDARY2,
      filled = true
    }

    if fillW > 0 then
      children[#children + 1] = {
        type = "rectangle",
        x = barX + 2,
        y = barY + 2,
        w = fillW,
        h = barH - 4,
        color = COLOR_THEME_SECONDARY1,
        filled = true
      }
    end
  end

  -- An optional way out of the notice. A loading box normally has none, because there is
  -- nothing to decide while something is being read; a caller that CAN be left early -- a save
  -- whose settings are already stored, waiting on a flight controller that may never come back
  -- -- passes one, and it is drawn here so the box geometry stays in one place.
  if action then
    local btnW = math.min(180, boxW - 32)
    children[#children + 1] = {
      type = "button",
      x = boxX + math.floor((boxW - btnW) / 2),
      y = showBar and (barY + barH + 14) or barY,
      w = btnW,
      h = 32,
      text = tostring(action.text or "OK"),
      press = type(action.press) == "function" and action.press or function() end
    }
  end
end

-- A notice the pilot has to acknowledge: the same box, without a progress bar it has no
-- progress to put in, and with exactly one button. This exists so that nothing in the
-- tool has to reach for lvgl.message, which is a native modal outside the tool's own
-- run loop -- while one stands, run() is not reached, and which key or touch closes it
-- depends on whether anything focusable was created after it in the same build.
function M.appendNotice(children, opts)
  if type(opts) ~= "table" then return end

  local press = type(opts.press) == "function" and opts.press or function() end
  M.append(children, {
    x = opts.x,
    y = opts.y,
    w = opts.w,
    h = opts.h,
    title = opts.title,
    message = opts.message,
    bar = false,
    action = { text = opts.buttonText or "OK", press = press }
  })
end

return M
