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

  -- The trim layout is the one setting a pilot meets with his thumbs rather than his eyes, so
  -- the help says what each of the three trims does rather than leaving the field labels to
  -- carry it on their own.
  local trims = tr(i18n, "help_trims",
    "Walk and adjust: the bank trim steps the bank, the walk trim the row in it, the adjust trim the value.")

  -- What the ground surface is FOR, in the order a pilot uses it. The three buttons are three
  -- separate ideas and nothing on the screen says which comes first; the pilot who flew round 3
  -- pressed the read button because it was on the left.
  local flow = tr(i18n, "help_flow",
    "On the ground: choose the backup profile here, take the backup, fly, then read the difference or restore.")

  -- And the one button whose cost is worth stating. Reading the board is roughly twelve seconds
  -- of round trips, and the overlay does it once per connect on its own -- so the button exists
  -- for the case the automatic read cannot cover: an adjustment changed in the Configurator while
  -- the radio stayed connected.
  local read = tr(i18n, "help_read",
    "The board is read once per connect, about twelve seconds. Read again only after changing adjustments in the Configurator.")

  return {
    message = intro .. "\n\n" .. trims .. "\n\n" .. flow .. "\n\n" .. read
      .. "\n\n" .. setup .. "\n\n" .. setupFc
  }
end
