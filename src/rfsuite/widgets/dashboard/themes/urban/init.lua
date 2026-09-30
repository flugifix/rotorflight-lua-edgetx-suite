local init = {
  name = "Urban",
  -- One module for both: the flight view does not change shape at spool-up.
  preflight = "flight.lua",
  inflight = "flight.lua",
  postflight = "postflight.lua",
  -- No `armed` and no `offline` module, and both are decisions rather than omissions.
  --
  -- A host that knows the two extra phases lets a theme REFINE two of the three: `armed` refines
  -- the ground screen, `offline` the post-flight one, and a theme naming no module for them
  -- draws the module of the phase they refine -- without rebuilding anything, because the scene
  -- already standing is the one that would be built.
  --
  -- `armed` would draw this theme's flight view either way: the view does not change shape at
  -- spool-up, and the bottom bar already says ARMED in the arm-state colour the moment the arm
  -- flag turns. A module for it would be a second copy of one file to keep in step for nothing.
  --
  -- `offline` DOES show something different -- the numbers are final and the model cannot be
  -- armed again -- but it is one word on one line, and postflight.lua draws it from
  -- `state.flightMode` in a per-frame closure. So the change reaches the screen without a
  -- module the host has to load, and there is one statistics view rather than two that must
  -- not drift apart.
  configure = "configure.lua",
  standalone = false,
  -- A host that knows this key draws this theme at the full screen size instead of the quick
  -- menu; one that does not know it ignores the key and full screen stays the quick menu.
  fullscreen = "theme",
  -- The way out of full screen is a long press on RTN, which the firmware always honours, so
  -- this theme draws no close control. The one control it binds is the menu glyph in the top
  -- bar (layout.lua, L.menuControl).
  fullscreenExit = "longRtn",
  -- The settings of this theme are three pages rather than one long form. A host that knows
  -- `pages` opens the theme's tile on a grid of these and hands the chosen one to the
  -- configure module as `ctx.page`; a host that does not know it ignores the field and shows
  -- the whole form, which is what the module does when no page arrives. `icon` is relative
  -- to this folder.
  --
  -- An id named here has to be named in configure.lua as well, and the two live in different
  -- files: an id this list carries that that module does not know falls through to its
  -- `only == nil` branch and draws the WHOLE form on that one tile -- silently, with nothing
  -- raising anywhere.
  --
  -- Each title is a quoted string literal, and that is not a style choice: the packager reads
  -- `pages` out of this file as TEXT, with a regular expression that wants `title = "..."`
  -- (bin/package/build_package.py, parse_theme_pages), and drops an entry without one without
  -- a word. A translation marker is such a literal. The generated theme index is written into
  -- the staged tree before the markers are resolved, so the marker is resolved in the index
  -- and in this file alike, and a radio reading either one gets the title in its language.
  pages = {
    { id = "look",   title = "@i18n(app.pages.settings_dashboard_settings.urban_page_look)@",   icon = "icons/look.png" },
    { id = "rows",   title = "@i18n(app.pages.settings_dashboard_settings.urban_page_rows)@",   icon = "icons/rows.png" },
    { id = "topbar", title = "@i18n(app.pages.settings_dashboard_settings.urban_page_topbar)@", icon = "icons/topbar.png" },
  },
}

return init
