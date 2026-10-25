-- The translator reaches this sheet through the house form: a `pageT` call the i18n precompiler
-- can derive a prefix from, and a wrapper named `t`, which is one of the two call names the
-- precompiler's pattern knows. A hand-rolled wrapper spelled anything else is a runtime lookup
-- only, and a packaged card carries no locale bundle, so the sheet would ship its English
-- fallbacks into a German install (#284).
local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

return function(ctx)
  local Common = loadModule("app/pages/settings/common.lua")
  local t = Common and Common.pageT("setup_controls_inflight") or function(_, _, fb) return fb end
  local i18n = ctx and ctx.i18n or nil

  -- One intro line, then one line per setting in the order the page shows them, each starting
  -- with the label as it reads on screen.
  local intro = t(i18n, "help_message",
    "Tuning offers what the FC slots hold, read on the ground; unread profiles refuse steps.")

  -- Two switches, and the one on this page is the smaller of them. A pilot who turns this on and
  -- finds nothing happening is looking at the radio's, which is on the dashboard settings.
  local enabled = t(i18n, "help_enabled",
    "In-flight tuning on this model: In-flight tuning on this radio (Settings > Dashboard) must be on too.")

  -- The steps are written INTO the slots, so changing one on the radio and not on the board leaves
  -- the two disagreeing, unless the pilot has been told which button puts it right.
  local step = t(i18n, "help_step",
    "Step size: written into the FC slots; after a change, set up the flight controller again. Head speed step works the same.")

  -- The one button here that changes anything on the board: it overwrites a slot whichever switch
  -- that slot belongs to, so it names them first.
  local setupFc = t(i18n, "help_setup_fc",
    "Set up the flight controller: writes the standard layout of 36 parameters and lists the slots it overwrites first.")

  -- The undo. It exists BEFORE the flight or not at all: the board writes an in-flight change to
  -- its own storage half a second after disarm, and there is nothing left to copy afterwards.
  local undo = t(i18n, "help_undo",
    "Undo: a ground read stores every reachable PID/rate profile on SD; Restore asks first, verifies and returns to the original profiles.")

  return {
    message = intro .. "\n" .. enabled .. "\n" .. step .. "\n" .. setupFc .. "\n" .. undo
  }
end
