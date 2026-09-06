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

local M = {}

-- The switch picker's filters, as the firmware numbers them. Named here rather than reached for
-- as globals, following app/pages/setup_wizard/proc_radio.lua: SW_SWITCH is the physical switch
-- block, SW_NONE the empty entry that lets a pilot clear the choice. Trims are a filter of their
-- own and are deliberately not offered -- a trim is a row, not the interlock.
local SW_SWITCH = 1
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
  ui.proposed = false
  ui.gvarsShort = false
  ui.planNotice = nil
  ui.loaded = true
end

--- The two variables the model does not already use, offered rather than assumed.
--
-- The pilot's radio arrived with both variables unset and nothing on the page to say which ones
-- were free, so they are proposed -- VISIBLY, in the fields, where the numbers can be overruled
-- before they go anywhere. Nothing is written here and `ui.dirty` is deliberately NOT raised: a
-- proposal the pilot never looked at must not turn into a store write on the way out.
--
-- Runs once per visit, off the same latch as the check.
local function proposeGvars()
  if ui.proposed then return end
  ui.proposed = true
  local value, bank = Setup.proposeGvars(radio(), ui.config)
  if value ~= nil then ui.config.value_gvar = value end
  if bank ~= nil then ui.config.bank_gvar = bank end
  -- Two are needed and a busy model may not have two to spare; the verdict says so when it cannot.
  ui.gvarsShort = ((ui.config.value_gvar or 0) <= 0) or ((ui.config.bank_gvar or 0) <= 0)
end

local function trimNames()
  if ui.trimNames == nil then
    ui.trimNames = Setup.resolveTrims(radio()) or false
  end
  if ui.trimNames == false then return nil end
  return ui.trimNames
end

--- The setup check, cached.
--
-- `ui.checkDone` is the whole discipline: the walk runs when it is false and sets it, and only a
-- field's `set` puts it back. So a screen laid out again for any other reason -- a section opened,
-- a dialog closed, a rebuild the form runtime asked for -- costs no model reads at all.
local function checkResult()
  if not ui.checkDone then
    ui.checkDone = true
    ui.checkResult = Setup.check({ radio = radio(), settings = ui.config }, ui.config)
  end
  return ui.checkResult
end

--- The verdict in one sentence, grouped by the page of the radio's own menus a pilot has to open:
-- the mixer, the global variables, the trims. A list of one line per fault reads longer and says
-- the same thing.
local function describeCheck(i18n, result)
  if ui.gvarsShort then
    return t(i18n, "check_no_free_gvar", "Fewer than two free variables on this model")
  end
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
  ui.planNotice = nil
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
-- The sections
-- ---------------------------------------------------------------------------

local function appendNote(children, x, y, w, text)
  children[#children + 1] = {
    type = "label", x = x, y = y, w = w, text = text, color = COLOR_THEME_PRIMARY1, font = SMLSIZE
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
    t(i18n, "pulse_ms", "Step length (ms)"), "pulse_ms", Setup.PULSE_MS_MIN, Setup.PULSE_MS_MAX, 10)
  return cursorY
end

--- The six rows against the trims that drive them.
--
-- The options carry the radio's OWN trim names where they can be read: those labels are localised
-- and renameable, so a list of fixed stems would name something else on a radio set up
-- differently. Where they cannot be read the default order stands in.
local function trimOptions(i18n)
  local resolved = trimNames()
  local options = { { value = 0, label = t(i18n, "trim_off", "Off") } }
  local defaults = {
    t(i18n, "trim_1", "Rudder"),
    t(i18n, "trim_2", "Elevator"),
    t(i18n, "trim_3", "Throttle"),
    t(i18n, "trim_4", "Aileron"),
    t(i18n, "trim_5", "T5"),
    t(i18n, "trim_6", "T6")
  }
  for index = 1, Setup.TRIM_COUNT do
    local entry = resolved and resolved[index] or nil
    local label = (entry and entry.name) or defaults[index]
    options[#options + 1] = { value = index, label = label }
  end
  return options
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

  local options = trimOptions(i18n)

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
    cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
      t(i18n, "nav_trim", "Walk trim"), options, ui.config.nav_trim,
      function(value) markValue("nav_trim", tonumber(value) or 0) end)
    cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
      t(i18n, "adj_trim", "Adjust trim"), options, ui.config.adj_trim,
      function(value) markValue("adj_trim", tonumber(value) or 0) end)
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
    cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
      labels[row], options, ui.config.rowTrim[index],
      function(value)
        local chosen = tonumber(value) or 0
        if ui.config.rowTrim[index] == chosen then return end
        ui.config.rowTrim[index] = chosen
        ui.checkDone = false
        ui.planNotice = nil
        ui.runtime.markDirty()
      end)
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
  proposeGvars()
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
  Common.resetPageState(ui)
  ui.radio = nil
  ui.checkResult = nil
  ui.trimNames = nil
  ui.planNotice = nil
  Controls = nil
  Common = nil
  Setup = nil
  ConfirmDialog = nil
  t = nil
end

return M
