-- The battery picker this theme draws for itself.
--
-- The host's dashboard runtime calls `theme.batteryPick(children, widget)` in fullscreen
-- while `state.batteryPick.pending` or `widget.batteryPickOpen` is set; preflight.lua and
-- inflight.lua both forward to M.build below. Without the hook the host draws its own
-- generic picker, so nothing here is load-bearing for the feature -- only for the look.
--
-- It is a one-shot build: every string is a constant computed in this function. Nothing of
-- the picker runs in the firmware's reactive sweep, which is the cheapest way to satisfy
-- the reactive-closure rule rather than the carefully memoised way the flight view needs.
--
-- What the theme may write back is fixed by the host contract, and it is all this file
-- does: a press sets `widget._batteryPickRequest` to the entry's id (`false` for "no
-- battery"; nil is the host's "nothing was pressed"), the close box calls the host's
-- `rfsuite.batteryPick.dismiss()` or, where
-- that is not published, sets `widget.state.batteryPick.dismissed` itself, and both leave
-- fullscreen. In particular the `widget.built = false; widget.renderKey = nil` reset the
-- stock fullscreen menu performs is deliberately NOT done here -- the contract says nothing
-- else is written to the host, so the host keys its own rebuild off `pending`/`dismissed`.
--
-- Node order is part of the deal with tools/battpick_probe.lua: background, header strip,
-- title, close box, then one button-plus-two-labels group per candidate in registry order,
-- then the NO BATTERY button. The close box is therefore the FIRST button in the list and
-- the pack buttons follow in registry order.

if type(_G) == "table" and type(_G.__rfsuiteThemeUrbanBattpickModule) == "table" then
  return _G.__rfsuiteThemeUrbanBattpickModule
end

local function requireModule(path)
  if _G.rfsuite and type(_G.rfsuite.require) == "function" then
    local mod = _G.rfsuite.require(path)
    if type(mod) == "table" then return mod end
  end
  local mode = (_G.rfsuite and _G.rfsuite.loadMode) or "bt"
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. path, mode)
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local UD = requireModule("widgets/dashboard/themes/urban/common.lua")
if not UD then return {} end

local M = {}
local C = UD.C
local num = UD.num

local function exitFullScreen()
  if lcd and type(lcd.exitFullScreen) == "function" then lcd.exitFullScreen() end
end

-- A press records a request and leaves. The host performs the pick on its next pass; no
-- card write and no MSP queue call may happen inside an LVGL press callback.
local function pressRequest(widget, id)
  return function()
    widget._batteryPickRequest = id
    exitFullScreen()
  end
end

-- The close box dismisses through the host's own published helper wherever it exists:
-- `rfsuite.batteryPick.dismiss()` clears `pending` and invalidates the render key as well as
-- setting the flag, and neither of those is reachable from a theme. The direct write stays
-- as the fallback for a host that does not publish it -- `dismissed` is the one state field
-- the contract lets a theme set, and setting it alongside the helper would be writing a
-- field the helper already owns.
--
-- The lookup sits inside the callback rather than at build time: the runtime publishes the
-- table when it comes up, which need not be before this module was loaded. A press callback
-- is not a reactive closure, so a global read here is legal.
local function pressDismiss(widget)
  return function()
    local api = _G.rfsuite and _G.rfsuite.batteryPick
    if api and type(api.dismiss) == "function" then
      api.dismiss()
    else
      local st = widget and widget.state
      local bp = st and st.batteryPick
      if type(bp) == "table" then bp.dismissed = true end
    end
    exitFullScreen()
  end
end

