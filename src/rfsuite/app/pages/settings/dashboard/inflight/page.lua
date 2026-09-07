-- Settings > Dashboard > In-flight tuning.
--
-- Everything on this page is per MODEL: which switch arms the overlay, which channels and global
-- variables this model's mixer devotes to the adjustment pair, and which trims stand in for its
-- rows. So it writes into the model store keyed by the flight controller's MCU id, exactly as the
-- theme page's model override does, and says so when no flight controller is connected.
--
-- Two things this page has learned the hard way, both from a radio and both worth stating here.
--
-- What it LOADS. The page needs the settings, the setup check and the trim names -- it needs
-- nothing of the live state machine and nothing of the adjustment-function tables behind it.
-- Loading widgets/dashboard/inflight/drive.lua to get at them pulled 135 kB of Lua into the tool
-- on entry, against 0.1 to 3.9 kB for the project's other settings pages, on a radio whose tool
-- had 134 kB of heap left; the tool stopped answering twelve seconds later. It loads
-- inflight/setup.lua instead, which is the same code without the drive behind it.
--
-- What it READS. The setup check walks the model's mixer lines, its variables and its trim modes.
-- That walk runs ONCE per visit, and again only after a field has actually changed, latched on a
-- flag the next build consumes. It is not on a timer: a page that re-reads the model because a
-- second has passed is a page that re-reads the model forever.

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = nil
local Controls = nil
local Setup = nil
local ConfirmDialog = nil
-- The flight controller action, loaded only when the button that uses it is pressed. It brings
-- inflight/fcsetup.lua and the whole adjustment function table with it, and the page's entry cost
-- is what the pilot's radio ran out of heap on -- so nothing that is not needed to DRAW the page
-- is loaded to draw it.
local FcAction = nil

local M = {}

-- The switch picker's filters, as the firmware numbers them. Named here rather than reached for
-- as globals, following app/pages/setup_wizard/proc_radio.lua: SW_SWITCH is the physical switch
-- block, SW_NONE the empty entry that lets a pilot clear the choice. Trims are a filter of their
-- own and are deliberately not offered -- a trim is a row, not the interlock.
local SW_SWITCH = 1
-- The trim block, as its own filter. A trim is offered by the picker as two positions -- the
-- decrement and the increment -- and the overlay stores the increment; see Setup.normaliseTrim.
local SW_TRIM = 1 << 1
local SW_NONE = 1 << 20

-- How many of the lines the write would remove are named one by one in the question. Past this the
-- rest are counted instead: a confirmation nobody reads to the end is not a confirmation.
local PLAN_LINES_SHOWN = 6

local ui = {
  loaded = false,
  dirty = false,
  sections = {
    general = true,
    wiring = false,
    trims = false,
    undo = false
  },
  config = nil,
  trimNames = nil
}

ui.runtime = nil
local t = nil

local function ensureDeps()
  if not Common then
    Common = loadModule("app/pages/settings/common.lua")
  end
  if not Controls then
    Controls = loadModule("ui/controls.lua")
  end
  if not Setup then
    Setup = loadModule("widgets/dashboard/inflight/setup.lua")
  end
  if not ui.runtime then
    ui.runtime = Common.createFormRuntime(ui)
  end
  if not t then
    t = Common.pageT("settings_dashboard_inflight")
  end
end

local function session()
  if type(_G) ~= "table" or not _G.rfsuite then return nil end
  if type(_G.rfsuite.session) ~= "table" then return nil end
  return _G.rfsuite.session
end

-- Per-model settings can only be stored while a flight controller is connected: the store is
-- keyed by its MCU id and there is no key without it.
local function hasModelStore()
  local s = session()
  return s ~= nil and s.mcu_id ~= nil
end

--- One radio surface for the whole visit. It is a table of closures, so building a fresh one per
-- build would hand the page a new set of them every time the screen was laid out again.
local function radio()
  if ui.radio == nil then
    ui.radio = Setup.radio()
  end
  return ui.radio
end

