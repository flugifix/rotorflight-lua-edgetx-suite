-- The flight controller's adjustment functions, and the channel geometry that reaches them.
--
-- Rotorflight drives its stepped adjustments from two RC channels: one arms a slot (the enable
-- channel) and one carries the step (the value channel). fc/rc_adjustments.c accepts a step only
-- after the value channel has stood still inside one window for TRIGGER_DELAY, so every control
-- on the tuning screen is a PULSE to a fixed magnitude and never a movement.
--
-- Nothing in this file probes. It is a table and arithmetic, so the widget pass, a reactive
-- closure and a settings page can all read it.

local M = {}

-- Their packager rewrites every literal t("widgets.dashboard.<key>", "FALLBACK") call site into
-- the locale being built (bin/package/build_package.py, .vscode/scripts/precompile_i18n.py). In a
-- tree that has not been packaged the call survives and answers with its own English fallback,
-- which is what the simulator and the offline accounting run see.
local function t(_key, fallback)
  return fallback
end

-- Every adjustment function the firmware exposes, with the value range their own adjustments
-- page uses. The names are the ones that page shows, so a parameter reads the same wherever the
-- pilot meets it (app/pages/setup/controls/adjustments/page.lua, ADJUST_FUNCTIONS).
--
-- Ids 30 and 31 are deliberately absent: YAW_COLLECTIVE_DYN and YAW_COLLECTIVE_DECAY have no
-- ADJ_ENTRY in 4.6 firmware, so a slot naming them can never fire and a row offering them would
-- promise a step that is not made.
M.FUNCTIONS = {
  { id = 1, name = t("widgets.dashboard.fn_rate_profile", "Rate Profile"), min = 1, max = 6 },
  { id = 2, name = t("widgets.dashboard.fn_pid_profile", "PID Profile"), min = 1, max = 6 },
  { id = 3, name = t("widgets.dashboard.fn_led_profile", "LED Profile"), min = 1, max = 4 },
  { id = 4, name = t("widgets.dashboard.fn_osd_profile", "OSD Profile"), min = 1, max = 3 },
  { id = 5, name = t("widgets.dashboard.fn_pitch_rate", "Pitch Rate"), min = 0, max = 255 },
  { id = 6, name = t("widgets.dashboard.fn_roll_rate", "Roll Rate"), min = 0, max = 255 },
  { id = 7, name = t("widgets.dashboard.fn_yaw_rate", "Yaw Rate"), min = 0, max = 255 },
  { id = 8, name = t("widgets.dashboard.fn_pitch_rc_rate", "Pitch RC Rate"), min = 0, max = 255 },
  { id = 9, name = t("widgets.dashboard.fn_roll_rc_rate", "Roll RC Rate"), min = 0, max = 255 },
  { id = 10, name = t("widgets.dashboard.fn_yaw_rc_rate", "Yaw RC Rate"), min = 0, max = 255 },
  { id = 11, name = t("widgets.dashboard.fn_pitch_rc_expo", "Pitch RC Expo"), min = 0, max = 100 },
  { id = 12, name = t("widgets.dashboard.fn_roll_rc_expo", "Roll RC Expo"), min = 0, max = 100 },
  { id = 13, name = t("widgets.dashboard.fn_yaw_rc_expo", "Yaw RC Expo"), min = 0, max = 100 },
  { id = 14, name = t("widgets.dashboard.fn_pitch_p", "Pitch P"), min = 0, max = 250 },
  { id = 15, name = t("widgets.dashboard.fn_pitch_i", "Pitch I"), min = 0, max = 250 },
  { id = 16, name = t("widgets.dashboard.fn_pitch_d", "Pitch D"), min = 0, max = 250 },
  { id = 17, name = t("widgets.dashboard.fn_pitch_f", "Pitch F"), min = 0, max = 250 },
  { id = 18, name = t("widgets.dashboard.fn_roll_p", "Roll P"), min = 0, max = 250 },
  { id = 19, name = t("widgets.dashboard.fn_roll_i", "Roll I"), min = 0, max = 250 },
  { id = 20, name = t("widgets.dashboard.fn_roll_d", "Roll D"), min = 0, max = 250 },
  { id = 21, name = t("widgets.dashboard.fn_roll_f", "Roll F"), min = 0, max = 250 },
  { id = 22, name = t("widgets.dashboard.fn_yaw_p", "Yaw P"), min = 0, max = 250 },
  { id = 23, name = t("widgets.dashboard.fn_yaw_i", "Yaw I"), min = 0, max = 250 },
  { id = 24, name = t("widgets.dashboard.fn_yaw_d", "Yaw D"), min = 0, max = 250 },
  { id = 25, name = t("widgets.dashboard.fn_yaw_f", "Yaw F"), min = 0, max = 250 },
  { id = 26, name = t("widgets.dashboard.fn_yaw_cw_stop_gain", "Yaw CW Stop Gain"), min = 25, max = 250 },
  { id = 27, name = t("widgets.dashboard.fn_yaw_ccw_stop_gain", "Yaw CCW Stop Gain"), min = 25, max = 250 },
  { id = 28, name = t("widgets.dashboard.fn_yaw_cyclic_ff", "Yaw Cyclic FF"), min = 0, max = 250 },
  { id = 29, name = t("widgets.dashboard.fn_yaw_collective_ff", "Yaw Collective FF"), min = 0, max = 250 },
  { id = 32, name = t("widgets.dashboard.fn_pitch_collective_ff", "Pitch Collective FF"), min = 0, max = 250 },
  { id = 33, name = t("widgets.dashboard.fn_pitch_gyro_cutoff", "Pitch Gyro Cutoff"), min = 0, max = 250 },
  { id = 34, name = t("widgets.dashboard.fn_roll_gyro_cutoff", "Roll Gyro Cutoff"), min = 0, max = 250 },
  { id = 35, name = t("widgets.dashboard.fn_yaw_gyro_cutoff", "Yaw Gyro Cutoff"), min = 0, max = 250 },
  { id = 36, name = t("widgets.dashboard.fn_pitch_dterm_cutoff", "Pitch Dterm Cutoff"), min = 0, max = 250 },
  { id = 37, name = t("widgets.dashboard.fn_roll_dterm_cutoff", "Roll Dterm Cutoff"), min = 0, max = 250 },
  { id = 38, name = t("widgets.dashboard.fn_yaw_dterm_cutoff", "Yaw Dterm Cutoff"), min = 0, max = 250 },
  { id = 39, name = t("widgets.dashboard.fn_rescue_climb_collective", "Rescue Climb Coll"), min = 0, max = 1000 },
  { id = 40, name = t("widgets.dashboard.fn_rescue_hover_collective", "Rescue Hover Coll"), min = 0, max = 1000 },
  { id = 41, name = t("widgets.dashboard.fn_rescue_hover_altitude", "Rescue Hover Alt"), min = 0, max = 2500 },
  { id = 42, name = t("widgets.dashboard.fn_rescue_alt_p", "Rescue Alt P"), min = 0, max = 250 },
  { id = 43, name = t("widgets.dashboard.fn_rescue_alt_i", "Rescue Alt I"), min = 0, max = 250 },
  { id = 44, name = t("widgets.dashboard.fn_rescue_alt_d", "Rescue Alt D"), min = 0, max = 250 },
  { id = 45, name = t("widgets.dashboard.fn_angle_level_gain", "Angle Level Gain"), min = 0, max = 200 },
  { id = 46, name = t("widgets.dashboard.fn_horizon_level_gain", "Horizon Level Gain"), min = 0, max = 200 },
  { id = 47, name = t("widgets.dashboard.fn_acro_trainer_gain", "Acro Trainer Gain"), min = 25, max = 255 },
  { id = 48, name = t("widgets.dashboard.fn_governor_gain", "Governor Gain"), min = 0, max = 250 },
  { id = 49, name = t("widgets.dashboard.fn_governor_p", "Governor P"), min = 0, max = 250 },
  { id = 50, name = t("widgets.dashboard.fn_governor_i", "Governor I"), min = 0, max = 250 },
  { id = 51, name = t("widgets.dashboard.fn_governor_d", "Governor D"), min = 0, max = 250 },
  { id = 52, name = t("widgets.dashboard.fn_governor_f", "Governor F"), min = 0, max = 250 },
  { id = 53, name = t("widgets.dashboard.fn_governor_tta", "Governor TTA"), min = 0, max = 250 },
  { id = 54, name = t("widgets.dashboard.fn_governor_cyclic_ff", "Gov Cyclic FF"), min = 0, max = 250 },
  { id = 55, name = t("widgets.dashboard.fn_governor_collective_ff", "Gov Collective FF"), min = 0, max = 250 },
  { id = 56, name = t("widgets.dashboard.fn_pitch_b", "Pitch B"), min = 0, max = 250 },
  { id = 57, name = t("widgets.dashboard.fn_roll_b", "Roll B"), min = 0, max = 250 },
  { id = 58, name = t("widgets.dashboard.fn_yaw_b", "Yaw B"), min = 0, max = 250 },
  { id = 59, name = t("widgets.dashboard.fn_pitch_o", "Pitch O"), min = 0, max = 250 },
  { id = 60, name = t("widgets.dashboard.fn_roll_o", "Roll O"), min = 0, max = 250 },
  { id = 61, name = t("widgets.dashboard.fn_cross_coupling_gain", "Cross Coupling Gain"), min = 0, max = 250 },
  { id = 62, name = t("widgets.dashboard.fn_cross_coupling_ratio", "Cross Coupling Ratio"), min = 0, max = 250 },
  { id = 63, name = t("widgets.dashboard.fn_cross_coupling_cutoff", "Cross Coupling Cutoff"), min = 0, max = 250 },
  { id = 64, name = t("widgets.dashboard.fn_acc_trim_pitch", "Acc Trim Pitch"), min = -300, max = 300 },
  { id = 65, name = t("widgets.dashboard.fn_acc_trim_roll", "Acc Trim Roll"), min = -300, max = 300 },
  { id = 66, name = t("widgets.dashboard.fn_yaw_inertia_precomp_gain", "Yaw Inertia Precomp Gain"), min = 0, max = 250 },
  { id = 67, name = t("widgets.dashboard.fn_yaw_inertia_precomp_cutoff", "Yaw Inertia Precomp Cutoff"), min = 0, max = 250 },
  { id = 68, name = t("widgets.dashboard.fn_pitch_setpoint_boost_gain", "Pitch Setpoint Boost Gain"), min = 0, max = 255 },
  { id = 69, name = t("widgets.dashboard.fn_roll_setpoint_boost_gain", "Roll Setpoint Boost Gain"), min = 0, max = 255 },
  { id = 70, name = t("widgets.dashboard.fn_yaw_setpoint_boost_gain", "Yaw Setpoint Boost Gain"), min = 0, max = 255 },
  { id = 71, name = t("widgets.dashboard.fn_col_setpoint_boost_gain", "Col Setpoint Boost Gain"), min = 0, max = 255 },
  { id = 72, name = t("widgets.dashboard.fn_yaw_dyn_ceiling_gain", "Yaw Dyn Ceiling Gain"), min = 0, max = 250 },
  { id = 73, name = t("widgets.dashboard.fn_yaw_dyn_deadband_gain", "Yaw Dyn Deadband Gain"), min = 0, max = 250 },
  { id = 74, name = t("widgets.dashboard.fn_yaw_dyn_deadband_filter", "Yaw Dyn Deadband Filter"), min = 0, max = 250 },
  { id = 75, name = t("widgets.dashboard.fn_yaw_precomp_cutoff", "Yaw Precomp Cutoff"), min = 0, max = 250 },
  { id = 76, name = t("widgets.dashboard.fn_gov_idle_throttle", "Gov Idle Throttle"), min = 0, max = 250 },
  { id = 77, name = t("widgets.dashboard.fn_gov_auto_throttle", "Gov Auto Throttle"), min = 0, max = 250 },
  { id = 78, name = t("widgets.dashboard.fn_gov_max_throttle", "Gov Max Throttle"), min = 0, max = 100 },
  { id = 79, name = t("widgets.dashboard.fn_gov_min_throttle", "Gov Min Throttle"), min = 0, max = 100 },
  { id = 80, name = t("widgets.dashboard.fn_gov_headspeed", "Gov Headspeed"), min = 0, max = 10000 },
  { id = 81, name = t("widgets.dashboard.fn_gov_yaw_ff", "Gov Yaw FF"), min = 0, max = 250 },
  { id = 82, name = t("widgets.dashboard.fn_battery_profile", "Battery Profile"), min = 1, max = 6 }
}

