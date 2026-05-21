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
      language                     = "en",
      iconsize                     = 2,
      txbatt_type                  = 0,
      theme_loader                 = 1,
      hs_loader                    = 0,
      toolbar_timeout              = 10,
      -- safety & prompts
      save_confirm                 = true,
      save_armed_warning           = true,
      reload_confirm               = true,
      -- integration
      syncname                     = false,
      auto_msp_telem_sync         = false,
      -- development
      developer_tools              = false,
      continuous_memory_log        = false,
      show_header_memory           = false,
      enable_serial_debug          = false,
      debug_level                  = "off",
    },
    localizations = {
      temperature_unit = 0,
      altitude_unit    = 0,
    },
    audio_events = {
      arming_flags = true,
      governor_state = true,
      voltage_alert = true,
      pid_profile = true,
      rate_profile = true,
      esc_temperature = false,
      esc_threshold = 90,
      adjustment_events = false,
      fuel_alerts = true,
      battery_profile = true,
      model_announcement = false,
    },
    audio_switches = {
      flight_mode_switch = false,
      arm_disarm_switch = false,
      stabilize_mode_switch = false,
      acro_mode_switch = false,
      altitude_hold_switch = false,
      position_hold_switch = false,
      return_to_home_switch = false,
      channel_6_switch = false,
      switch_feedback = false,
    },
    audio_timer = {
      timer1_alerts = false,
      timer2_alerts = false,
      timer3_alerts = false,
      flight_time_alert = false,
      battery_timer = false,
      armed_timer = false,
      count_down_timer = false,
      count_up_timer = false,
      timer_bell_sound = false,
    },
    dashboard = {
      theme_preflight = "system/default",
      theme_inflight = "system/default",
      theme_postflight = "system/default",
      model_override = false,
      model_theme_preflight = "nil",
      model_theme_inflight = "nil",
      model_theme_postflight = "nil",
      theme_config_target = "system/default",
      connection_guard = true,
    },
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
