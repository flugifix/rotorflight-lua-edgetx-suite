local function tr(i18n, key, fallback)
  if i18n and i18n.t then
    local full = "app.pages.settings_dashboard_inflight." .. key
    local value = i18n.t(full)
    if value ~= full then return value end
  end
  return fallback
end

-- The blank line between two paragraphs of the help sheet.
local NL = "\n\n"

return function(ctx)
  local i18n = ctx and ctx.i18n or nil

  local intro = tr(i18n, "help_message",
    "Choose the interlock switch and the channels, variables and trims the overlay uses on this radio.")

  -- The one button on this page that changes anything but the settings, so the help says what it
  -- writes and that it asks first. Its counterpart -- the one that writes the flight controller's
  -- own adjustment slots -- went to the page that owns the flight controller's half.
  local setup = tr(i18n, "help_setup",
    "Set up the model writes the mixer lines, the variables and the trim modes, after showing what it removes.")

  -- The trim layout is the one setting a pilot meets with his thumbs rather than his eyes, so
  -- the help says what each of the three trims does rather than leaving the field labels to
  -- carry it on their own.
  local trims = tr(i18n, "help_trims",
    "Walk and adjust: the bank trim steps the bank, the walk trim the row in it, the adjust trim the value.")

  -- Where the other half is. The split is the pilot's after the third radio round and the one
  -- thing it costs him is knowing which page a setting is on, so both pages say.
  local flow = tr(i18n, "help_flow",
    "The flight controller's own half is in Setup > Controls > In-Flight Tuning.")

  return {
    message = intro .. NL .. trims .. NL .. setup .. NL .. flow
  }
end