local byId = {}
for i = 1, #M.FUNCTIONS do
  byId[M.FUNCTIONS[i].id] = M.FUNCTIONS[i]
end

M.BANK_COUNT = 6
M.ROW_COUNT = 6

--- The adjustment function with this id, or nil when the firmware has none.
function M.byId(id)
  return byId[tonumber(id) or -1]
end

--- What a parameter is called on screen. An id with no entry is named by its number rather than
-- left blank: an unnamed row the pilot is about to turn is worse than an ugly one.
function M.nameOf(id)
  local fn = byId[tonumber(id) or -1]
  if fn then return fn.name end
  return t("widgets.dashboard.fn_unknown", "Function") .. " " .. tostring(math.floor(tonumber(id) or 0))
end

-- The six enable windows of the documented radio setup, in slot order, on the bank channel.
-- Source: the project's own generic radio setup and the model template shipped beside it.
M.REFERENCE_BANDS = {
  { min = 900, max = 1100 },
  { min = 1100, max = 1300 },
  { min = 1300, max = 1400 },
  { min = 1550, max = 1700 },
  { min = 1750, max = 1900 },
  { min = 1950, max = 2100 }
}

-- The six INCREMENT windows on the value channel, row 1 at the top of the travel. A row's
-- decrement window is this window mirrored about 1500.
M.REFERENCE_ROW_WINDOWS = {
  { min = 1925, max = 1975 },
  { min = 1850, max = 1900 },
  { min = 1775, max = 1825 },
  { min = 1700, max = 1750 },
  { min = 1625, max = 1675 },
  { min = 1550, max = 1600 }
}

