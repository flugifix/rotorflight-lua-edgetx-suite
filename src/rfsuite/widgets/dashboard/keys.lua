-- Radio-wide fullscreen shortcuts. Theme choices stay in the theme's own table;
-- resolving a global override must never overwrite the keys a build will write again.
local M = {}

M.KEYS = {
  { id = "pageDown", pref = "key_page_down", label = "@i18n(app.pages.settings_dashboard_keys.page_down)@" },
  { id = "pageUp", pref = "key_page_up", label = "@i18n(app.pages.settings_dashboard_keys.page_up)@" },
  { id = "mdl", pref = "key_mdl", label = "@i18n(app.pages.settings_dashboard_keys.mdl)@" },
  { id = "sys", pref = "key_sys", label = "@i18n(app.pages.settings_dashboard_keys.sys)@" },
  { id = "tele", pref = "key_tele", label = "@i18n(app.pages.settings_dashboard_keys.tele)@" },
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
local PREFS = {}
for i = 1, #M.KEYS do PREFS[M.KEYS[i].id] = M.KEYS[i].pref end

function M.choice(value)
  if type(value) == "string" and ACTIONS[value] ~= nil then return value end
  return "theme"
end

-- The second result distinguishes a deliberate Nothing from an absent binding.
-- Short RTN has no preference: view back/close and firmware long RTN keep ownership.
function M.resolve(dashboard, name, themeKeys, declaredKeys)
  local pref = PREFS[name]
  local choice = pref and type(dashboard) == "table" and M.choice(dashboard[pref]) or "theme"
  if choice ~= "theme" then return ACTIONS[choice], true end
  local action = type(themeKeys) == "table" and themeKeys[name] or nil
  if action == nil and type(declaredKeys) == "table" then action = declaredKeys[name] end
  return action, false
end

return M
