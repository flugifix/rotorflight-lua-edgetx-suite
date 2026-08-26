-- The close of the part of the path this assistant covers.
--
-- It is NOT the review. The review belongs to sign-off, where the machine is assembled and the
-- checks it collects can mean something; one here would have to tick procedures whose subject
-- does not exist yet, and a tick the assistant cannot have earned is worse than no tick at all.
-- So there is no derived mark on this screen.
--
-- What it does carry is the other half, and it is the half a pilot is normally not told: what
-- this run did NOT cover. An assistant that ends in silence has told the pilot they are finished,
-- and the machine at this point cannot be spooled up safely -- the drivetrain, the servos and the
-- mechanics are all still at their defaults.

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local Common = loadModule("app/pages/settings/common.lua")
local t = Common and Common.pageT("setup_wizard") or function(_, _, fb) return fb end

local procs = {}

procs[#procs + 1] = {
  id = "close",
  -- Its own section, so the heading does not claim it belongs to the flight controller, and
  -- uncounted, so it never appears on the overview as a piece of work with a state.
  section = "close",
  counted = false,
  title = function(i18n) return t(i18n, "step_close", "Done for now") end,
  screens = {
    {
      id = "done",
      build = function(w, ctx, area)
        local children, i18n, y = ctx.children, ctx.i18n, area.y

        y = y + w.paragraph(children, area.x, y, area.w,
          t(i18n, "close_p1",
            "The transmitter and the basics on the flight controller are set. Anything you change later can be run again on its own from the list.")) + 8

        y = y + w.paragraph(children, area.x, y, area.w,
          t(i18n, "close_p2",
            "This machine is not ready to spool up. These parts are not covered here and are still at their defaults:")) + 6

        y = y + w.row(children, area.x, y, area.w,
          t(i18n, "close_drivetrain", "Drivetrain"),
          t(i18n, "close_drivetrain_what", "ESC, motor, battery, throttle range, governor"), nil)
        y = y + w.row(children, area.x, y, area.w,
          t(i18n, "close_servos", "Servos"),
          t(i18n, "close_servos_what", "output parameters, direction, centre"), nil)
        y = y + w.row(children, area.x, y, area.w,
          t(i18n, "close_mechanics", "Mechanics"),
          t(i18n, "close_mechanics_what", "swashplate, pitch limits, tail"), nil)
        y = y + w.row(children, area.x, y, area.w,
          t(i18n, "close_signoff", "Sign-off"),
          t(i18n, "close_signoff_what", "arming test, throttle hold, failsafe, telemetry"), nil)
      end
    }
  }
}

return procs
