-- The page titles follow the theme's language, resolved as common.lua's M.resolveLanguage does
-- it -- the suite's locale module where it is already loaded (a global; nothing is loaded here),
-- the package's language baked in by the packager, the radio's -- restated in a few lines
-- rather than loaded, because this file is read on every theme load and must stay that cheap.
local BAKED = "@i18n_language@"
local function language()
  local mod = type(_G) == "table" and _G.__rfsuite_system_locale_module or nil
  if type(mod) == "table" and type(mod.resolveSystemLanguage) == "function" then
    local ok, lang = pcall(mod.resolveSystemLanguage, "en")
    if ok and type(lang) == "string" then return string.lower(string.sub(lang, 1, 2)) end
  end
  if BAKED ~= "@i18n_" .. "language@" then return string.lower(string.sub(BAKED, 1, 2)) end
  if type(getGeneralSettings) == "function" then
    local ok, g = pcall(getGeneralSettings)
    if ok and type(g) == "table" and type(g.language) == "string" then
      return string.lower(string.sub(g.language, 1, 2))
    end
  end
  return "en"
end

-- One table per language, keyed by page id. English is the only one; a language without a
-- table here reads English.
local TITLES = {
  en = { look = "Look", rows = "Value Rows", topbar = "Top Bar" },
}
local titles = TITLES[language()] or TITLES.en

-- The titles stay string LITERALS in the table below and are replaced after it is built, and
-- that is not a style choice: the packager reads `pages` out of this file as TEXT, with a
-- regular expression that wants `title = "..."` (bin/package/build_package.py,
-- parse_theme_pages), and drops an entry without one without a word. A radio that reads the
-- generated theme index instead of this file therefore gets the literal titles, and one that
-- runs this file gets the ones for its language.

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
  pages = {
    { id = "look",   title = "Look",       icon = "icons/look.png" },
    { id = "rows",   title = "Value Rows", icon = "icons/rows.png" },
    { id = "topbar", title = "Top Bar",    icon = "icons/topbar.png" },
  },
}

for i = 1, #init.pages do
  local page = init.pages[i]
  page.title = titles[page.id] or page.title
end

return init
