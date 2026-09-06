-- The Settings > Dashboard > In-Flight Tuning page's flight controller action, on its own.
--
-- It is a module rather than part of page.lua for one measured reason. The page is opened on a
-- radio whose tool sits near its heap ceiling -- the pilot's froze there with 134 kB free -- and
-- everything a page's chunk holds is paid on ENTRY, whether the pilot presses anything or not.
-- This half is never needed to DRAW the page: it is wanted only after the button is pressed, and
-- it drags widgets/dashboard/inflight/fcsetup.lua and the whole adjustment function table behind
-- it. So it is read off the card then, and not before.
--
-- Everything it touches comes in through the context table: the page's own text helper, the
-- settings being edited, the page state it reports into, and the repaint it asks for. It reaches
-- for nothing on its own except the two modules it drives.

local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local FcSetup = nil
local ConfirmDialog = nil

-- The page's text helper, handed over on the press. A module-level local because the sentence
-- builders below are module-level too: they are built once per load rather than once per press.
local t = nil

-- How many slots are named one by one in the question. Past this the rest are counted instead: a
-- confirmation nobody reads to the end is not a confirmation.
local SLOT_LINES_SHOWN = 6

--- Why the flight controller cannot be read or written, in words.
--
-- Every reason the writer can answer with is named. A reason with no sentence of its own still
-- reaches the screen, appended to the general one, because a code the pilot can read out is worth
-- more than a polished sentence that hides which of eight things went wrong.
local function refusalText(i18n, reason)
  if reason == "armed" then
    return t(i18n, "fc_armed", "The model is armed.")
  elseif reason == "arm_unknown" then
    return t(i18n, "fc_arm_unknown", "The arming state cannot be read, so nothing is written.")
  elseif reason == "no_link" then
    return t(i18n, "fc_no_link", "No link to the flight controller.")
  elseif reason == "no_sensors" or reason == "no_api" then
    return t(i18n, "fc_unavailable", "This build cannot reach the flight controller.")
  elseif reason == "old_api" then
    return t(i18n, "fc_old_api", "This flight controller does not answer the paged reads.")
  elseif reason == "same_channel" then
    return t(i18n, "plan_same_channel", "The two channels have to be different.")
  elseif reason == "ena_channel" or reason == "adj_channel" then
    return t(i18n, "fc_channel", "No receiver channel of the flight controller reaches that channel.")
  end
  return t(i18n, "fc_failed", "The flight controller write failed") .. ": " .. tostring(reason)
end

--- What the board carries today, held against the standard set.
local function compareText(i18n, compare)
  local verdict = (type(compare) == "table") and compare.verdict or nil
  if verdict == "match" then
    return t(i18n, "fc_board_matches", "The flight controller already carries this set.")
  elseif verdict == "empty" then
    return t(i18n, "fc_board_empty", "The flight controller carries none of this set.")
  elseif verdict == "differ" then
    return string.format("%s %d", t(i18n, "fc_board_differs", "Slots differing from this set:"),
      compare.count)
  end
  return t(i18n, "fc_board_unknown", "The flight controller has not been compared.")
end

