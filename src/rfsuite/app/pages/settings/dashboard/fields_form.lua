--[[
  The settings pages every theme that declares boxes shares: one page per flight phase, listing
  the tiles whose value the pilot can choose (widgets/dashboard/fields.lua), a Keys page
  binding the full-screen keys to the host's actions (widgets/dashboard/keys.lua), and an Info
  bar page choosing what the bar across the top of the full screen shows
  (widgets/dashboard/fullscreen_controls.lua `appendBar`).

  A theme's configure.lua makes one form, hands it the page the settings page opened, and lets
  it build and save that page; the theme's own settings stay its own. The form reads a phase
  module only for the page that lists it, so the theme's other pages load nothing of it.
]]

local function loadModule(path)
  local chunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. path, "t"))
  return chunk()
end

local Controls = loadModule("ui/controls.lua")
local Fields = loadModule("widgets/dashboard/fields.lua")
local GlobalKeys = loadModule("widgets/dashboard/keys.lua")

local M = {}

local KEY_NAMES = { pageDown = "PAGE >", pageUp = "PAGE <", mdl = "MDL", sys = "SYS", tele = "TELE" }

-- The Info bar page: one switch per item of the bar, in the bar's order, each on by default.
-- The keys are the ones the runtime reads (`bar_<item id>`); a value never stored counts as on.
local BAR_ITEMS = {
  { pref = "bar_clock", label = "@i18n(app.pages.settings_dashboard_settings.bar_clock)@" },
  { pref = "bar_tx_battery", label = "@i18n(app.pages.settings_dashboard_settings.bar_tx_battery)@" },
  { pref = "bar_link", label = "@i18n(app.pages.settings_dashboard_settings.bar_link)@" },
}

local function barItemOn(value)
  return not (value == false or value == "false" or value == 0 or value == "0")
end

-- One option list per catalogue, made once: the page builds a combo per tile from the same list.
local OPTIONS = {}
local function optionsOf(list)
  local options = OPTIONS[list]
  if options == nil then
    options = {}
    for i = 1, #list do options[i] = { value = list[i].id, label = list[i].label } end
    OPTIONS[list] = options
  end
  return options
end

-- What a phase module's boxes evaluate to on the settings page. A theme that builds its boxes in
-- a function reads its configuration from the state it is handed; the page hands it the theme's
-- configuration as the widget would and nothing else, which is all a box's source depends on.
local function phaseBoxes(path, config)
  local chunk = loadScript(path, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, module = pcall(chunk)
  if not ok or type(module) ~= "table" then return nil end
  local boxes = module.boxes
  if type(boxes) == "function" then
    local built
    ok, built = pcall(boxes, nil, { themeConfig = config or {} })
    boxes = ok and built or nil
  end
  return type(boxes) == "table" and boxes or nil
end

--- A form for one theme. `folder` is the theme's own folder as the settings page loads it
--- (ending in "/"), `phases` the phase pages it shows: `{ preflight = "preflight.lua", ... }`.
function M.new(folder, phases)
  local form = { folder = folder, phases = phases or {}, rows = nil, phase = nil, values = {} }

  --- The rows of `phase`, read from its module once per page visit; `config` is the theme's
  --- configuration as last loaded, for a theme that builds its boxes from it.
  function form.rowsFor(phase, config)
    if form.phase == phase and form.rows ~= nil then return form.rows end
    form.phase = phase
    local file = form.phases[phase]
    local boxes = file and phaseBoxes(form.folder .. file, config) or nil
    form.rows = Fields.rows(boxes, phase)
    return form.rows
  end

  --- The defaults of `page`'s settings, for the theme's defaults table: a tile's own value for a
  --- phase page, unbound for the Keys page. Registered with the library so a model's save drops
  --- a choice equal to the standard instead of storing it.
  function form.defaults(page, config, into)
    into = into or {}
    if page == "keys" then
      for i = 1, #GlobalKeys.THEME_KEYS do into[GlobalKeys.THEME_KEYS[i].pref] = "none" end
    elseif page == "bar" then
      for i = 1, #BAR_ITEMS do into[BAR_ITEMS[i].pref] = true end
    elseif form.phases[page] then
      local rows = form.rowsFor(page, config)
      for i = 1, #rows do
        if rows[i].default ~= nil then into[rows[i].key] = rows[i].default end
      end
    end
    return into
  end

  --- Take `page`'s values out of `config`, the theme's configuration as the library read it.
  function form.load(page, config)
    form.values = {}
    if type(config) ~= "table" then return end
    if page == "keys" then
      for i = 1, #GlobalKeys.THEME_KEYS do
        local pref = GlobalKeys.THEME_KEYS[i].pref
        form.values[pref] = config[pref] or "none"
      end
    elseif page == "bar" then
      for i = 1, #BAR_ITEMS do
        local pref = BAR_ITEMS[i].pref
        form.values[pref] = barItemOn(config[pref])
      end
    elseif form.phases[page] then
      local rows = form.rowsFor(page, config)
      for i = 1, #rows do form.values[rows[i].key] = config[rows[i].key] or rows[i].default end
    end
  end

  --- The values to save for the page last loaded, for DashboardLib.setThemeConfig.
  function form.save()
    return form.values
  end

  --- Whether `page` is one of the form's.
  function form.owns(page)
    return page == "keys" or page == "bar" or form.phases[page] ~= nil
  end

  --- Build `page` into `children` from `cursorY`; answers the cursor after it.
  function form.build(page, children, x, cursorY, w, config, dashboard)
    if page == "keys" then
      for i = 1, #GlobalKeys.THEME_KEYS do
        local entry = GlobalKeys.THEME_KEYS[i]
        local pref = entry.pref
        local label = "@i18n(app.pages.settings_dashboard_settings.theme_key)@ " .. (KEY_NAMES[entry.id] or entry.id)
        -- A key the radio-wide Keys page holds for every theme is marked and cannot be changed:
        -- what this page stored for it would have no effect.
        local held = GlobalKeys.global(dashboard, entry.id) ~= "theme"
        if held then label = label .. " " .. "@i18n(app.pages.settings_dashboard_settings.theme_key_global)@" end
        local opts = { helpText = "@i18n(app.pages.settings_dashboard_settings.theme_key_help)@" }
        if held then opts.active = false end
        cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w, label,
          GlobalKeys.THEME_OPTIONS, form.values[pref] or "none",
          function(value) if type(value) == "string" then form.values[pref] = value end end,
          opts)
      end
      return cursorY
    end

    if page == "bar" then
      for i = 1, #BAR_ITEMS do
        local pref = BAR_ITEMS[i].pref
        cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w, BAR_ITEMS[i].label,
          function() return form.values[pref] == true end,
          function(value) form.values[pref] = value == true end,
          { helpText = "@i18n(app.pages.settings_dashboard_settings.bar_help)@" })
      end
      return cursorY
    end

    local rows = form.rowsFor(page, config)
    for i = 1, #rows do
      local row = rows[i]
      local key = row.key
      local label = row.title or row.defaultLabel or "@i18n(app.pages.settings_dashboard_settings.field_tile)@"
      local help = (row.list == Fields.STATS)
        and "@i18n(app.pages.settings_dashboard_settings.field_help_stats)@"
        or "@i18n(app.pages.settings_dashboard_settings.field_help_live)@"
      cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w, label,
        optionsOf(row.list), form.values[key],
        function(value) if type(value) == "string" then form.values[key] = value end end,
        { helpText = help })
    end
    return cursorY
  end

  return form
end

return M
