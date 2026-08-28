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

        -- Name over list, not name beside list.
        --
        -- These four were rows, and a row's value column is a fifth of the page wide with no room
        -- to wrap: every one of the lists ran past its own column, on three of the four
        -- geometries. Found by measuring across the elements rather than only down them, which is
        -- a check this bench did not have until the section beside this one was walked on a
        -- radio. Written as a heading and a sentence, the list wraps and nothing is dropped from
        -- it -- and what is listed here is exactly what the pilot must not assume is configured.
        local parts = {
          { "close_drivetrain", "Drivetrain",
            "close_drivetrain_what", "ESC, motor, battery, throttle range, governor" },
          { "close_servos", "Servos",
            "close_servos_what", "output parameters, direction, centre" },
          { "close_mechanics", "Mechanics",
            "close_mechanics_what", "swashplate, pitch limits, tail" },
          { "close_signoff", "Sign-off",
            "close_signoff_what", "arming test, throttle hold, failsafe, telemetry" }
        }
        for _, part in ipairs(parts) do
          y = y + w.row(children, area.x, y, area.w, t(i18n, part[1], part[2]), nil, nil)
          y = y + 2 + w.paragraph(children, area.x, y + 2, area.w, t(i18n, part[3], part[4]))
        end
      end
    }
  }
}

return procs
