-- The controls the widget draws over a theme that draws its own fullscreen and binds no control
-- of its own: a way into the quick menu, a way out of fullscreen, and a way into the suite's tool.
--
-- A theme that has taken fullscreen decides which controls it shows and what they do; it binds
-- them through the `ctx` its build receives. This file is what such a screen gets when its tree
-- carries no press at all, which is always the case for a declarative theme -- the engine has
-- no way to bind a tap -- so that no fullscreen the widget puts up is without the menu and a
-- way out. Loaded only then, by the runtime's fullscreen build.
--
-- The geometry is the quick menu's: the X lands exactly where the menu's close box lands, at
-- both layout profiles (`dH > 350` is the split fullscreen_menu.lua uses), the menu control
-- sits one box to its left and the tool control one box to the left of that.
--
-- The tool control is also drawn on its own, on the connect splash at full screen
-- (`M.appendTool`), so the tool can be reached before the dashboard has anything to show.

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
-- The tool runs in place of the dashboard until it is closed; see widgets/dashboard/tool_host.lua.
local AFTER_TOOL = "openTool"

local function navigate(widget, after)
  if Views and type(Views.navigate) == "function" then Views.navigate(widget, after) end
end

local function geometry(widget)
  local zone = widget.zone
  local dW = (zone and zone.w) or LCD_W or 0
  local dH = (zone and zone.h) or LCD_H or 0

  local isLarge = dH > 350
  local size = isLarge and 44 or 20
  -- The quick menu's own inset for its close box, so the X is not a pixel off the menu's.
  local margin = isLarge and 8 or 1
  return {
    isLarge = isLarge,
    size = size,
    margin = margin,
    cx = dW - size - margin,
    cy = isLarge and 8 or 1,
  }
end

-- The tool control: a button with three slider lines on it. Lines for the same reason as the
-- menu control's bars below -- a line object is not clickable, so a press on the glyph reaches
-- the button. Not drawn while the model is armed: the tool is not opened then (tool_host.lua).
local function appendToolControl(children, widget, x, y, size)
  if widget.state and widget.state.armed == true then return end
  children[#children+1] = {
    type = "button", x = x, y = y, w = size, h = size, color = COLOR_THEME_PRIMARY1 or BLACK,
    press = function() navigate(widget, AFTER_TOOL) end
  }
  local lineW = math.floor(size * 0.56)
  local thin = math.max(1, math.floor(size * 0.05))
  local knobW = math.max(2, math.floor(size * 0.12))
  local knobH = math.max(4, math.floor(size * 0.2))
  local lineX = x + math.floor((size - lineW) / 2)
  local step = math.max(knobH + 1, math.floor(size * 0.25))
  local firstY = y + math.floor(size / 2) - step
  local knobAt = { 0.7, 0.3, 0.55 }
  for i = 0, 2 do
    local lineY = firstY + i * step
    children[#children+1] = {
      type = "line", x = 0, y = 0, w = 0, h = 0,
      pts = { { lineX, lineY }, { lineX + lineW, lineY } },
      color = WHITE, thickness = thin
    }
    local knobX = lineX + math.floor(lineW * knobAt[i + 1])
    local half = math.floor(knobH / 2)
    children[#children+1] = {
      type = "line", x = 0, y = 0, w = 0, h = 0,
      pts = { { knobX, lineY - half }, { knobX, lineY + half } },
      color = WHITE, thickness = knobW
    }
  end
end

--- Append the tool control alone, in the place of the close control, for a fullscreen surface
--- that carries no other control -- the connect splash.
function M.appendTool(children, widget)
  local g = geometry(widget)
  appendToolControl(children, widget, g.cx, g.cy, g.size)
  return children
end

--- Append the tool control, the menu control and the close control to `children`, after
--- whatever is there, so they lie above it.
function M.append(children, widget)
  local g = geometry(widget)
  local isLarge, size, margin = g.isLarge, g.size, g.margin
  local fontH = isLarge and 24 or 12
  local font = isLarge and MIDSIZE or SMLSIZE
  local textOffY = isLarge and -8 or -4

  local cx = g.cx
  local gx = cx - size - margin
  local cy = g.cy

  appendToolControl(children, widget, gx - size - margin, cy, size)

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

