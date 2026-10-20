-- Radio-wide fullscreen shortcuts. Theme choices stay in the theme's own table;
-- resolving a global override must never overwrite the keys a build will write again.
local M = {}

-- `default` is the choice a key has while the radio's preferences hold none for it: SYS opens
-- the suite's tool and TELE the quick menu, the two places a pilot on the full screen goes most;
-- the page keys and MDL are left to the theme. The defaults live here and nowhere else, so the
-- Keys page and the widget cannot disagree about them.
M.KEYS = {
  { id = "pageDown", pref = "key_page_down", default = "theme" },
  { id = "pageUp", pref = "key_page_up", default = "theme" },
  { id = "mdl", pref = "key_mdl", default = "theme" },
  { id = "sys", pref = "key_sys", default = "suite_tool" },
  { id = "tele", pref = "key_tele", default = "menu" },
}
M.OPTIONS = {
  { value = "theme", label = "@i18n(app.pages.settings_dashboard_keys.theme)@" },
  { value = "none", label = "@i18n(app.pages.settings_dashboard_keys.none)@" },
  { value = "menu", label = "@i18n(app.pages.settings_dashboard_keys.menu)@" },
  { value = "suite_tool", label = "@i18n(app.pages.settings_dashboard_keys.suite_tool)@" },
  { value = "flight_log", label = "@i18n(app.pages.settings_dashboard_keys.flight_log)@" },
  { value = "exit", label = "@i18n(app.pages.settings_dashboard_keys.exit)@" },
}
local ACTIONS = {
  none = "none", menu = "openView:menu", suite_tool = "openTool",
  flight_log = "openTool:tools_flight_log_page", exit = "exitFullscreen",
}
local BY_ID = {}
for i = 1, #M.KEYS do BY_ID[M.KEYS[i].id] = M.KEYS[i] end

-- A stored choice as one of the page's values. Theme is a choice of its own, stored as one where
-- it is not the key's default; anything absent or unknown is the key's default.
function M.choice(value, name)
  if value == "theme" or (type(value) == "string" and ACTIONS[value] ~= nil) then return value end
  local entry = BY_ID[name]
  return entry and entry.default or "theme"
end

-- The choice in force for key `name` on this radio: the stored one, else the key's default.
-- Anything but "theme" holds the key for every theme.
function M.global(dashboard, name)
  local entry = BY_ID[name]
  if entry == nil then return "theme" end
  return M.choice(type(dashboard) == "table" and dashboard[entry.pref] or nil, name)
end

-- The second result distinguishes a radio-wide choice from the theme's binding, and a deliberate
-- Nothing from an absent binding. A key on Theme uses `ctx.keys`, then the manifest's `keys`,
-- then nothing. Short RTN has no preference: view back/close and firmware long RTN keep ownership.
function M.resolve(dashboard, name, themeKeys, declaredKeys)
  local choice = M.global(dashboard, name)
  if choice ~= "theme" then return ACTIONS[choice], true end
  local action = type(themeKeys) == "table" and themeKeys[name] or nil
  if action == nil and type(declaredKeys) == "table" then action = declaredKeys[name] end
  return action, false
end

return M