local function ensureLoaded()
  if ui.loaded then return end
  local s = session()
  ui.config = Setup.loadSettings(s and s.modelPreferences or nil)
  ui.radio = nil
  ui.checkDone = false
  ui.checkResult = nil
  ui.trimNames = nil
  ui.gvarWalkDone = false
  ui.gvarConflicts = nil
  ui.planNotice = nil
  ui.fcRun = nil
  ui.fcNotice = nil
  ui.fcProgress = nil
  ui.fcPhase = nil
  ui.loaded = true
end

--- A repaint WITHOUT marking the settings edited.
--
-- ui.runtime.markDirty does both, which is right for a field the pilot changed and wrong for the
-- progress of a flight controller write: that changes the board, not the settings, and raising the
-- edited flag for it would leave the page asking to save something nobody typed.
local function requestRepaint()
  local rebuild = ui.runtime and ui.runtime.requestRebuild
  if type(rebuild) == "function" then rebuild() end
end

--- Whether this model already drives something with one of the two configured variables.
--
-- This replaces a PROPOSAL. The page used to walk the model for two variables nothing referred to
-- and put them in the fields; the pilot's ruling after the third radio round is that the pair is
-- a fixed default instead, because a setting that moves with the model is one nobody can write
-- down and a pilot who never opens this page had an overlay that could not go live.
--
-- The walk stays, and its answer is now a WARNING rather than a choice: the overlay pulses these
-- variables several times a second while a pilot is tuning, so one that already scales a mixer or
-- an input line would move a control surface for a reason nobody could connect to it. It names the
-- line, because a warning that says only "taken" sends the pilot through thirty-two channels.
--
-- Runs once per visit, off the same latch as the check, and writes nothing.
local function gvarConflicts()
  if ui.gvarWalkDone then return ui.gvarConflicts end
  ui.gvarWalkDone = true
  ui.gvarConflicts = Setup.gvarConflicts(radio(), ui.config)
  return ui.gvarConflicts
end

local function trimNames()
  if ui.trimNames == nil then
    ui.trimNames = Setup.resolveTrims(radio()) or false
    -- A store written before the trims were picked with the radio's own picker holds semantic
    -- indices, 1..6; from here on they are switch positions. The walk is the first moment this
    -- page can say what an old index meant, so the conversion happens here -- in the working copy
    -- only. It reaches the card on the next save, which is what the pilot asked for: nothing is
    -- rewritten behind him, and a page he opens and leaves changes nothing.
    if ui.trimNames ~= false then Setup.migrateTrims(ui.config, ui.trimNames) end
  end
  if ui.trimNames == false then return nil end
  return ui.trimNames
end

--- One trim, chosen with the radio's own switch picker rather than from a list this page wrote.
--
-- The list was a per-radio guess: the six semantic trims with the radio's labels where they could
-- be read and English stems where they could not, on a radio that may carry four. The picker is
-- the firmware's own, filtered to the trim block, so it offers exactly the trims this radio has
-- and names each of them the way every other page of the radio does.
--
-- It offers both positions of every trim and the store keeps the INCREMENT: the drive derives the
-- decrement from the same block entry, and a setting that could hold either would be two
-- spellings of one choice. A picked decrement is normalised to its own increment on the way in.
local function appendTrimPicker(children, x, y, w, label, get, set)
  local pickerW = 172
  if pickerW > w then pickerW = w end
  local rowH = Controls.ROW_H
  children[#children + 1] = {
    type = "label", x = x, y = Controls.labelY(y, rowH), w = w - pickerW - 18,
    text = label, color = COLOR_THEME_PRIMARY1, font = SMLSIZE
  }
  children[#children + 1] = {
    type = "switch",
    x = x + w - pickerW - 10, y = Controls.controlY(y, rowH), w = pickerW, h = rowH - 6,
    filter = SW_TRIM | SW_NONE,
    get = get,
    set = function(value)
      local wanted = Setup.normaliseTrim(trimNames(), value)
      if get() == wanted then return end
      set(wanted)
      ui.checkDone = false
      ui.planNotice = nil
      ui.runtime.markValueChanged()
    end
  }
  return rowH
