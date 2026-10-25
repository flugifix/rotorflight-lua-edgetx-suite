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
  local t = Common and Common.pageT("settings_dashboard_inflight") or function(_, _, fb) return fb end
  local i18n = ctx and ctx.i18n or nil

  -- One intro line, then one line per setting in the order the page shows them, each starting
  -- with the label as it reads on screen. How the overlay itself is flown is the docs page's.
  local intro = t(i18n, "help_message",
    "Wiring applies to all models; the flight list belongs to this model. Shown once Settings > General > Preview is on.")

  -- The one button on this page that changes anything but the settings, so the help says that it
  -- asks first. Its counterpart for the flight controller's own slots is on Setup > Controls.
  local setup = t(i18n, "help_setup",
    "Set up the model: shows what it will change on the radio before it writes.")

  -- The link carries these two channels, and an ExpressLRS switch mode quantises both of them to a
  -- fixed number of positions. The windows the flight controller decodes are 50 microseconds wide,
  -- so a quantised code can land in the gap beside its own window or inside the neighbouring row's.
  local link = t(i18n, "help_link",
    "Enable channel: on ExpressLRS use a Wide or full-resolution switch mode; Hybrid can select the wrong parameter.")

  local trims = t(i18n, "help_trims",
    "Drive rows from the trims: optional and off by default; touch, PAGE and the encoder work without them.")

  -- The flight list is stored by the model's MCU identity, so saving it needs the board.
  local owner = t(i18n, "help_owner",
    "All parameters: offers everything the board carries; when off, keep at least one group. Saving needs the FC connected.")

  return {
    message = intro .. "\n" .. setup .. "\n" .. link .. "\n" .. trims .. "\n" .. owner
  }
end
