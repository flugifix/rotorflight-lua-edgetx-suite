-- Setup assistant: the first setup of a bare flight controller.
--
-- The unit is a PROCEDURE, not a wizard step. A procedure has a precondition, a goal, a
-- completion criterion it derives from the machine, and one or more screens; it is the thing that
-- can be run on its own two months later when one setting changes. The sections -- radio, flight
-- controller -- are orientation and progress, never navigation: the pilot is told *Radio, 3 of 6*,
-- not *step 7 of 12*.
--
-- Three rules shape everything below and are worth stating once rather than at each screen:
--
--   A procedure owns a decision or a check only if it can FINISH it. Where a value depends on
--   something a later procedure sets, the decision belongs there and not here behind a
--   placeholder.
--
--   Every intermediate state the assistant leaves behind must be harmless on its own. The pilot
--   may leave at any point, and does -- going out to correct something in the radio is a designed
--   route, not an abort.
--
--   A screen must fit without scrolling. On a page that ASKS, a row scrolled out of sight is an
--   option the pilot never knew was there, so where the content would not fit the procedure gets
--   a second screen instead.
--
-- And one that is about honesty rather than about shape: completion is DERIVED from the machine on
-- every entry. Only what the machine cannot know is stored -- see `store.lua`.

local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local Common = nil
local Controls = nil
local LoadingOverlay = nil
local Msp = nil
local Radio = nil
local Store = nil
local t = nil

local BASE = "app/pages/setup_wizard/"

local ui = {
  loaded = false,
  procIndex = 1,
  screenIndex = 1,
  procedures = nil,
  busy = nil,
  data = nil,
  requestRebuild = nil,
  requestClose = nil,
  entered = nil
}

local function pageText(i18n, key, fallback)
  if t then
    local translated = t(i18n, key, fallback)
    if translated ~= nil and translated ~= "" and translated ~= key then
      return translated
    end
  end
  return fallback
end

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
  if not Msp then Msp = loadModule(BASE .. "msp.lua") end
  if not Radio then Radio = loadModule(BASE .. "radio.lua") end
  if not Store then Store = loadModule(BASE .. "store.lua") end
  if not t then t = Common and Common.pageT("setup_wizard") or nil end
end

-- The object every procedure is handed. It carries the shared state and the few operations a
-- procedure needs from the runner, so a procedure file never reaches into `ui` directly.
local wiz = {}

wiz.text = pageText

function wiz.rebuild()
  if type(ui.requestRebuild) == "function" then ui.requestRebuild() end
end

function wiz.setBusy(title, message)
  ui.busy = { title = title, message = message }
  wiz.rebuild()
end

function wiz.clearBusy()
  ui.busy = nil
  wiz.rebuild()
end

function wiz.procedure()
  return ui.procedures and ui.procedures[ui.procIndex] or nil
end

function wiz.screen()
  local proc = wiz.procedure()
  return proc and proc.screens and proc.screens[ui.screenIndex] or nil
end

function wiz.procedures()
  return ui.procedures or {}
end

-- Completion, derived. `nil` means the machine cannot answer -- a calibration that has run leaves
-- no mark, and an assistant that guessed would be claiming a step happened. A procedure like that
-- is offered every time and can only be closed by the pilot saying so.
function wiz.isComplete(proc)
  if type(proc) ~= "table" or type(proc.isComplete) ~= "function" then return nil end
  local ok, value = pcall(proc.isComplete, wiz)
  if not ok then return nil end
  return value
end

function wiz.isSkipped(proc)
  if type(proc) ~= "table" or Store == nil then return false end
  return Store.isSkipped(proc.id, proc.section == "radio")
end

function wiz.setSkipped(proc, value)
  if type(proc) ~= "table" or Store == nil then return end
  Store.setSkipped(proc.id, proc.section == "radio", value)
  Store.flush()
end

-- What the opening screen reports, and it is the same walk the quick pass runs on. A procedure
-- whose criterion the machine cannot answer counts as OPEN -- the safe direction, because it
-- offers work rather than hiding it.
function wiz.walk()
  local open, total = 0, 0
  for _, proc in ipairs(ui.procedures or {}) do
    if proc.counted ~= false then
      total = total + 1
      if wiz.isComplete(proc) ~= true and not wiz.isSkipped(proc) then open = open + 1 end
    end
  end
  return open, total
end

-- Where the pilot stands inside the section, which is the only progress this assistant shows.
local function sectionPosition(proc)
  if type(proc) ~= "table" or proc.counted == false then return nil, nil end
  local at, total = 0, 0
  for _, other in ipairs(ui.procedures or {}) do
    if other.section == proc.section and other.counted ~= false then
      total = total + 1
      if other.id == proc.id then at = total end
    end
  end
  if at == 0 then return nil, nil end
  return at, total