--- The question the pilot answers, built from the plan and not from what the page intended.
--
-- The counts come first because they are what cannot be taken back, and the two that matter get a
-- sentence and a list of their own rather than a number in a row: a slot being overwritten is a
-- parameter moving somewhere else on the screen, and a slot in use by another switch is a control
-- the pilot flies with that will stop working.
local function question(i18n, plan)
  local lines = {}
  lines[#lines + 1] = compareText(i18n, plan.compare)
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("%s %d (%d..%d)",
    t(i18n, "fc_write_slots", "Adjustment slots written:"), plan.writes,
    plan.slots[1].slot0, plan.slots[#plan.slots].slot0)
  lines[#lines + 1] = string.format("%s %d",
    t(i18n, "fc_overwritten", "Of them already in use:"), plan.overwritten)

  local shown = 0
  for i = 1, #plan.slots do
    local entry = plan.slots[i]
    if entry.overwritten then
      if shown >= SLOT_LINES_SHOWN then
        lines[#lines + 1] = string.format("  ... %d", plan.overwritten - shown)
        break
      end
      shown = shown + 1
      lines[#lines + 1] = string.format("  %d: %s -> %s", entry.slot0,
        tostring(entry.heldName), tostring(entry.name))
    end
  end

  if plan.otherSwitch > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("%s %d",
      t(i18n, "fc_other_switch", "In use by a switch on another channel:"), plan.otherSwitch)
    lines[#lines + 1] = t(i18n, "fc_other_switch_note", "Those switches stop adjusting anything.")
  end

  local kept = {}
  for i = 1, #plan.keep do kept[#kept + 1] = tostring(plan.keep[i].slot0) end
  lines[#lines + 1] = ""
  lines[#lines + 1] = string.format("%s %s",
    t(i18n, "fc_kept", "Left alone:"), table.concat(kept, ", "))

  -- The two things this action cannot check for itself and cannot work without. They are settings
  -- of the flight controller's own telemetry, not of its adjustments, so nothing read here says
  -- anything about them -- and without both the values never come back and every parameter on the
  -- tuning screen stays a dash.
  lines[#lines + 1] = ""
  lines[#lines + 1] = t(i18n, "fc_reminder",
    "The values only come back to the radio with telemetry sensor 99 selected and CRSF custom telemetry on.")
  return table.concat(lines, "\n")
end

--- Where the action has got to, for the line under the button.
local function progressText(i18n, run)
  local phase = run.phase
  local done, total = run.done or 0, run.total or 0
  if phase == FcSetup.PHASE_WRITING or phase == FcSetup.PHASE_COMMIT then
    return string.format("%s %d/%d", t(i18n, "fc_writing", "Writing"), done, total)
  elseif phase == FcSetup.PHASE_VERIFY then
    return string.format("%s %d/%d", t(i18n, "fc_verifying", "Reading back"), done, total)
  end
  return string.format("%s %d/%d", t(i18n, "fc_reading", "Reading the flight controller"), done, total)
end

--- Read, ask, write, read back -- and write nothing at all if the answer is no.
--
-- Every callback checks that the run it belongs to is still THIS page's run before it touches
-- anything on screen. A page that has been left still has its messages in the queue, and a write
-- already under way is deliberately not abandoned: a half-written adjustment table is a worse
-- state to leave a flight controller in than a finished one nobody watched.
function M.offer(ctx)
  local i18n = ctx.i18n
  local ui = ctx.state
  local requestRepaint = ctx.repaint
  t = ctx.t

  if FcSetup == nil then
    FcSetup = loadModule("widgets/dashboard/inflight/fcsetup.lua")
  end
  if type(FcSetup) ~= "table" then
    ui.fcNotice = t(i18n, "fc_unavailable", "This build cannot reach the flight controller.")
    requestRepaint()
    return
  end

  local run = FcSetup.newRun(ctx.config)
  ui.fcRun = run
  ui.fcPercent = nil

  local function mine()
    return ui.fcRun == run
  end

  local function progress()
    if not mine() then return end
    local total = run.total or 0
    local percent = (total > 0) and math.floor((run.done or 0) * 100 / total) or 0
    ui.fcNotice = progressText(i18n, run)
    -- A rebuild tears the screen down and builds it again, so it is worth doing only when the
    -- number on it has actually changed. Their own adjustments page throttles its save overlay
    -- the same way.
    if percent ~= ui.fcPercent then
      ui.fcPercent = percent
      requestRepaint()
    end
  end

  local function failed(_, reason)
    if not mine() then return end
    ui.fcRun = nil
    ui.fcNotice = refusalText(i18n, reason)
    requestRepaint()
  end

  local function done(_, report)
    if not mine() then return end
    ui.fcRun = nil
    if report.verdict == "match" then
      ui.fcNotice = string.format("%s (%d)",
        t(i18n, "fc_done", "Flight controller set up"), report.written)
    else
      -- The write said yes to every slot and the read-back disagrees, which is the one outcome
      -- worth spelling out: it is not a failure the queue reported and it is not a success.
      ui.fcNotice = string.format("%s (%d)",
        t(i18n, "fc_verify_differs", "Written, but the read-back does not match"), report.count)
    end
    requestRepaint()
  end

  local function planned(_, plan)
    if not mine() then return end
    if plan.ok ~= true then
      ui.fcRun = nil
      ui.fcNotice = refusalText(i18n, plan.refused)
      requestRepaint()
      return
    end

    if ConfirmDialog == nil then
      ConfirmDialog = loadModule("ui/confirm_dialog.lua")
    end

    local handlers = { onProgress = progress, onError = failed, onDone = done }
    local shown = false
    if ConfirmDialog and type(ConfirmDialog.show) == "function" then
      shown = ConfirmDialog.show({
        title = t(i18n, "setup_fc", "Set up the flight controller"),
        message = question(i18n, plan),
        onConfirm = function()
          if not mine() then return end
          FcSetup.apply(run, handlers)
        end,
        onCancel = function()
          -- Deliberately empty of writes AND deliberately present: a declined plan changes
          -- nothing, and saying so here is what keeps that from being an accident of the dialog's
          -- defaults.
          if not mine() then return end
          ui.fcRun = nil
          ui.fcNotice = t(i18n, "plan_cancelled", "Nothing was changed")
          requestRepaint()
        end
      })
    end

    if not shown then
      -- No confirmation could be put up, so there is no answer to act on. Writing a flight
      -- controller is not something to do on the assumption that the pilot would have said yes.
      ui.fcRun = nil
      ui.fcNotice = t(i18n, "plan_no_dialog", "This radio cannot show the confirmation.")
      requestRepaint()
    end
  end

  ui.fcNotice = progressText(i18n, run)
  requestRepaint()
  FcSetup.begin(run, { onProgress = progress, onPlan = planned, onError = failed, onDone = done })
end

return M
