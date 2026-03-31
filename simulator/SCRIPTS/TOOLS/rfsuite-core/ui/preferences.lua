-- ui/preferences.lua
-- Safe wrapper around lib/preferences.lua.
-- Provides lazy loading, pcall guards, and default fallback.
--
-- Usage:
--   local PreferencesSafe = loadModule("ui/preferences.lua")
--   local Prefs = PreferencesSafe.new(loadModule)
--   local data  = Prefs.load()
--   local ok, err = Prefs.save(data)

local PreferencesSafe = {}

local function defaultPreferences()
  return {
    general = {
      -- display
      iconsize                     = 2,
      txbatt_type                  = 0,
      theme_loader                 = 1,
      hs_loader                    = 0,
      toolbar_timeout              = 10,
      -- safety & prompts
      save_confirm                 = true,
      save_dirty_only              = true,
      save_armed_warning           = true,
      reload_confirm               = true,
      show_battery_profile_startup = true,
      show_confirmation_dialog     = true,
      -- integration
      syncname                     = false,
      -- development
      developer_tools              = false,
    },
    localizations = {
      temperature_unit = 0,
      altitude_unit    = 0,
    }
  }
end

-- Returns a { load, save, defaults } object.
-- `loadModuleFn` is the host's loadModule function so the path resolution
-- stays consistent with the rest of the build.
function PreferencesSafe.new(loadModuleFn)
  local module = nil   -- nil = not yet attempted, false = failed

  local function getModule()
    if module == false then return nil end
    if module ~= nil   then return module end

    local ok, result = pcall(function()
      return loadModuleFn("lib/preferences.lua")
    end)
    if ok and type(result) == "table" then
      module = result
      return module
    end
    module = false
    return nil
  end

  local function load()
    local prefs = defaultPreferences()
    local m = getModule()
    if not m or type(m.load) ~= "function" then return prefs end
    local ok, loaded = pcall(m.load)
    if ok and type(loaded) == "table" then return loaded end
    return prefs
  end

  local function save(prefs)
    local m = getModule()
    if not m or type(m.save) ~= "function" then
      return false, "Preferences unavailable in this build"
    end
    local ok, saveOk, err = pcall(m.save, prefs)
    if not ok then return false, tostring(saveOk) end
    return saveOk, err
  end

  return { load = load, save = save, defaults = defaultPreferences }
end

return PreferencesSafe