end

local function enterCurrent()
  local proc = wiz.procedure()
  local screen = wiz.screen()
  if not proc or not screen then return end
  local mark = tostring(proc.id) .. "/" .. tostring(screen.id or ui.screenIndex)
  if ui.entered ~= mark then
    ui.entered = mark
    if ui.screenIndex == 1 and type(proc.enter) == "function" then proc.enter(wiz) end
    if type(screen.enter) == "function" then screen.enter(wiz) end
    if proc.counted ~= false and Store then
      Store.setResume(proc.id)
      Store.flush()
    end
  end
end

function wiz.goToProcedure(index, screenIndex)
  if not ui.procedures then return end
  if index < 1 then index = 1 end
  if index > #ui.procedures then index = #ui.procedures end
  ui.procIndex = index
  ui.screenIndex = screenIndex or 1
  ui.entered = nil
  ui.busy = nil
  enterCurrent()
  wiz.rebuild()
end

-- Forward through the path, passing over what the machine says is done and what the pilot said to
-- leave. That IS the quick pass -- there is no mode to switch on, and a first-time run passes over
-- nothing because nothing is satisfied yet.
local function nextOpenIndex(from)
  local list = ui.procedures or {}
  for index = from, #list do
    local proc = list[index]
    if proc.counted == false then return index end
    if wiz.isComplete(proc) ~= true and not wiz.isSkipped(proc) then return index end
  end
  return #list
end

wiz.nextOpenIndex = nextOpenIndex

function wiz.advanceUnconditional()
  local proc = wiz.procedure()
  if proc and proc.screens and ui.screenIndex < #proc.screens then
    ui.screenIndex = ui.screenIndex + 1
    ui.entered = nil
    enterCurrent()
    wiz.rebuild()
    return
  end
  wiz.goToProcedure(nextOpenIndex(ui.procIndex + 1), 1)
end

function wiz.advance()
  local screen = wiz.screen()
  if screen and type(screen.advance) == "function" then
    screen.advance(wiz, function(ok)
      wiz.clearBusy()
      if ok ~= false then wiz.advanceUnconditional() end
    end)
    return
  end
  wiz.advanceUnconditional()
end