-- bank -> row -> adjustment function id, for the documented setup. A cell with no slot behind it
-- is simply absent, and the screen shows it as unassigned rather than as a parameter it cannot
-- drive. Replaced by the board's own slot table once the overlay has read it.
M.REFERENCE_SET = {
  [1] = { [1] = 14, [2] = 18, [3] = 22, [4] = 49, [5] = 27, [6] = 26 },
  [2] = { [1] = 15, [2] = 19, [3] = 23, [4] = 50, [5] = 28, [6] = 29 },
  [3] = { [1] = 16, [2] = 20, [3] = 24, [4] = 51, [5] = 39, [6] = 40 },
  [4] = { [1] = 17, [2] = 21, [3] = 25, [4] = 52 },
  [5] = { [1] = 59, [2] = 60, [3] = 54, [4] = 55 },
  [6] = { [1] = 56, [2] = 57, [3] = 58, [4] = 48 }
}

-- What a global variable is worth on the wire. A mixer line MAX x GVn at full weight puts
-- 1500 + 5.12 x GV microseconds on the channel, so this constant is what converts between the
-- window the firmware watches and the number written into the variable.
local US_PER_GVAR_UNIT = 5.12
local CENTRE_US = 1500

-- A channel cannot leave its own travel. At 100% output the mixer reaches 1500 +/- 512
-- microseconds, so a global variable past +/-100 moves nothing further and the output limit
-- clips it. Every band value below is therefore held inside that range.
local GVAR_TRAVEL_LIMIT = 100

