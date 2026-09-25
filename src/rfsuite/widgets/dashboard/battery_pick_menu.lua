-- The battery picker the dashboard shows in fullscreen when the flight log's prompt is on and
-- the pilot has not answered it yet for this connection.
--
-- It is the one picker surface, drawn for every theme, so its close box is always there. What
-- is drawn here is deliberately the same layout profile as fullscreen_menu.lua, so that a radio
-- at either resolution gets rows of the size it already gets from the quick menu.
--
-- A press records a REQUEST on the widget and nothing else. The pick, the card write and the
-- flight controller write all happen in the runtime's job pass: an LVGL press callback runs
-- inside the firmware's event dispatch, where a card write or a queue turn is the one thing a
-- widget must not do.
--
-- Every string the tree carries is built here, once, while the menu is built. Nothing below is
-- a closure, so nothing below runs in the reactive sweep.

local M = {}

local function requestPick(widget, id)
  -- `false` rather than nil for "no battery": nil is what the runtime reads as "no request at
  -- all", so the answer that clears the pack would never reach the job. Written out rather than
  -- as `(id == nil) and false or id`, which cannot produce `false` at all -- the `or` arm takes
  -- over the moment the `and` arm is false, and hands back the nil it was meant to replace.
  if id == nil then
    widget._batteryPickRequest = false
  else
    widget._batteryPickRequest = id
  end
  widget.built = false
  widget.renderKey = nil
  if lcd and type(lcd.exitFullScreen) == "function" then
    lcd.exitFullScreen()
  end
end

local function dismiss(widget)
  local pick = widget.state and widget.state.batteryPick or nil
  if type(pick) == "table" then
    pick.dismissed = true
    pick.pending = false
  end
  widget.batteryPickOpen = nil
  widget.built = false
  widget.renderKey = nil
  if lcd and type(lcd.exitFullScreen) == "function" then
    lcd.exitFullScreen()
  end
end

