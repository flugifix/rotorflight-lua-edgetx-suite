local M = {}

local function clamp01(v)
  local n = tonumber(v) or 0
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
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

  local boxW = math.min(420, math.max(220, w - 40))
  local boxH = 154
  local boxX = x + math.floor((w - boxW) / 2)
  local boxY = y + math.floor((h - boxH) / 2) - 64
  if boxY < y + 8 then
    boxY = y + 8
  end

  local barX = boxX + 16
  local barY = boxY + 110
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
    w = boxW - 28,
    text = title,
    color = COLOR_THEME_PRIMARY1,
    font = MIDSIZE
  }

  children[#children + 1] = {
    type = "label",
    x = boxX + 14,
    y = boxY + 42,
    w = boxW - 28,
    text = message,
    color = COLOR_THEME_PRIMARY1,
    font = SMLSIZE
  }

  -- The track, and it needs a colour of its own. GREY_DEFAULT is exported to Lua only when
  -- LCD_DEPTH > 1 and COLORLCD is NOT defined (radio/src/lua/api_general.cpp), so on every
  -- radio this overlay can run on it is nil -- and a rectangle with no colour is drawn in
  -- COLOR_THEME_SECONDARY1, which is what the filled part uses. Track and fill were therefore
  -- the same colour, and the bar read as full from the first frame to the last.
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

return M