local function roundToInt(value)
  return math.floor(value + 0.5)
end

--- Which band a microsecond reading falls in, or nil when it sits between two windows.
-- Used for the DISPLAY of the armed bank, so a six-position switch wired straight to the enable
-- channel reads correctly without the overlay having written anything at all.
function M.usToBand(us, bands)
  us = tonumber(us)
  if us == nil or type(bands) ~= "table" then return nil end
  for i = 1, #bands do
    local band = bands[i]
    if type(band) == "table" and us >= band.min and us <= band.max then return i end
  end
  return nil
end

--- The global variable value that parks the enable channel in the middle of one band.
-- Mid-band rather than an edge, so switch, mixer and receiver tolerance all fit inside the window.
function M.bandMidGv(band)
  if type(band) ~= "table" then return nil end
  local mid = (tonumber(band.min) or 0) + (tonumber(band.max) or 0)
  local value = roundToInt(((mid / 2) - CENTRE_US) / US_PER_GVAR_UNIT)
  if value > GVAR_TRAVEL_LIMIT then value = GVAR_TRAVEL_LIMIT end
  if value < -GVAR_TRAVEL_LIMIT then value = -GVAR_TRAVEL_LIMIT end
  return value
end

--- The value-channel magnitude that lands inside row `row`'s increment or decrement window.
-- The rows are 15 percent apart and row 1 is the outermost, which is exactly what the shipped
-- template's summed trims produce: 90, 75, 60, 45, 30, 15.
function M.rowCode(row, up)
  row = tonumber(row)
  if row == nil or row < 1 or row > M.ROW_COUNT then return nil end
  local magnitude = (M.ROW_COUNT + 1 - row) * 15
  if up then return magnitude end
  return -magnitude
end

--- A raw channel reading, as microseconds. EdgeTX answers getValue("chN") on -1024..1024 around
-- centre; the flight controller and every window above speak microseconds. A reading already in
-- the microsecond band is passed through, because the same helper meets numbers from both sides.
-- Follows app/pages/setup/controls/adjustments/page.lua, which converts the same two ways.
function M.channelRawToUs(raw)
  raw = tonumber(raw)
  if raw == nil then return nil end
  if raw >= -1200 and raw <= 1200 then
    return roundToInt(CENTRE_US + (raw * 500 / 1024))
  end
  if raw >= 700 and raw <= 2300 then
    return roundToInt(raw)
  end
  return nil
end

-- The band values of the documented setup, computed from the windows above rather than written
-- out again, so the two can never disagree.
M.REFERENCE_BAND_GV = {}
for i = 1, #M.REFERENCE_BANDS do
  M.REFERENCE_BAND_GV[i] = M.bandMidGv(M.REFERENCE_BANDS[i])
end

return M