function wiz.back()
  if ui.screenIndex > 1 then
    ui.screenIndex = ui.screenIndex - 1
    ui.entered = nil
    enterCurrent()
    wiz.rebuild()
    return
  end
  if ui.procIndex > 1 then
    local index = ui.procIndex - 1
    local proc = ui.procedures[index]
    wiz.goToProcedure(index, proc and proc.screens and #proc.screens or 1)
  end
end

function wiz.isLast()
  local proc = wiz.procedure()
  if ui.procedures == nil or proc == nil then return false end
  return ui.procIndex >= #ui.procedures and ui.screenIndex >= #(proc.screens or {})
end

-- Layout. The row height and the two reserved bands are the whole of the no-scroll rule in code: a
-- screen is given the space that is left and must not ask for more.
local ROW_H = 34
local HEADER_H = 40
local FOOTER_H = 42
-- The page is a scrolling container and the height it reports runs past the visible area, so a
-- footer placed at that height alone is drawn half off the screen. Measured on a 800x480 build.
local FOOTER_MARGIN = 16

wiz.ROW_H = ROW_H

local function label(children, x, y, w, text, font, colour)
  children[#children + 1] = {
    type = "label",
    x = x, y = y, w = w,
    text = tostring(text or ""),
    font = font,
    color = colour
  }
end

wiz.label = label

-- One finding, as every check in this assistant renders it: what was looked at, what was found,
-- and a marker. The marker is a word rather than a colour alone, because a derived result and one
-- the pilot asserted must not look the same.
function wiz.row(children, x, y, w, name, value, marker)
  local markerW = 74
  local nameW = math.floor((w - markerW) * 0.45)
  label(children, x, y + 8, nameW, name, SMLSIZE, COLOR_THEME_PRIMARY1)
  label(children, x + nameW + 4, y + 8, w - markerW - nameW - 8, value, SMLSIZE, COLOR_THEME_PRIMARY1)
  if marker ~= nil then
    label(children, x + w - markerW, y + 8, markerW, marker, SMLSIZE, COLOR_THEME_PRIMARY1)
  end
  children[#children + 1] = {
    type = "rectangle",
    x = x, y = y + ROW_H - 1, w = w, h = 1,
    color = GREY_DEFAULT, filled = true
  }
  return ROW_H
end

-- A finding with its own actions. The buttons are EQUALLY WEIGHTED on purpose: *no mix* with a
-- single button has already decided that the gap is a defect, and the pilot adapting a replacement
-- board to a transmitter they set up years ago is not looking at a defect.
function wiz.findingRow(children, x, y, w, name, value, actions)
  -- The buttons take a share of the row rather than a fixed width: at 104 px a two-word
  -- label is drawn past its own edge, and on a 320 px screen a fixed width leaves the
  -- finding itself no room at all. Both ends are bounded so neither happens.
  local gap = 6
  local btnW = math.floor((w - gap) * 0.17)
  if btnW < 88 then btnW = 88 end
  if btnW > 132 then btnW = 132 end
  local count = #(actions or {})
  local buttonsW = count * btnW + (count > 0 and (count - 1) * gap or 0)
  local textW = w - buttonsW - 8
  local nameW = math.floor(textW * 0.5)

  label(children, x, y + 9, nameW, name, SMLSIZE, COLOR_THEME_PRIMARY1)
  label(children, x + nameW + 4, y + 9, textW - nameW - 4, value, SMLSIZE, COLOR_THEME_PRIMARY1)

  for i, action in ipairs(actions or {}) do
    children[#children + 1] = {
      type = "button",
      x = x + w - buttonsW + (i - 1) * (btnW + gap),
      y = y + 2,
      w = btnW,
      h = ROW_H - 6,
      text = action.text,
      active = action.active,
      press = action.press
    }
  end

  children[#children + 1] = {
    type = "rectangle",
    x = x, y = y + ROW_H - 1, w = w, h = 1,
    color = GREY_DEFAULT, filled = true
  }
  return ROW_H
end

function wiz.paragraph(children, x, y, w, text)
  children[#children + 1] = {
    type = "label",
    x = x, y = y, w = w,
    text = tostring(text or ""),
    font = SMLSIZE,
    color = COLOR_THEME_PRIMARY1
  }
  return 0
end

local function buildFooter(children, ctx, x, y, w)
  local proc = wiz.procedure()
  local screen = wiz.screen()
  local i18n = ctx.i18n
  local gap = 8

  -- The skip is a control of the PROCEDURE and it is labelled, because what the pilot does with it
  -- is assert something about their own machine rather than dismiss a dialog. It is offered only
  -- where the machine cannot answer for itself.
  local skippable = proc ~= nil and proc.skippable == true and ui.screenIndex == 1
  local slots = skippable and 3 or 2
  local btnW = math.floor((w - (slots - 1) * gap) / slots)

  children[#children + 1] = {
    type = "button",
    x = x, y = y, w = btnW, h = FOOTER_H - 6,
    text = pageText(i18n, "back", "Back"),
    active = function() return ui.procIndex > 1 or ui.screenIndex > 1 end,
    press = function() wiz.back() end
  }

  local column = 1
  if skippable then
    column = 2
    children[#children + 1] = {
      type = "button",
      x = x + btnW + gap, y = y, w = btnW, h = FOOTER_H - 6,
      text = pageText(i18n, "skip", "I do this myself"),
      press = function()
        wiz.setSkipped(proc, true)
        wiz.goToProcedure(nextOpenIndex(ui.procIndex + 1), 1)
      end
    }
  end

  local nextLabel = pageText(i18n, "next", "Next")
  if wiz.isLast() then
    nextLabel = pageText(i18n, "finish", "Finish")
  elseif screen and type(screen.nextLabel) == "function" then
    nextLabel = screen.nextLabel(i18n)
  end

  children[#children + 1] = {
    type = "button",
    x = x + column * (btnW + gap), y = y, w = btnW, h = FOOTER_H - 6,
    text = nextLabel,
    active = function()
      local current = wiz.screen()
      if current and type(current.canAdvance) == "function" then
        return current.canAdvance(wiz) ~= false
      end
      return true
    end,
    press = function()
      if wiz.isLast() then
        if Store then Store.setResume(nil) Store.flush() end
        if type(ui.requestClose) == "function" then ui.requestClose() end
        return
      end
      wiz.advance()
    end
  }
end

local function sectionTitle(i18n, proc)
  if not proc then return pageText(i18n, "title", "Setup Assistant") end
  if proc.section == "board" then return pageText(i18n, "section_board", "Flight controller") end
  return pageText(i18n, "section_radio", "Radio")
end

local function ensureLoaded()
  if ui.loaded then return end
  ui.data = {}
  wiz.data = ui.data
  wiz.msp = Msp
  wiz.radio = Radio
  wiz.store = Store

  local procedures = {}
  local radioProcs = loadModule(BASE .. "proc_radio.lua")
  local boardProcs = loadModule(BASE .. "proc_board.lua")
  if type(radioProcs) == "table" then
    for _, proc in ipairs(radioProcs) do procedures[#procedures + 1] = proc end
  end
  if type(boardProcs) == "table" then
    for _, proc in ipairs(boardProcs) do procedures[#procedures + 1] = proc end
  end
  ui.procedures = procedures
  ui.procIndex = 1
  ui.screenIndex = 1
  ui.entered = nil
  ui.loaded = true
  enterCurrent()
end

-- Jumping straight to one procedure, which is what makes a later change a one-procedure job rather
-- than a walk. The precondition travels with the procedure for exactly this reason: the pilot who
-- arrives here never saw the section it belongs to.
function wiz.openProcedure(id)
  for index, proc in ipairs(ui.procedures or {}) do
    if proc.id == id then
      wiz.goToProcedure(index, 1)
      return true
    end
  end
  return false
end

function M.onLoad()
  ensureDeps()
  ensureLoaded()
end

function M.onActivate()
  ensureDeps()
  ensureLoaded()
end

function M.wakeup(ctx)
  ensureDeps()
  ensureLoaded()
  if type(ctx) == "table" then
    if type(ctx.requestRebuild) == "function" then ui.requestRebuild = ctx.requestRebuild end
    if type(ctx.requestClose) == "function" then ui.requestClose = ctx.requestClose end
    wiz.i18n = ctx.i18n
  end
  enterCurrent()
  local proc = wiz.procedure()
  local screen = wiz.screen()
  if proc and type(proc.wakeup) == "function" then proc.wakeup(wiz) end
  if screen and type(screen.wakeup) == "function" then screen.wakeup(wiz) end
end

function M.getHeaderActions()
  return {
    save = false,
    reload = false,
    star = false,
    help = true,
    menu = true
  }
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded()

  ui.requestRebuild = ctx and ctx.requestRebuild or nil
  ui.requestClose = ctx and ctx.requestClose or nil
  wiz.i18n = ctx and ctx.i18n or nil

  local children = ctx.children
  local x, y, w, h = ctx.x, ctx.y, ctx.w, ctx.h
  local i18n = ctx.i18n

  if ui.busy then
    LoadingOverlay.append(children, {
      x = x, y = y, w = w, h = h,
      title = ui.busy.title or pageText(i18n, "working_title", "Working"),
      message = ui.busy.message or "",
      progress = 0
    })
    return
  end

  local proc = wiz.procedure()
  local screen = wiz.screen()

  -- The heading is the section and the procedure, with the position INSIDE the section. There is
  -- deliberately no counter over the whole path: the procedures are the unit, the sections are
  -- orientation, and a running total would present the path as a form to get through.
  local heading = sectionTitle(i18n, proc)
  if proc then
    local title = type(proc.title) == "function" and proc.title(i18n) or tostring(proc.id)
    heading = heading .. "  -  " .. title
    local at, total = sectionPosition(proc)
    if at then heading = heading .. "   " .. tostring(at) .. "/" .. tostring(total) end
  end

  if Controls and type(Controls.appendStaticSectionHeader) == "function" then
    Controls.appendStaticSectionHeader(children, x, y, w, heading)
  end

  local bodyY = y + HEADER_H + 6
  local bodyH = h - HEADER_H - FOOTER_H - FOOTER_MARGIN - 12
  if bodyH < ROW_H then bodyH = ROW_H end

  if screen and type(screen.build) == "function" then
    screen.build(wiz, ctx, { x = x, y = bodyY, w = w, h = bodyH })
  end

  buildFooter(children, ctx, x, y + h - FOOTER_H - FOOTER_MARGIN, w)
end

function M.onHelp(ctx)
  local help = loadModule(BASE .. "help.lua")
  if type(help) == "function" then return help(ctx, wiz.procedure()) end
  return { title = pageText(ctx and ctx.i18n, "help_title", "Setup Assistant"), message = "" }
end

function M.onBack(ctx)
  -- Leaving to correct something elsewhere is a designed route rather than an abort, so no
  -- confirmation is raised here. The cursor is kept; what it does NOT do is assert anything -- on
  -- re-entry every procedure is derived again, so a repair made outside the assistant is noticed
  -- with nobody telling it.
  if ui.procIndex > 1 or ui.screenIndex > 1 then
    wiz.back()
    return false
  end
  return true
end

function M.allowMemAutoRefresh()
  return false
end

function M.onClose()
  if Store then Store.flush() end
  if Common and type(Common.resetPageState) == "function" then
    Common.resetPageState(ui, { resetLoaded = true, resetDirty = true })
  end
  if Msp and type(Msp.release) == "function" then Msp.release() end
  ui.procedures = nil
  ui.data = nil
  ui.busy = nil
  ui.entered = nil
  ui.loaded = false
  Common = nil
  Controls = nil
  LoadingOverlay = nil
  Msp = nil
  Radio = nil
  Store = nil
  t = nil
end

return M
