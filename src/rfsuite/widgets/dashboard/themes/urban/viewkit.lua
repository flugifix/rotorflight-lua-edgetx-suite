-- The chrome this theme's full screen views share: the header with its title and close box, the
-- row button, and the few words a view says about the host's work.
--
-- The views are registered in init.lua (`views`) and exist only on a host that has theme views;
-- the host loads a view's module the first time the view is built, so this file loads in a
-- fullscreen job pass and never in the pass that reloads the theme. Every view draws its header
-- through K.header, the battery picker (battpick.lua) included, so the picker, the menus and the
-- link view read as one set.
--
-- Nothing here decides what a press does. Every press a view binds is `ctx.action(...)` or
-- `ctx.run(...)`: the host performs the work and what follows it.

if type(_G) == "table" and type(_G.__rfsuiteThemeUrbanViewkitModule) == "table" then
  return _G.__rfsuiteThemeUrbanViewkitModule
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

local K = {}
K.UD = UD
K.C = UD.C
K.T = UD.T

-- The start of every view build: the scheme and the language the pilot chose, the metric cache
-- for this zone, and the geometry. Answers the geometry, or nil where the zone has no area.
function K.begin(zone, state)
  UD.applyScheme(((state and state.themeConfig) or {}).scheme)
  -- A host whose Urban carries a language table of its own picks it here; the suite's
  -- shipped Urban resolves its words through the translation markers and has none.
  if type(UD.applyLanguage) == "function" then UD.applyLanguage(UD.resolveLanguage()) end
  UD.beginBuild(zone)
  return K.geometry(zone)
end

-- The geometry alone, without touching the scheme: the paddings, the close box and the face of
-- the title, and the layout profile the rows still take -- the picker's two, by the screen height.
--
-- The face is the flight view's own -- the one its top bar, its clock and its value-row names are
-- drawn in (layout.lua, L.buildFlight: a bar of 7.5 % of the height, at least 18 px, its face
-- sized against "Total Time"). Taken by the same rule from the same height, a view's title is
-- the size of the screen the view opens from, on every screen size.
--
-- The close box is the one fixed size: 72 px on a screen taller than 350 px, 36 px below that.
function K.geometry(zone)
  local w = math.floor(UD.num(zone and zone.w) or 0)
  local h = math.floor(UD.num(zone and zone.h) or 0)
  if w <= 0 or h <= 0 then return nil end
  local isLarge = h > 350
  local barH = math.max(18, math.floor(h * 0.075))
  local font = UD.selectFont(barH - 2, nil, "Total Time")
  return {
    x = math.floor(UD.num(zone.x) or 0), y = math.floor(UD.num(zone.y) or 0), w = w, h = h,
    isLarge = isLarge,
    pad = isLarge and 12 or 5,
    gap = isLarge and 8 or 4,
    textPad = isLarge and 5 or 2,
    closeSize = isLarge and 72 or 36,
    closeMargin = isLarge and 4 or 2,
    font = font,
    fontH = UD.measure(font, "Total Time"),
  }
end

local function line(nodes, x1, y1, x2, y2, color, thickness)
  nodes[#nodes + 1] = { type = "line", x = 0, y = 0, w = 0, h = 0,
    pts = { { x1, y1 }, { x2, y2 } }, color = color, thickness = thickness }
end

-- A box outline drawn as four lines, as the flight view's menu glyph is drawn: a line is created
-- not clickable, so the outline can lie over a button without taking its press, where a rectangle
-- over a button would take it.
function K.outline(nodes, x, y, w, h, color, thickness)
  local x1, y1 = x + w - 1, y + h - 1
  local th = thickness or 2
  line(nodes, x, y, x1, y, color, th)
  line(nodes, x, y1, x1, y1, color, th)
  line(nodes, x, y, x, y1, color, th)
  line(nodes, x1, y, x1, y1, color, th)
end

