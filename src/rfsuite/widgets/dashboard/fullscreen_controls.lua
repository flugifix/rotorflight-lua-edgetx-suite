-- The two controls the widget draws over a theme that draws its own fullscreen and binds no
-- control of its own: a way into the quick menu, and a way out of fullscreen.
--
-- A theme that has taken fullscreen decides which controls it shows and what they do; it binds
-- them through the `ctx` its build receives. This file is what such a screen gets when its tree
-- carries no press at all, which is always the case for a declarative theme -- the engine has
-- no way to bind a tap -- so that no fullscreen the widget puts up is without the menu and a
-- way out. Loaded only then, by the runtime's fullscreen build.
--
-- The geometry is the quick menu's: the X lands exactly where the menu's close box lands, at
-- both layout profiles (`dH > 350` is the split fullscreen_menu.lua uses), and the menu control
-- sits one box to its left.

local M = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require) or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local chunk = loadScript(fullPath, "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local Views = requireModule("widgets/dashboard/views.lua")

-- The glyph opens the menu over the theme. The X is drawn on the theme, which is the whole of
-- fullscreen, so it leaves fullscreen -- where the menu's own X, drawn on a view over the
-- theme, closes that view and puts the theme back.
local AFTER_MENU = "openView:menu"
local AFTER_CLOSE = "exitFullscreen"

local function navigate(widget, after)
  if Views and type(Views.navigate) == "function" then Views.navigate(widget, after) end
end

--- Append the menu control and the close control to `children`, after whatever is there, so
--- they lie above it.
function M.append(children, widget)
  local zone = widget.zone
  local dW = (zone and zone.w) or LCD_W or 0
  local dH = (zone and zone.h) or LCD_H or 0

  local isLarge = dH > 350
  local size = isLarge and 44 or 20
  -- The quick menu's own inset for its close box, so the X is not a pixel off the menu's.
  local margin = isLarge and 8 or 1
  local fontH = isLarge and 24 or 12
  local font = isLarge and MIDSIZE or SMLSIZE
  local textOffY = isLarge and -8 or -4

  local cx = dW - size - margin
  local gx = cx - size - margin
  local cy = isLarge and 8 or 1

  children[#children+1] = {
    type = "button", x = gx, y = cy, w = size, h = size, color = COLOR_THEME_PRIMARY1 or BLACK,
    press = function() navigate(widget, AFTER_MENU) end
  }

  -- The three bars are LINES, and that is not a drawing preference. A `rectangle` built while
  -- the widget is fullscreen is a clickable object that passes its press to its parent
  -- (lua_lvgl_widget.cpp, LvglWidgetBox::build clears the clickable flag only for a widget that
  -- is not fullscreen), so bars drawn as boxes would lie on top of the button and swallow every
  -- press that lands on them: the control would answer around its bars and not at its centre.
  -- LVGL's line object is created not clickable, so a press on a bar reaches the button -- the
  -- same reason the quick menu's X label over its own button has always worked. The points are
  -- a plain table, not a function, so nothing here is resolved per frame.
  local barW = math.floor(size * 0.5)
  local barH = math.max(2, math.floor(size * 0.08))
  local barX = gx + math.floor((size - barW) / 2)
  local step = math.max(barH + 2, math.floor(size * 0.2))
  local barY = cy + math.floor((size - (barH + step * 2)) / 2) + math.floor(barH / 2)
  for i = 0, 2 do
    local lineY = barY + i * step
    children[#children+1] = {
      type = "line", x = 0, y = 0, w = 0, h = 0,
      pts = { { barX, lineY }, { barX + barW, lineY } },
      color = WHITE, thickness = barH
    }
  end

  children[#children+1] = {
    type = "button", x = cx, y = cy, w = size, h = size, color = COLOR_THEME_SECONDARY1 or RED,
    press = function() navigate(widget, AFTER_CLOSE) end
  }
  children[#children+1] = {
    type = "label", x = cx, y = cy + math.floor((size - fontH) / 2) + textOffY, w = size,
    text = "X", color = WHITE, align = CENTER, font = font
  }
  return children
end

return M
