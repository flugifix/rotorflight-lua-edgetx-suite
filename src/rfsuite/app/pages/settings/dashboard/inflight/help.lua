local function tr(i18n, key, fallback)
  if i18n and i18n.t then
    local full = "app.pages.settings_dashboard_inflight." .. key
    local value = i18n.t(full)
    if value ~= full then return value end
  end
  return fallback
end

return function(ctx)
  local i18n = ctx and ctx.i18n or nil

  local intro = tr(i18n, "help_message",
    "Choose the interlock switch, the channels, variables and trims it uses, and a spare PID profile as the undo.")

  -- The button is the one thing on this page that changes the model rather than the settings, so
  -- the help says what it writes and that it asks first.
  local setup = tr(i18n, "help_setup",
    "Set up the model writes the mixer lines, the variables and the trim modes, after showing what it removes.")

  return {
    message = intro .. "\n\n" .. setup
  }
end
