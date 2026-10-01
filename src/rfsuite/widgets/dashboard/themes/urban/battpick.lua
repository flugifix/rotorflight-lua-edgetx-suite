-- The battery picker this theme draws for itself.
--
-- M.layout draws it, and pickview.lua is what calls it on a host with theme views: the host's
-- `battery_pick` record turned into a spec. M.build fills the same spec from a widget's
-- `state.batteryPick` for a host that calls a theme's `batteryPick(children, widget)` hook; the
-- phase modules of this theme export no such hook.
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
local K = requireModule("widgets/dashboard/themes/urban/viewkit.lua")
if not UD or not K or type(K.geometry) ~= "function" then return {} end

local M = {}
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
--
-- The header is the one every view of this theme draws (viewkit.lua, K.header), from the
-- screen's top left corner. The packs stand in two columns from two packs up, each a cell with
-- the pack's name one face above the flight view's and its capacity and profile in that face.
-- NO BATTERY always gets a full-width row of its own at the foot, reserved before the pack grid
-- is measured so it can never be the entry that falls off the bottom.
function M.layout(children, dW, dH, spec)
  local g = K.geometry({ x = 0, y = 0, w = dW, h = dH })
  if g == nil then return children end
  local packs = spec.packs or {}
  local contentY = K.header(children, g, spec.title, spec.closePress)

  local cols = (#packs >= 2) and 2 or 1
  local fullW = dW - 2 * g.pad
  local btnW = math.floor((fullW - (cols - 1) * g.gap) / cols)
  if btnW < 20 then return children end
  local contentH = dH - contentY - g.pad
  if contentH < 20 then return children end

  local nameFont = K.stepFace(g.font, 1)
  local f = { name = nameFont, nameH = UD.measure(nameFont, "Ag"), sub = g.font, subH = g.fontH }
  -- A cell is never lower than the close box, so every target on the picker is at least its size.
  local minBtnH = math.max(f.nameH + f.subH + 2 * g.textPad, g.closeSize)

  local noneH = math.min(minBtnH, contentH)
  local noneY = contentY + contentH - noneH
  local gridH = contentH - noneH - g.gap

  -- How many pack rows the remaining height takes. Candidates past `rows * cols` are NOT
  -- drawn -- the grid is cut, not scrolled, and the pilot reaches the rest through the
  -- flight log page. Registry order decides who makes the cut: three rows, six packs, on the
  -- 800x480, 480x320 and 480x272 screens.
  local rowsFit = 0
  if gridH >= minBtnH then rowsFit = math.floor((gridH + g.gap) / (minBtnH + g.gap)) end
  local rows = math.min(math.ceil(#packs / cols), rowsFit)

  local btnH = minBtnH
  if rows > 0 then
    local fair = math.floor((gridH - (rows - 1) * g.gap) / rows)
    -- Capped, or two packs become slabs as tall as the picker.
    btnH = math.max(minBtnH, math.min(fair, 2 * minBtnH))
  end

  for i = 1, rows * cols do
    local pack = packs[i]
    if type(pack) ~= "table" then break end
    local row = math.floor((i - 1) / cols)
    local col = (i - 1) % cols
    K.button(children, g, f, g.pad + col * (btnW + g.gap), contentY + row * (btnH + g.gap), btnW, btnH,
      pack.name, pack.sub, pack.selected, pack.press)
  end

  local none = spec.none
  if none ~= nil then
    K.button(children, g, f, g.pad, noneY, fullW, noneH, none.label, nil, none.selected, none.press)
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
