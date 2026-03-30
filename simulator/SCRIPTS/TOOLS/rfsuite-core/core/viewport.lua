local Viewport = {}

local DEFAULT_WIDTH = 480
local DEFAULT_HEIGHT = 272

local function detectSize()
  local w = _G.LCD_W or DEFAULT_WIDTH
  local h = _G.LCD_H or DEFAULT_HEIGHT
  return w, h
end

function Viewport.detect(margin)
  local w, h = detectSize()
  local m = margin or 0

  if m < 0 then
    m = 0
  end

  local innerW = w - (m * 2)
  local innerH = h - (m * 2)

  if innerW < 0 then innerW = 0 end
  if innerH < 0 then innerH = 0 end

  return {
    width = w,
    height = h,
    scaleX = w / DEFAULT_WIDTH,
    scaleY = h / DEFAULT_HEIGHT,
    bounds = {
      x = m,
      y = m,
      w = innerW,
      h = innerH
    }
  }
end

return Viewport