end

--- A getter and a setter for one of the three named trim settings.
local function trimField(key)
  return function() return ui.config[key] or 0 end,
         function(value) ui.config[key] = value end
end

--- The setup check, cached.
--
-- `ui.checkDone` is the whole discipline: the walk runs when it is false and sets it, and only a
-- field's `set` puts it back. So a screen laid out again for any other reason -- a section opened,
-- a dialog closed, a rebuild the form runtime asked for -- costs no model reads at all.
local function checkResult()
  if not ui.checkDone then
    ui.checkDone = true
    -- The resolved block goes with it: a trim setting is a switch POSITION now, and the trim-mode
    -- half of the check indexes the firmware's own table by the semantic number behind it.
    ui.checkResult = Setup.check({ radio = radio(), settings = ui.config }, ui.config, trimNames())
  end
  return ui.checkResult
end

--- The verdict in one sentence, grouped by the page of the radio's own menus a pilot has to open:
-- the mixer, the global variables, the trims. A list of one line per fault reads longer and says
-- the same thing.
local function describeCheck(i18n, result)
  if result == nil then return t(i18n, "check_unchecked", "Setup not checked") end
  if result == "ok" then return t(i18n, "check_ok", "Setup OK") end
  if type(result) ~= "table" then return "" end

  local unset, mix, gvar, trim, claim = false, false, false, false, false
  for i = 1, #result do
    local code = result[i]
    if string.find(code, "mix", 1, true) then
      mix = true
    elseif string.find(code, "gvar_", 1, true) then
      gvar = true
    elseif string.find(code, "trim_mode", 1, true) then
      trim = true
    elseif code == "no_nav_trim" or code == "trim_claimed_twice" then
      claim = true
    else
      unset = true
    end
  end

  local parts = {}
  if unset then parts[#parts + 1] = t(i18n, "check_unset", "Switch or variables not set") end
  if mix then parts[#parts + 1] = t(i18n, "check_mix", "Mixer line missing or wrong") end
  if gvar then parts[#parts + 1] = t(i18n, "check_gvar", "Variable range or precision") end
  if trim then parts[#parts + 1] = t(i18n, "check_trim", "Trim still active in this flight mode") end
  if claim then parts[#parts + 1] = t(i18n, "check_claim", "Walk and adjust need two different trims") end
  return table.concat(parts, " / ")
end

--- A field changed, so the verdict on the screen was reached about a different model.
local function markValue(key, value)
  if ui.config[key] == value then return end
  ui.config[key] = value
  ui.checkDone = false
  -- The conflict warning names the variable that was configured when the walk ran, so a changed
  -- variable makes it a sentence about a setting nobody holds any more.
  if key == "value_gvar" or key == "bank_gvar" then ui.gvarWalkDone = false end
  ui.planNotice = nil
  -- The verdict on the flight controller was reached about the channels that have just changed.
  ui.fcNotice = nil
  ui.runtime.markValueChanged()
end

local function saveToStore()
  local s = session()
  if s == nil or s.mcu_id == nil then return false, "missing_mcu_id" end
  if type(s.modelPreferences) ~= "table" then s.modelPreferences = {} end
  if type(s.modelPreferences.inflight) ~= "table" then s.modelPreferences.inflight = {} end
  Setup.storeSettings(s.modelPreferences.inflight, ui.config)

  local MP = loadModule("lib/model_preferences.lua")
  if type(MP) ~= "table" or type(MP.saveByMcuId) ~= "function" then return false, "model_preferences" end
  return MP.saveByMcuId(s.mcu_id, s.modelPreferences)
end

function M.getHeaderActions()
  ensureDeps()
  return { save = true, help = true }
end

function M.onReload(ctx)
  ensureDeps()
  ui.loaded = false
  ui.dirty = false
  ensureLoaded()
  return true
end

function M.onSave(ctx)
  ensureDeps()
  local ok, err = saveToStore()
  if ctx and type(ctx.reportSave) == "function" then
    if ok then
      ui.dirty = false
      ctx.reportSave({
        ok = true,
        title = t(ctx.i18n, "saved_title", "Saved"),
        message = t(ctx.i18n, "saved_message", "In-flight tuning settings saved")
      })
    else
      ctx.reportSave({
        title = t(ctx.i18n, "save_error_title", "Error"),
        message = t(ctx.i18n, "save_error_message", "Save failed") .. ": " .. tostring(err or "io")
      })
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Setting the model up
-- ---------------------------------------------------------------------------

--- The question the pilot answers, built from the plan and not from what the page intended.
--
-- The destructive half comes first and with the count in the sentence, because that is the part
-- that cannot be undone from this page. The lines are then named the way the radio's own mixer
-- page names them, so that they can be recognised before they are gone.
local function planQuestion(i18n, plan)
  local lines = {}

  local removals = 0
  for i = 1, #plan.channels do
    local entry = plan.channels[i]
    removals = removals + entry.removed
    if entry.removed > 0 then
      lines[#lines + 1] = string.format("%s CH%d: %d",
        t(i18n, "plan_remove", "Remove from"), entry.channel, entry.removed)
    end
  end
  if removals == 0 then
    lines[#lines + 1] = t(i18n, "plan_remove_none", "Nothing has to be removed.")
  end

  local shown = 0
  for i = 1, #plan.deletions do
    if shown >= PLAN_LINES_SHOWN then
      lines[#lines + 1] = string.format("  ... %d", #plan.deletions - shown)
      break
    end
    shown = shown + 1
    lines[#lines + 1] = "  - " .. tostring(plan.deletions[i].text)
  end

  lines[#lines + 1] = ""
  for i = 1, #plan.insertions do
    local entry = plan.insertions[i]
    lines[#lines + 1] = string.format("%s CH%d: %s",
      t(i18n, "plan_add", "Add to"), entry.channel, tostring(entry.text))
  end

  for i = 1, #plan.gvars do
    local entry = plan.gvars[i]
    lines[#lines + 1] = string.format("%s GV%d %s -100..100",
      t(i18n, "plan_gvar", "Set"), entry.index, entry.name)
  end

  if #plan.trims > 0 then
    local modes = {}
    for i = 1, #plan.trims do modes[#modes + 1] = tostring(plan.trims[i].fm) end
    lines[#lines + 1] = string.format("%s %s",
      t(i18n, "plan_trims", "Trims off in flight mode"), table.concat(modes, ", "))
  end

  return table.concat(lines, "\n")
end

--- What a plan that will not be carried out says instead of the question.
local function refusalText(i18n, reason)
  if reason == "no_gvar" then
    return t(i18n, "plan_no_gvar", "Choose both variables first.")
  elseif reason == "same_gvar" then
    return t(i18n, "plan_same_gvar", "The two variables have to be different.")
  elseif reason == "same_channel" then
    return t(i18n, "plan_same_channel", "The two channels have to be different.")
  end
  return t(i18n, "plan_unsupported", "This radio does not offer the mixer writer.")
end

--- Plan, ask, write, check again -- and write nothing at all if the answer is no.
--
-- The plan is built here rather than carried over from the last build, so that the lines it offers
-- to delete are the ones on the model at the moment the question is asked. The write and the
-- re-check both happen inside the confirmation's own callback, which is where the pilot's answer
-- is; nothing outside this function reaches applyPlan.
local function offerSetup(i18n)
  local plan = Setup.plan(radio(), ui.config)
  if type(plan) ~= "table" or plan.ok ~= true then
    ui.planNotice = refusalText(i18n, type(plan) == "table" and plan.refused or nil)
    ui.runtime.markDirty()
    return
  end

  if ConfirmDialog == nil then
    ConfirmDialog = loadModule("ui/confirm_dialog.lua")
  end

  local function apply()
    local report = Setup.applyPlan(radio(), plan)
    -- The verdict on the screen was reached about the model as it was; the model has just changed.
    ui.checkDone = false
    if report.failed > 0 then
      ui.planNotice = string.format("%s (%d/%d)",
        t(i18n, "plan_failed", "The radio refused part of the setup"),
        report.written, report.written + report.failed)
    else
      ui.planNotice = string.format("%s (%d)",
        t(i18n, "plan_done", "Model set up"), report.written)
    end
    ui.runtime.markDirty()
  end

  local shown = false
  if ConfirmDialog and type(ConfirmDialog.show) == "function" then
    shown = ConfirmDialog.show({
      title = t(i18n, "plan_title", "Set up the model"),
      message = planQuestion(i18n, plan),
      onConfirm = apply,
      onCancel = function()
        -- Deliberately empty of writes AND deliberately present: a declined plan changes nothing,
        -- and saying so here is what keeps that from being an accident of the dialog's defaults.
        ui.planNotice = t(i18n, "plan_cancelled", "Nothing was changed")
        ui.runtime.markDirty()
      end
    })
  end

  if not shown then
    -- No confirmation could be put up, so there is no answer to act on. A model write is not
    -- something to do on the assumption that the pilot would have said yes.
    ui.planNotice = t(i18n, "plan_no_dialog", "This radio cannot show the confirmation.")
    ui.runtime.markDirty()
  end
end

-- ---------------------------------------------------------------------------
-- Setting the flight controller up
-- ---------------------------------------------------------------------------

--- Hand the flight controller action its context, having loaded it first.
--
-- The action itself lives in fcaction.lua beside this file and is read off the card only here,
-- on the press. Everything it needs travels in the table: the page's text helper, the settings
-- being edited, the page state it reports into and the repaint it asks for. Loading it at the top
-- of this file instead would put the whole adjustment function table into the tool's heap for
-- every pilot who ever opens this page, which is the cost that froze one radio already.
local function offerFcSetup(i18n)
  if FcAction == nil then
    FcAction = loadModule("app/pages/settings/dashboard/inflight/fcaction.lua")
  end
  if type(FcAction) ~= "table" or type(FcAction.offer) ~= "function" then
    ui.fcNotice = t(i18n, "fc_unavailable", "This build cannot reach the flight controller.")
    requestRepaint()
    return
  end
  FcAction.offer({
    i18n = i18n,
    t = t,
    config = ui.config,
    state = ui,
    repaint = requestRepaint
  })
end

-- ---------------------------------------------------------------------------
-- The sections
-- ---------------------------------------------------------------------------

local function appendNote(children, x, y, w, text)
  children[#children + 1] = {
    type = "label", x = x, y = y, w = w, text = text, color = COLOR_THEME_PRIMARY1, font = SMLSIZE
  }
  return 24
end

--- The line under the flight controller button while a run is on, drawn through a CLOSURE.
--
-- A moving number and a rebuild are two different things, and this page pays dearly for confusing
-- them: the read used to ask for a rebuild every time its percentage moved, which on the pilot's
-- radio was once per record for thirty-six records, on a tool with 134 kB of heap left. A closure
-- handed to lvgl.build runs in the firmware's reactive sweep and formats one string per frame,
-- which is what a counter needs and all it needs. The precedent is theirs -- every ESC page draws
-- its "unsaved" marker exactly this way.
--
-- The closure reads the page's own state and probes nothing.
local function appendProgressNote(children, x, y, w, source)
  children[#children + 1] = {
    type = "label", x = x, y = y, w = w, color = COLOR_THEME_PRIMARY1, font = SMLSIZE,
    text = function()
      local fn = source()
      if type(fn) ~= "function" then return "" end
      local ok, text = pcall(fn)
      if not ok or type(text) ~= "string" then return "" end
      return text
    end
  }
  return 24
end

local function buildGeneral(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "enabled", "Enabled"),
    ui.runtime.getBoolGetter("enabled"),
    ui.runtime.getBoolSetter("enabled"))

  -- The interlock. The picker stores a signed switch POSITION, which is what getSwitchValue takes,
  -- so nothing has to be resolved between what the pilot chose and what the overlay reads.
  local pickerW = 172
  if pickerW > w then pickerW = w end
  local rowH = Controls.ROW_H
  children[#children + 1] = {
    type = "label", x = x, y = Controls.labelY(cursorY, rowH), w = w - pickerW - 18,
    text = t(i18n, "switch", "Interlock switch"), color = COLOR_THEME_PRIMARY1, font = SMLSIZE
  }
  children[#children + 1] = {
    type = "switch",
    x = x + w - pickerW - 10, y = Controls.controlY(cursorY, rowH), w = pickerW, h = rowH - 6,
    filter = SW_SWITCH | SW_NONE,
    get = function() return ui.config.switch or 0 end,
    set = function(value) markValue("switch", tonumber(value) or 0) end
  }
  cursorY = cursorY + rowH

  -- Which parameters the overlay offers, and whether it is allowed to put them on the board.
  local setOptions = {
    { value = Setup.SET_MODE_STANDARD, label = t(i18n, "set_mode_standard", "Standard") },
    { value = Setup.SET_MODE_CUSTOM, label = t(i18n, "set_mode_custom", "Custom") }
  }
  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    t(i18n, "set_mode", "Set layout"), setOptions, ui.config.set_mode,
    function(value)
      if ui.config.set_mode == value then return end
      ui.config.set_mode = value
      ui.checkDone = false
      ui.planNotice = nil
      ui.fcNotice = nil
      ui.runtime.markDirty()
    end)
  if ui.config.set_mode == Setup.SET_MODE_CUSTOM then
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "set_mode_custom_note",
        "The set is whatever the flight controller carries. Nothing is written to it."))
  else
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "set_mode_standard_note",
        "Six banks of six parameters, known in advance. The flight controller is read to compare."))
  end

  cursorY = cursorY + appendNote(children, x, cursorY, w, describeCheck(i18n, checkResult()))

  -- The button that makes the model match what the verdict just reported. It sits here rather than
  -- in the wiring section because this is where that verdict is read.
  local btnW = math.min(240, w)
  local btnH = (lvgl and lvgl.UI_ELEMENT_HEIGHT) or Controls.CTRL_H or 32
  children[#children + 1] = {
    type = "button",
    x = x + math.floor((w - btnW) / 2), y = cursorY, w = btnW, h = btnH,
    text = t(i18n, "setup_model", "Set up the model"),
    press = function() offerSetup(i18n) end
  }
  cursorY = cursorY + btnH + 6

  if ui.planNotice then
    cursorY = cursorY + appendNote(children, x, cursorY, w, ui.planNotice)
  end

  -- The other half of the same job, and the only thing on this page that writes the FLIGHT
  -- CONTROLLER. Offered in the standard layout alone: in the custom one the set is whatever the
  -- board carries, and a button that overwrote it would overwrite the very thing being read.
  if ui.config.set_mode ~= Setup.SET_MODE_CUSTOM then
    children[#children + 1] = {
      type = "button",
      x = x + math.floor((w - btnW) / 2), y = cursorY, w = btnW, h = btnH,
      text = t(i18n, "setup_fc", "Set up the flight controller"),
      press = function()
        -- One run at a time. A second press while the first chain is on the wire would put two
        -- sets of writes into one queue with no order between them.
        if ui.fcRun == nil then offerFcSetup(i18n) end
      end
    }
    cursorY = cursorY + btnH + 6

    -- While a run is on, the moving line; when it is over, the fixed one it left behind. Never
    -- both, and the closure is not built at all once there is nothing for it to say.
    if ui.fcProgress then
      cursorY = cursorY + appendProgressNote(children, x, cursorY, w, function() return ui.fcProgress end)
    elseif ui.fcNotice then
      cursorY = cursorY + appendNote(children, x, cursorY, w, ui.fcNotice)
    end
  end
  return cursorY
end

local function appendNumber(children, x, y, w, label, key, minValue, maxValue, step)
  return Controls.appendNumberField(children, x, y, w, label, {
    min = minValue,
    max = maxValue,
    step = step or 1,
    get = function() return ui.config[key] end,
    set = function(value) markValue(key, value) end
  })
end

local function buildWiring(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + appendNote(children, x, cursorY, w,
    t(i18n, "wiring_note", "One mixer line per channel: MAX at the named variable's weight, added, no switch."))
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "bank_ch", "Enable channel"), "bank_ch", Setup.CHANNEL_MIN, Setup.CHANNEL_MAX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "value_ch", "Value channel"), "value_ch", Setup.CHANNEL_MIN, Setup.CHANNEL_MAX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "bank_gvar", "Enable variable"), "bank_gvar", 0, Setup.GVAR_MAX_INDEX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "value_gvar", "Value variable"), "value_gvar", 0, Setup.GVAR_MAX_INDEX)
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "pulse_ms", "Pulse length (ms)"), "pulse_ms", Setup.PULSE_MS_MIN, Setup.PULSE_MS_MAX, 10)
  cursorY = cursorY + appendNote(children, x, cursorY, w,
    t(i18n, "pulse_ms_note",
      "One press is one step. The board counts nothing before 100 ms of stillness and repeats only after 200 ms more."))

  -- The variables are fixed defaults now, so the model is walked to say when one of them is
  -- already spoken for rather than to choose a free pair. It is a warning and not a refusal: a
  -- pilot who knows what that line does may well want it.
  local conflicts = gvarConflicts()
  if type(conflicts) == "table" and #conflicts > 0 then
    local parts = {}
    for i = 1, #conflicts do
      parts[#parts + 1] = "GV" .. tostring(conflicts[i].index) .. " "
        .. t(i18n, "gvar_in_use", "is in use by") .. " " .. tostring(conflicts[i].where)
    end
    cursorY = cursorY + appendNote(children, x, cursorY, w, table.concat(parts, " / "))
  end
  return cursorY
end

--- Which trim does what.
--
-- Two arrangements, and the difference is how many trims a pilot has to spare. `rows` gives each
-- of the six rows its own trim, which is the layout the project's own radio setup documents;
-- `navigate` claims two -- one walks the whole set, one moves what the walk selected -- which is
-- what a radio with four trims can offer and what a pilot who does not want to remember six
-- positions asks for.
local function buildTrims(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
    t(i18n, "trims", "Drive rows from the trims"),
    ui.runtime.getBoolGetter("trims"),
    ui.runtime.getBoolSetter("trims"))

  if trimNames() == nil then
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "trims_unreadable", "This radio did not report its trims; the default order is used."))
  end

  local modeOptions = {
    { value = Setup.TRIM_MODE_ROWS, label = t(i18n, "trim_mode_rows", "One trim per row") },
    { value = Setup.TRIM_MODE_NAVIGATE, label = t(i18n, "trim_mode_navigate", "Walk and adjust") }
  }
  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    t(i18n, "trim_mode", "Trim layout"), modeOptions, ui.config.trim_mode,
    function(value)
      if ui.config.trim_mode == value then return end
      ui.config.trim_mode = value
      ui.checkDone = false
      ui.planNotice = nil
      ui.runtime.markDirty()
    end)

  if ui.config.trim_mode == Setup.TRIM_MODE_NAVIGATE then
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "navigate_note", "One trim steps through the parameters, the other moves the one it selected."))
    cursorY = cursorY + appendTrimPicker(children, x, cursorY, w,
      t(i18n, "bank_trim", "Bank trim"), trimField("bank_trim"))
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "bank_trim_note", "With a bank trim the walk trim stays inside the bank; without one it walks the whole set."))
    cursorY = cursorY + appendTrimPicker(children, x, cursorY, w,
      t(i18n, "nav_trim", "Walk trim"), trimField("nav_trim"))
    cursorY = cursorY + appendTrimPicker(children, x, cursorY, w,
      t(i18n, "adj_trim", "Adjust trim"), trimField("adj_trim"))
    return cursorY
  end

  local labels = {
    t(i18n, "row_1", "Row 1"),
    t(i18n, "row_2", "Row 2"),
    t(i18n, "row_3", "Row 3"),
    t(i18n, "row_4", "Row 4"),
    t(i18n, "row_5", "Row 5"),
    t(i18n, "row_6", "Row 6")
  }
  for row = 1, Setup.TRIM_COUNT do
    local index = row
    cursorY = cursorY + appendTrimPicker(children, x, cursorY, w, labels[row],
      function() return ui.config.rowTrim[index] or 0 end,
      function(value) ui.config.rowTrim[index] = value end)
  end
  return cursorY
