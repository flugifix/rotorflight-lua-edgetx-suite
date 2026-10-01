-- The chrome this theme's full screen views share: the header strip with its title and close
-- box, the row button, and the few words a view says about the host's work.
--
-- The views are registered in init.lua (`views`) and exist only on a host that has theme views;
-- the host loads a view's module the first time the view is built, so this file loads in a
-- fullscreen job pass and never in the pass that reloads the theme. It draws the picture the
-- battery picker (battpick.lua) already draws -- the header strip in the track colour, the close
-- box in the critical colour, the buttons in the track colour with the selected one in the ok
-- colour -- so the picker, the menus and the link view read as one set.
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
-- for this zone, and the layout profile -- the picker's two, by the screen height. Answers the
-- profile, or nil where the zone has no area.
function K.begin(zone, state)
  UD.applyScheme(((state and state.themeConfig) or {}).scheme)
  -- A host whose Urban carries a language table of its own picks it here; the suite's
  -- shipped Urban resolves its words through the translation markers and has none.
  if type(UD.applyLanguage) == "function" then UD.applyLanguage(UD.resolveLanguage()) end
  UD.beginBuild(zone)
  local w = math.floor(UD.num(zone and zone.w) or 0)
  local h = math.floor(UD.num(zone and zone.h) or 0)
  if w <= 0 or h <= 0 then return nil end
  local isLarge = h > 350
  return {
    x = math.floor(UD.num(zone.x) or 0), y = math.floor(UD.num(zone.y) or 0), w = w, h = h,
    isLarge = isLarge,
    pad = isLarge and 12 or 5,
    gap = isLarge and 8 or 4,
    textPad = isLarge and 5 or 2,
    headerH = isLarge and 48 or 24,
  }
end

-- The background, the header strip, its title and -- where `closePress` is given -- the close
-- box, exactly as the picker draws them. `aside` is an optional second text after the title, in
-- the label colour, which the link view uses for the air rate. Answers the y the content starts at.
function K.header(nodes, g, title, closePress, aside)
  local C = UD.C
  UD.rect(nodes, g.x, g.y, g.w, g.h, C.bg, true)
  UD.rect(nodes, g.x, g.y, g.w, g.headerH, C.track, true)

  local right = g.x + g.w - g.pad
  if closePress ~= nil then
    local closeSize = math.max(14, g.headerH - 2 * (g.isLarge and 6 or 3))
    local closeX = right - closeSize
    local closeY = g.y + math.floor((g.headerH - closeSize) / 2)
    nodes[#nodes + 1] = {
      type = "button", x = closeX, y = closeY, w = closeSize, h = closeSize,
      color = C.crit, press = closePress
    }
    local closeFont = UD.selectFont(closeSize - 2 * g.textPad, closeSize, "X")
    local closeH = UD.measure(closeFont, "X")
    UD.label(nodes, closeX, closeY + math.floor((closeSize - closeH) / 2), closeSize, closeH,
      "X", closeFont, C.text, CENTER)
    right = closeX - g.pad
  end

  local titleW = math.max(10, right - (g.x + g.pad))
  local titleFont = UD.selectFont(g.headerH - 2 * g.textPad, titleW, title)
  local titleH = UD.measure(titleFont, title)
  local titleY = g.y + math.floor((g.headerH - titleH) / 2)
  local shown = UD.fit(titleFont, title, titleW)
  UD.label(nodes, g.x + g.pad, titleY, titleW, titleH, shown, titleFont, C.text, LEFT)
  if aside ~= nil then
    local used = UD.textWidth(titleFont, shown) + 2 * g.pad
    local asideW = titleW - used
    if asideW > 10 then
      UD.label(nodes, g.x + g.pad + used, titleY, asideW, titleH, aside, titleFont, C.label, LEFT)
    end
  end
  return g.y + g.headerH + g.gap
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