-- ---------------------------------------------------------------------------
-- The info bar
-- ---------------------------------------------------------------------------
--
-- A declarative theme is laid out for the widget area of a normal screen, which lies below the
-- radio's own top bar. At full screen that top bar is gone, so the runtime lays the theme out
-- below a bar of the same kind instead (`M.barHeight`) and draws the bar with `M.appendBar`:
-- what the radio's top bar showed, on the left, and the three controls above, on the right --
-- inside the bar rather than over the theme. The bar is drawn in the colour of the theme's tiles,
-- so it reads as one more tile above the grid.
--
-- Which items it shows is the pilot's choice on the theme's Info bar page; the runtime hands the
-- ids of the items switched on, in the order they are drawn. An empty list leaves the controls.

-- The readings are taken by `M.refresh`, which the runtime calls from the widget's own refresh
-- while the bar is up, at most once a second -- never from the bar's labels: their getters run in
-- the firmware's reactive sweep, which may read a prepared value and do nothing else. getTime()
-- counts in 10 ms ticks.
local REFRESH_TICKS = 100

-- The link item's four steps: in percent of a link quality, or in dBm where the link sensor that
-- answered is a signal strength (1RSS/2RSS, which the suite's search for `link` ends in; the
-- runtime publishes which one answered as `state.lqSource`).
local LINK_STEPS = { 1, 50, 70, 90 }
local RSSI_STEPS = { -120, -100, -85, -70 }
local RSSI_LINK_SOURCES = { ["1RSS"] = true, ["2RSS"] = true }

-- Kept once loaded; a load that failed is tried again on the next refresh.
local RadioStatus = nil

--- Take the readings of the items in `values.items` into `values`, at most once a second
--- (`force` skips that wait). Called from the widget's refresh, where probing the radio is legal.
function M.refresh(widget, values, force)
  local now = (type(getTime) == "function" and getTime()) or 0
  if not force and values.at ~= nil and now - values.at < REFRESH_TICKS and now >= values.at then return end
  values.at = now
  local items = values.items or {}

  if items.clock then
    local ok, dt = false, nil
    if type(getDateTime) == "function" then ok, dt = pcall(getDateTime) end
    values.clock = (ok and type(dt) == "table")
      and string.format("%02d:%02d", dt.hour or 0, dt.min or 0) or "--:--"
  end

  if items.tx_battery then
    if RadioStatus == nil then RadioStatus = requireModule("lib/radio_status.lua") end
    local volts, low = nil, false
    if type(RadioStatus) == "table" and type(RadioStatus.txBattery) == "function" then
      local okBattery, v, _, l = pcall(RadioStatus.txBattery)
      if okBattery then volts, low = v, l == true end
    end
    values.tx_battery = volts and string.format("%.1fV", volts) or "-V"
    values.batteryLow = low
  end

  if items.link then
    local state = widget.state
    local reading = state and state.lq
    local rssi = state and type(state.lqSource) == "string" and RSSI_LINK_SOURCES[state.lqSource] == true
    local steps, limits = 0, rssi and RSSI_STEPS or LINK_STEPS
    if type(reading) == "number" and reading == reading then
      reading = math.floor(reading + 0.5)
      if not rssi then reading = math.max(0, math.min(100, reading)) end
      values.link = string.format(rssi and "%ddB" or "%d%%", reading)
      for i = 1, #limits do
        if reading >= limits[i] then steps = i end
      end
    else
      values.link = rssi and "-dB" or "-%"
    end
    values.linkSteps = steps
  end
end

local function fontHeight(font, fallback)
  if lcd and type(lcd.sizeText) == "function" then
    local ok, _, h = pcall(lcd.sizeText, "0", font)
    if ok and type(h) == "number" and h > 0 then return h end
  end
  return fallback
end

local function textWidth(text, font, fallback)
  if lcd and type(lcd.sizeText) == "function" then
    local ok, w = pcall(lcd.sizeText, text, font)
    if ok and type(w) == "number" and w > 0 then return w end
  end
  return fallback
end

--- The height of the bar at this zone: the controls with their top inset above and below.
function M.barHeight(widget)
  local g = geometry(widget)
  return g.size + 2 * g.cy
end

--- The area a declarative theme is laid out in at full screen: the zone below the bar. The whole
--- zone where the bar would leave nothing.
function M.bodyZone(widget)
  local zone = widget.zone or {}
  local barH = M.barHeight(widget)
  local h = (zone.h or LCD_H or 0) - barH
  if h <= 0 then return zone end
  return { x = zone.x or 0, y = (zone.y or 0) + barH, w = zone.w or LCD_W or 0, h = h }
end

-- The items of the bar, in its order, and the theme configuration key that switches each off (the
-- Info bar page of app/pages/settings/dashboard/fields_form.lua). A key never stored leaves its
-- item on.
local ITEMS = {
  { id = "clock", pref = "bar_clock" },
  { id = "tx_battery", pref = "bar_tx_battery" },
  { id = "link", pref = "bar_link" },
}