function M.build(children, widget)
  local dW = widget.zone.w
  local dH = widget.zone.h
  local dX = 0
  local dY = 0

  local t = (widget.i18n and type(widget.i18n.t) == "function") and widget.i18n.t or function(k, f) return f or k end

  local bg_color = COLOR_THEME_PRIMARY3 or BLACK
  if bg_color == BLACK and lcd and type(lcd.RGB) == "function" then
    bg_color = lcd.RGB(40, 40, 40)
  end
  local btn_color = COLOR_THEME_PRIMARY1 or BLACK
  local accent_color = COLOR_THEME_SECONDARY1 or WHITE

  children[#children+1] = {
    type = "rectangle", x=dX, y=dY, w=dW, h=dH, color=bg_color, filled=true
  }

  -- The same two layout profiles fullscreen_menu.lua uses: a large high-resolution radio, and
  -- the standard 480x272 one.
  local isLarge = dH > 350

  local headerH, titleFont, rowFont, fontH, smallH, closeSize, contentGap, btnH, gapY, paddingX
  local headTextOffY, closeTextOffY

  if isLarge then
    headerH = 60
    titleFont = MIDSIZE
    rowFont = MIDSIZE
    fontH = 24
    smallH = 16
    closeSize = 44
    contentGap = 20
    btnH = 62
    gapY = 10
    paddingX = 15
    headTextOffY = -6
    closeTextOffY = -8
  else
    headerH = 22
    titleFont = SMLSIZE
    rowFont = SMLSIZE
    fontH = 12
    smallH = 10
    closeSize = 20
    contentGap = 5
    btnH = 34
    gapY = 6
    paddingX = 5
    headTextOffY = -2
    closeTextOffY = -4
  end

  children[#children+1] = {
    type = "rectangle", x=dX, y=dY, w=dW, h=headerH, color=btn_color, filled=true
  }
  children[#children+1] = {
    type = "label", x=dX + paddingX, y=dY + math.floor((headerH - fontH)/2) + headTextOffY, w=dW-60,
    text=t("widgets.dashboard.battery_pick_title", "WHICH BATTERY?"), color=WHITE, align=LEFT, font=titleFont
  }

  local cx = dX + dW - closeSize - (isLarge and 8 or 1)
  local cy = dY + math.floor((headerH - closeSize)/2)
  children[#children+1] = {
    type = "button", x=cx, y=cy, w=closeSize, h=closeSize, color=COLOR_THEME_SECONDARY1 or RED,
    press = function() dismiss(widget) end
  }
  children[#children+1] = {
    type = "label", x=cx, y=cy + math.floor((closeSize - fontH)/2) + closeTextOffY, w=closeSize,
    text="X", color=WHITE, align=CENTER, font=titleFont
  }

  local pick = widget.state and widget.state.batteryPick or nil
  local candidates = (type(pick) == "table" and type(pick.candidates) == "table") and pick.candidates or {}
  local selectedId = type(pick) == "table" and pick.selectedId or nil

  local profileFmt = t("widgets.dashboard.battery_pick_profile", "Profile %d")
  local noProfile = t("widgets.dashboard.battery_pick_profile_none", "no profile")

  -- Two columns from four packs up, so a pilot with a handful of them still sees the whole
  -- registry without scrolling. One column below that keeps the names readable.
  local cols = (#candidates >= 4 and dW >= 400) and 2 or 1
  local btnW = math.floor((dW - paddingX*(cols+1)) / cols)
  local listY = dY + headerH + contentGap
  local bottom = dY + dH - paddingX

  -- NO BATTERY has the foot row to itself, reserved before the packs are laid out, so it can
  -- never be the entry that falls off the screen. The pack grid is cut, not scrolled: packs past
  -- what fits above it are not drawn. The Flight Log page can record one of them as the pack in
  -- use, but a pick there does not switch the flight controller's battery profile.
  local noneY = bottom - btnH
  local gridBottom = noneY - gapY

  for i = 1, #candidates do
    local entry = candidates[i]
    local row = math.floor((i-1)/cols)
    local col = (i-1)%cols
    local bx = dX + paddingX + col*(btnW+paddingX)
    local by = listY + row*(btnH+gapY)
    if by + btnH > gridBottom then break end

    local isCurrent = (selectedId ~= nil and entry.id == selectedId)
    local bColor = isCurrent and accent_color or btn_color
    local tColor = isCurrent and BLACK or WHITE

    local nameText = entry.name
    if type(nameText) ~= "string" or nameText == "" then nameText = tostring(entry.id) end
    local capText = ""
    if type(entry.cap) == "number" and entry.cap > 0 then
      capText = string.format("%d mAh", math.floor(entry.cap))
    end
    local profileText = noProfile
    if type(entry.targetProfile) == "number" then
      profileText = string.format(profileFmt, entry.targetProfile + 1)
    end
    local subText = capText
    if subText ~= "" then
      subText = subText .. "  -  " .. profileText
    else
      subText = profileText
    end

    local id = entry.id
    children[#children+1] = {
      type = "button", x=bx, y=by, w=btnW, h=btnH, color=bColor,
      press = function() requestPick(widget, id) end
    }
    children[#children+1] = {
      type = "label", x=bx, y=by + (isLarge and 8 or 3), w=btnW,
      text=nameText, color=tColor, align=CENTER, font=rowFont
    }
    children[#children+1] = {
      type = "label", x=bx, y=by + btnH - smallH - (isLarge and 8 or 3), w=btnW,
      text=subText, color=tColor, align=CENTER, font=SMLSIZE
    }
  end

  -- "No battery": the honest answer for a flight nobody wants in the log against a pack, and
  -- the one that clears a choice carried over from the previous connection.
  local noneW = math.floor(dW - paddingX * 2)
  children[#children+1] = {
    type = "button", x=dX + paddingX, y=noneY, w=noneW, h=btnH, color=btn_color,
    press = function() requestPick(widget, nil) end
  }
  children[#children+1] = {
    type = "label", x=dX + paddingX, y=noneY + math.floor((btnH - fontH)/2), w=noneW,
    text=t("widgets.dashboard.battery_pick_none", "NO BATTERY"), color=WHITE, align=CENTER, font=titleFont
  }
end

return M