-- The picker's picture, apart from what its presses do and where its strings come from: the
-- `spec` names the title, the close box's press, the packs in registry order (`name`, `sub`,
-- `selected`, `press`) and NO BATTERY (`label`, `selected`, `press`). M.build below fills it
-- from the widget for the host hook; pickview.lua fills it from the host's `battery_pick`
-- record, so the two pickers are one drawing.
function M.layout(children, dW, dH, spec)
  local packs = spec.packs or {}

  -- Two layout profiles, as the stock fullscreen menu has: 800x480 and 480x272 are the two
  -- screens this is ever built on. Only the paddings are fixed here -- the text heights come
  -- from the theme's own font picker, so a firmware without XLSIZE still lands on a face
  -- that fits.
  local isLarge = dH > 350
  local pad = isLarge and 12 or 5
  local gap = isLarge and 8 or 4
  local textPad = isLarge and 5 or 2
  local headerH = isLarge and 48 or 24

  UD.rect(children, 0, 0, dW, dH, C.bg, true)
  UD.rect(children, 0, 0, dW, headerH, C.track, true)

  local closeSize = math.max(14, headerH - 2 * (isLarge and 6 or 3))
  local closeX = dW - pad - closeSize
  local closeY = math.floor((headerH - closeSize) / 2)

  local title = spec.title
  local titleW = math.max(10, closeX - 2 * pad)
  local titleFont = UD.selectFont(headerH - 2 * textPad, titleW, title)
  local titleH = UD.measure(titleFont, title)
  UD.label(children, pad, math.floor((headerH - titleH) / 2), titleW, titleH,
    UD.fit(titleFont, title, titleW), titleFont, C.text, LEFT)

  children[#children + 1] = {
    type = "button", x = closeX, y = closeY, w = closeSize, h = closeSize,
    color = C.crit, press = spec.closePress
  }
  local closeFont = UD.selectFont(closeSize - 2 * textPad, closeSize, "X")
  local closeH = UD.measure(closeFont, "X")
  UD.label(children, closeX, closeY + math.floor((closeSize - closeH) / 2), closeSize, closeH,
    "X", closeFont, C.text, CENTER)

  -- UltiDash's own rule for its picker: one column below four packs, two from four up.
  -- NO BATTERY always gets a full-width row of its own at the foot, reserved before the
  -- pack grid is measured so it can never be the entry that falls off the bottom.
  local cols = (#packs >= 4) and 2 or 1
  local btnW = math.floor((dW - pad * (cols + 1)) / cols)
  local fullW = dW - 2 * pad
  if btnW < 20 then return children end

  local contentY = headerH + gap
  local contentH = dH - contentY - pad
  if contentH < 20 then return children end

  local nameFont = UD.selectFont(isLarge and 26 or 14, btnW - 2 * textPad, "MMMMMMMMMMMM")
  local nameH = UD.measure(nameFont, "Ag")
  local subFont = UD.selectFont(isLarge and 19 or 11, btnW - 2 * textPad, "8888 mAh  Profile 6")
  local subH = UD.measure(subFont, "Ag")
  local minBtnH = nameH + subH + 2 * textPad

  local noneH = math.min(minBtnH, contentH)
  local noneY = contentY + contentH - noneH
  local gridH = contentH - noneH - gap

  -- How many pack rows the remaining height takes. Candidates past `rows * cols` are NOT
  -- drawn -- the grid is cut, not scrolled, and the pilot reaches the rest through the
  -- flight log page. Registry order decides who makes the cut. How many that is depends on
  -- the face the firmware's font picker lands on and has not been measured on a radio; on
  -- the desktop probe's stub metrics it is six rows, so twelve packs in two columns.
  local rowsFit = 0
  if gridH >= minBtnH then rowsFit = math.floor((gridH + gap) / (minBtnH + gap)) end
  local rows = math.min(math.ceil(#packs / cols), rowsFit)

  local btnH = minBtnH
  if rows > 0 then
    local fair = math.floor((gridH - (rows - 1) * gap) / rows)
    -- Capped, or two packs on an 800x480 screen become slabs half the height of the picker.
    btnH = math.max(minBtnH, math.min(fair, math.floor(minBtnH * 3 / 2)))
  end

  local function entryButton(x, y, w, h, name, sub, selected, press)
    children[#children + 1] = {
      type = "button", x = x, y = y, w = w, h = h,
      color = selected and C.ok or C.track, press = press
    }
    local ink = selected and C.ink or C.text
    local subInk = selected and C.ink or C.label
    local inner = w - 2 * textPad
    local blockH = nameH + ((sub ~= "") and subH or 0)
    local top = y + math.max(0, math.floor((h - blockH) / 2))
    UD.label(children, x + textPad, top, inner, nameH,
      UD.fit(nameFont, name, inner), nameFont, ink, CENTER)
    if sub ~= "" then
      UD.label(children, x + textPad, top + nameH, inner, subH,
        UD.fit(subFont, sub, inner), subFont, subInk, CENTER)
    end
  end

  for i = 1, rows * cols do
    local pack = packs[i]
    if type(pack) ~= "table" then break end
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    entryButton(pad + col * (btnW + pad), contentY + row * (btnH + gap), btnW, btnH,
      pack.name, pack.sub, pack.selected, pack.press)
  end

  local none = spec.none
  if none ~= nil then
    entryButton(pad, noneY, fullW, noneH, none.label, "", none.selected, none.press)
  end

  return children
end

-- The host hook's picker: the spec made from the widget, with the presses the hook's contract
-- allows a theme -- a request on the widget, the host's dismiss helper -- and nothing else.
function M.build(children, widget)
  children = children or {}
  local zone = (widget and widget.zone) or {}
  -- Fullscreen hands the whole screen as the zone and the stock menu draws it from 0,0;
  -- this one does the same rather than trusting a zone origin that is not set there.
  local dW = math.floor(num(zone.w) or 0)
  local dH = math.floor(num(zone.h) or 0)
  if dW <= 0 or dH <= 0 then return children end

  local t = function(k, f) return f or k end
  if widget and type(widget.i18n) == "table" and type(widget.i18n.t) == "function" then
    t = widget.i18n.t
  end

  local state = (widget and widget.state) or {}
  -- The picker is drawn by the HOST, in fullscreen, outside any build of the two views, so it
  -- applies the colour scheme itself rather than inheriting whichever one the last build of a
  -- view happened to leave in place.
  UD.applyScheme((type(state.themeConfig) == "table" and state.themeConfig.scheme) or nil)
  local pick = (type(state.batteryPick) == "table" and state.batteryPick) or {}
  local candidates = (type(pick.candidates) == "table" and pick.candidates) or {}
  local selectedId = pick.selectedId
  local noneSelected = (selectedId == nil or selectedId == "")

  local profileNone = t("widgets.dashboard.battery_pick_profile_none", "no profile")
  local profileFmt = t("widgets.dashboard.battery_pick_profile", "Profile %d")

  local packs = {}
  for i = 1, #candidates do
    local entry = candidates[i]
    if type(entry) ~= "table" then break end

    -- targetProfile is 0-based and may be absent; the picker shows the human number.
    -- math.floor keeps an integer out of "%d", which a float would make raise.
    local target = num(entry.targetProfile)
    local profileText = profileNone
    if target then profileText = string.format(profileFmt, math.floor(target) + 1) end

    local cap = num(entry.cap)
    local sub = profileText
    if cap and cap > 0 then
      sub = string.format("%d mAh  %s", math.floor(cap + 0.5), profileText)
    end

    -- The comparison is by string so a numeric registry id and a stored string id still
    -- match; the id itself goes back to the host untouched -- the host owns its type.
    packs[i] = {
      name = tostring(entry.name or entry.id or "?"), sub = sub,
      selected = (not noneSelected) and (tostring(entry.id) == tostring(selectedId)),
      press = pressRequest(widget, entry.id),
    }
  end

  -- `false`, not "" and not nil: the host reads nil as "no request made on this pass", so
  -- "no battery" needs a value that is present and still not an id. It accepts "" as well,
  -- but `false` is what its contract states and what this theme sends.
  return M.layout(children, dW, dH, {
    title = t("widgets.dashboard.battery_pick_title", "WHICH BATTERY?"),
    closePress = pressDismiss(widget),
    packs = packs,
    none = { label = t("widgets.dashboard.battery_pick_none", "NO BATTERY"), selected = noneSelected,
             press = pressRequest(widget, false) },
  })
end

if type(_G) == "table" then _G.__rfsuiteThemeUrbanBattpickModule = M end

return M