--- The ids of the items the theme's configuration leaves on, in the bar's order.
function M.items(themeConfig)
  local items = {}
  for i = 1, #ITEMS do
    local value = nil
    if type(themeConfig) == "table" then value = themeConfig[ITEMS[i].pref] end
    if not (value == false or value == "false" or value == 0 or value == "0") then
      items[#items + 1] = ITEMS[i].id
    end
  end
  return items
end

--- Append the bar for a declarative theme's full-screen build: the items its configuration leaves
--- on, in the colour of its tiles (`engine.tileColor(build)`).
function M.appendThemeBar(children, widget, build, engine)
  local tileColor = engine and type(engine.tileColor) == "function" and engine.tileColor(build) or nil
  return M.appendBar(children, widget, M.items(widget.state and widget.state.themeConfig), tileColor)
end

--- Append the info bar to `children`, after whatever is there: its background in `bgcolor`
--- (the colour of the theme's tiles; the radio's title bar colour when that is not known), the
--- `items` in their order and the three controls of `M.append`.
function M.appendBar(children, widget, items, bgcolor)
  local g = geometry(widget)
  local dW = (widget.zone and widget.zone.w) or LCD_W or 0
  local barH = M.barHeight(widget)
  local font = g.isLarge and 0 or SMLSIZE
  local textH = fontHeight(font, g.isLarge and 24 or 12)
  local textY = math.floor((barH - textH) / 2)
  local gap = g.isLarge and 16 or 6
  local barColor = bgcolor or COLOR_THEME_SECONDARY1 or BLACK
  -- Dark text on a white bar, light text on anything else -- the pairing the themes use.
  local textColor = (barColor == WHITE) and BLACK or WHITE

  local list = type(items) == "table" and items or {}

  -- The readings the getters below return, kept on the widget: the runtime refreshes them from
  -- the widget's refresh while the bar is up, and a rebuild of the scene starts from the last.
  local values = widget._fullscreenBarValues
  if values == nil then
    values = {}
    widget._fullscreenBarValues = values
  end
  values.items = {}
  for i = 1, #list do values.items[list[i]] = true end
  M.refresh(widget, values, true)

  children[#children+1] = {
    type = "rectangle", x = 0, y = 0, w = dW, h = barH, filled = true, color = barColor
  }

  local x = g.margin + (g.isLarge and 4 or 2)
  for i = 1, #list do
    local id = list[i]
    if id == "clock" then
      local w = textWidth("00:00", font, g.isLarge and 70 or 30)
      children[#children+1] = {
        type = "label", x = x, y = textY, w = w + 4, font = font, color = textColor,
        text = function() return values.clock end
      }
      x = x + w + gap
    elseif id == "tx_battery" then
      local w = textWidth("00.0V", font, g.isLarge and 70 or 32)
      children[#children+1] = {
        type = "label", x = x, y = textY, w = w + 4, font = font,
        color = function() return values.batteryLow and (COLOR_THEME_WARNING or RED) or textColor end,
        text = function() return values.tx_battery end
      }
      x = x + w + gap
    elseif id == "link" then
      -- Four rising bars, then the reading. Lines, as on the controls: a line object takes no
      -- press, so nothing here can catch a tap meant for the screen behind it.
      local stepW = g.isLarge and 5 or 2
      local stepGap = g.isLarge and 3 or 1
      local fullH = math.max(4, textH - (g.isLarge and 4 or 2))
      local baseY = textY + math.floor((textH + fullH) / 2)
      for s = 1, #LINK_STEPS do
        local h = math.max(2, math.floor(fullH * s / #LINK_STEPS))
        local lineX = x + (s - 1) * (stepW + stepGap) + math.floor(stepW / 2)
        children[#children+1] = {
          type = "line", x = 0, y = 0, w = 0, h = 0, thickness = stepW,
          pts = { { lineX, baseY - h }, { lineX, baseY } },
          color = function()
            return (values.linkSteps or 0) >= s and textColor or (COLOR_THEME_DISABLED or textColor)
          end
        }
      end
      x = x + #LINK_STEPS * (stepW + stepGap) + (g.isLarge and 4 or 2)
      local w = textWidth("-100dB", font, g.isLarge and 72 or 32)
      children[#children+1] = {
        type = "label", x = x, y = textY, w = w + 4, font = font, color = textColor,
        text = function() return values.link end
      }
      x = x + w + gap
    end
  end

  return M.append(children, widget)
end

return M