-- The background, the header, its title and -- where `closePress` is given -- the close box.
-- `aside` is an optional second text after the title, in the label colour, which the link view
-- uses for the air rate. Answers the y the content starts at.
--
-- No strip: the header stands on the page's own background and a 1 px line closes it, inset by
-- the padding, as the flight view separates its groups. The close box takes the menu glyph's
-- shape: an outlined square with the X drawn as two lines, in the line colour. The header is as
-- tall as the box needs; a header without one (the link view in the widget zone) is as tall as
-- its title.
function K.header(nodes, g, title, closePress, aside)
  local C = UD.C
  local headerH = g.fontH + 2 * g.textPad
  if closePress ~= nil then headerH = g.closeSize + 2 * g.closeMargin end

  UD.rect(nodes, g.x, g.y, g.w, g.h, C.bg, true)
  UD.hline(nodes, g.x + g.pad, g.y + headerH - 1, g.w - 2 * g.pad)

  local right = g.x + g.w - g.pad
  if closePress ~= nil then
    local size = g.closeSize
    local closeX = right - size
    local closeY = g.y + g.closeMargin
    nodes[#nodes + 1] = {
      type = "button", x = closeX, y = closeY, w = size, h = size,
      color = C.bg, press = closePress
    }
    K.outline(nodes, closeX, closeY, size, size, C.line, 2)
    local inset = math.floor(size * 0.28)
    local th = math.max(2, math.floor(size * 0.09))
    local a, b = closeX + inset, closeX + size - 1 - inset
    local c, d = closeY + inset, closeY + size - 1 - inset
    line(nodes, a, c, b, d, C.line, th)
    line(nodes, a, d, b, c, C.line, th)
    right = closeX - g.pad
  end

  local titleW = math.max(10, right - (g.x + g.pad))
  local titleY = g.y + math.floor((headerH - g.fontH) / 2)
  local shown = UD.fit(g.font, title, titleW)
  UD.label(nodes, g.x + g.pad, titleY, titleW, g.fontH, shown, g.font, C.text, LEFT)
  if aside ~= nil then
    local used = UD.textWidth(g.font, shown) + 2 * g.pad
    local asideW = titleW - used
    if asideW > 10 then
      UD.label(nodes, g.x + g.pad + used, titleY, asideW, g.fontH, aside, g.font, C.label, LEFT)
    end
  end
  return g.y + headerH + g.gap
end

-- The two faces a row uses, picked once per build against the width a row has: the name and
-- the smaller line under it.
function K.rowFonts(g, w)
  local nameFont = UD.selectFont(g.isLarge and 26 or 14, w - 2 * g.textPad, "MMMMMMMMMMMM")
  local nameH = UD.measure(nameFont, "Ag")
  local subFont = UD.selectFont(g.isLarge and 19 or 11, w - 2 * g.textPad, "8888 mAh  Profile 6")
  local subH = UD.measure(subFont, "Ag")
  return { name = nameFont, nameH = nameH, sub = subFont, subH = subH,
           rowH = nameH + subH + 2 * g.textPad }
end

-- A button with a name and an optional line under it, the picker's entry button. `selected`
-- draws it in the ok colour. The labels lie over the button and are labels, never rectangles:
-- a rectangle drawn over a press takes the press away from it.
function K.button(nodes, g, f, x, y, w, h, name, sub, selected, press)
  local C = UD.C
  nodes[#nodes + 1] = {
    type = "button", x = x, y = y, w = w, h = h,
    color = selected and C.ok or C.track, press = press
  }
  local ink = selected and C.ink or C.text
  local subInk = selected and C.ink or C.label
  local inner = w - 2 * g.textPad
  local hasSub = sub ~= nil and sub ~= ""
  local blockH = f.nameH + (hasSub and f.subH or 0)
  local top = y + math.max(0, math.floor((h - blockH) / 2))
  UD.label(nodes, x + g.textPad, top, inner, f.nameH, UD.fit(f.name, name, inner), f.name, ink, CENTER)
  if hasSub then
    UD.label(nodes, x + g.textPad, top + f.nameH, inner, f.subH, UD.fit(f.sub, sub, inner), f.sub, subInk, CENTER)
  end
end

-- A row that is not offered now: its name and why, in the label colour, and no press.
function K.unavailable(nodes, g, f, x, y, w, h, name)
  local C = UD.C
  UD.rect(nodes, x, y, w, h, C.track, false, 0, 1)
  local inner = w - 2 * g.textPad
  local top = y + math.max(0, math.floor((h - f.nameH - f.subH) / 2))
  UD.label(nodes, x + g.textPad, top, inner, f.nameH, UD.fit(f.name, name, inner), f.name, C.label, CENTER)
  UD.label(nodes, x + g.textPad, top + f.nameH, inner, f.subH, UD.fit(f.sub, UD.T.unavailable, inner),
    f.sub, C.label, CENTER)
end

-- What became of the host's work on an entry, as the host reports it (`ctx.status`): the word and
-- its colour, or nil where nothing has been run in this visit.
function K.outcome(status)
  local C, T = UD.C, UD.T
  if status == "busy" then return T.run_busy, C.warn end
  if status == "ok" then return T.run_ok, C.ok end
  if status == "failed" then return T.run_failed, C.crit end
  return nil, nil
end

if type(_G) == "table" then _G.__rfsuiteThemeUrbanViewkitModule = K end

return K