end

local function buildUndo(children, x, y, w, i18n)
  local cursorY = y
  cursorY = cursorY + appendNote(children, x, cursorY, w,
    t(i18n, "undo_note", "The board saves an in-flight change itself, shortly after disarm, so the undo has to exist beforehand."))
  cursorY = cursorY + appendNumber(children, x, cursorY, w,
    t(i18n, "backup_profile", "Backup PID profile"), "backup_profile", 0, Setup.PROFILE_MAX)
  return cursorY
end

local SECTIONS = {
  { key = "general", titleKey = "section_general", titleFallback = "In-flight tuning", build = buildGeneral },
  { key = "wiring", titleKey = "section_wiring", titleFallback = "Channels and variables", build = buildWiring },
  { key = "trims", titleKey = "section_trims", titleFallback = "Rows and trims", build = buildTrims },
  { key = "undo", titleKey = "section_undo", titleFallback = "Undo", build = buildUndo }
}

function M.build(ctx)
  ensureDeps()
  ensureLoaded()
  ui.runtime.setRequestRebuild(ctx.requestRebuild)

  local children = ctx.children
  local x, w = ctx.x, ctx.w
  local i18n = ctx.i18n
  local cursorY = ctx.y

  if not hasModelStore() then
    cursorY = cursorY + appendNote(children, x, cursorY, w,
      t(i18n, "no_model", "Connect a flight controller: these settings are stored with the model."))
  end

  for i = 1, #SECTIONS do
    local section = SECTIONS[i]
    if i > 1 then cursorY = cursorY + 10 end
    Controls.appendSectionHeader(children, x, cursorY, w,
      t(i18n, section.titleKey, section.titleFallback),
      ui.sections[section.key],
      ui.runtime.getSectionToggleHandler(section.key))
    cursorY = cursorY + Controls.SECTION_H
    if ui.sections[section.key] then
      cursorY = section.build(children, x, cursorY, w, i18n)
    end
  end
end

function M.onClose()
  -- A READ the pilot walked away from is given up here, and its messages come out of the queue
  -- with it. His third radio round is the reason: he pressed the button, watched a screen that
  -- said nothing for twenty-eight seconds, pressed BACK -- and the chain went on running against
  -- a page that no longer existed, finishing nine seconds later with nobody to tell.
  --
  -- A WRITE is not given up, and that is deliberate: stopped half way it leaves the flight
  -- controller holding part of one adjustment set and part of another. The screen says so while it
  -- runs, which is the honest way round.
  if type(FcAction) == "table" and type(FcAction.cancel) == "function" then
    pcall(FcAction.cancel, ui)
  end

  Common.resetPageState(ui)
  ui.radio = nil
  ui.checkResult = nil
  ui.trimNames = nil
  ui.planNotice = nil
  -- What is left after the cancel above: a write still on the wire, whose callbacks all ask
  -- whether they still belong to the page's current run before touching anything.
  ui.fcRun = nil
  ui.fcProgress = nil
  ui.fcPhase = nil
  ui.fcNotice = nil
  Controls = nil
  Common = nil
  Setup = nil
  ConfirmDialog = nil
  FcAction = nil
  t = nil
end

return M
