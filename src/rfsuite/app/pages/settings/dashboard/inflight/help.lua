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

  -- The two buttons are the only things on this page that change anything but the settings, so
  -- the help says what each of them writes and that both ask first. They write different things:
  -- one the radio's own model, the other the flight controller's adjustment slots.
  local setup = tr(i18n, "help_setup",
    "Set up the model writes the mixer lines, the variables and the trim modes, after showing what it removes.")

  local setupFc = tr(i18n, "help_setup_fc",
    "Writes the standard set into the adjustment slots, after showing what it overwrites. Standard layout only.")

  return {
    message = intro .. "\n\n" .. setup .. "\n\n" .. setupFc
  }
end
