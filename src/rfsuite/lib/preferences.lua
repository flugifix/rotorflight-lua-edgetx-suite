local M = {}

local PREF_PATH = "/SCRIPTS/TOOLS/rfsuite.user/preferences.ini"

local function trim(s)
  local asString = tostring(s or "")
  asString = string.gsub(asString, "^%s+", "")
  asString = string.gsub(asString, "%s+$", "")
  return asString
end

local function parseValue(v)
  local t = trim(v)
  local lower = string.lower(t)
  if lower == "true" then return true end
  if lower == "false" then return false end
  local n = tonumber(t)
  if n ~= nil then return n end
  return t
end

local function serializeValue(v)
  local vt = type(v)
  if vt == "boolean" then
    return v and "true" or "false"
  end
  if vt == "number" then
    return tostring(v)
  end
  return tostring(v)
end

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
      show_battery_profile_startup = true,
      show_confirmation_dialog     = true,
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
    }
  }
end

function M.getPath()
  return PREF_PATH
end

local function loadFileAsString(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end

  local content = io.read(f, 2048)
  io.close(f)

  if content == nil or content == "" then
    return nil
  end

  return content
end

function M.load()
  local prefs = defaultPreferences()
  local content = loadFileAsString(PREF_PATH)
  if not content then
    return prefs, false
  end

  local section = nil
  for line in string.gmatch(content, "[^\r\n]+") do
    local normalized = trim(line)
    if normalized ~= "" and string.sub(normalized, 1, 1) ~= ";" and string.sub(normalized, 1, 1) ~= "#" then
      local sec = string.match(normalized, "^%[(.-)%]$")
      if sec then
        section = trim(sec)
        if prefs[section] == nil then
          prefs[section] = {}
        end
      else
        local k, v = string.match(normalized, "^([^=]+)=(.*)$")
        if k and v and section then
          prefs[section][trim(k)] = parseValue(v)
        end
      end
    end
  end

  return prefs, true
end

-- Writes ALL sections and keys from prefs to the INI file.
-- No field list to maintain — adding a key to prefs automatically persists it.
function M.save(prefs)
  local f, err = io.open(PREF_PATH, "w")
  if not f then return false, err end

  for section, values in pairs(prefs or {}) do
    if type(values) == "table" then
      io.write(f, "[" .. tostring(section) .. "]\n")
      for k, v in pairs(values) do
        io.write(f, tostring(k) .. "=" .. serializeValue(v) .. "\n")
      end
    end
  end

  io.close(f)
  return true
end

return M
