local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local Common = nil
local Controls = nil
local MspRuntime = nil
local EscParametersAm32Api = nil
local LoadingOverlay = nil
local ConfirmDialog = nil
local t = nil

local ui = {
  loaded = false,
  dirty = false,
  config = {
    -- Basic
    motor_direction = 0,
    motor_kv = 1400,
    motor_poles = 14,
    startup_power = 100,
    brake_on_stop = 0,
    brake_strength = 0,
    running_brake_level = 0,
    beep_volume = 10,

    -- Advanced
    bidirectional_mode = 0,
    sinusoidal_startup = 0,
    complementary_pwm = 0,
    variable_pwm_frequency = 0,
    stuck_rotor_protection = 0,
    timing_advance = 0,
    pwm_frequency = 24,
    stall_protection = 0,
    interval_telemetry = 0,
    rc_car_reversing = 0,
    use_hall_sensors = 0,
    sine_mode_range = 10,
    sine_mode_power = 7,
    auto_advance = 0,

    -- Limits
    servo_low_threshold = 1000,
    servo_high_threshold = 2000,
    servo_neutral = 1500,
    servo_dead_band = 50,
    low_voltage_cutoff = 0,
    low_voltage_threshold = 300,
    temperature_limit = 140,
    current_limit = 100,
    esc_protocol = 1
  },
  currentSection = 1,
  parsedCache = nil,
  runtime = {
    readPending = false,
    requestRebuild = nil,
    lastSessionSignature = nil
  },
  loading = false,
  saving = false,
  progress = 0
}

local function getSession()
  local root = _G and _G.rfsuite
  return root and root.session or nil
end

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not MspRuntime then MspRuntime = loadModule("tasks/msp/runtime.lua") end
  if not EscParametersAm32Api then EscParametersAm32Api = loadModule("tasks/msp/api/esc_parameters_am32.lua") end
  if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
  if not ConfirmDialog then ConfirmDialog = loadModule("ui/confirm_dialog.lua") end
  if not t then t = Common and Common.pageT("setup_esc_motors") or nil end

  if type(ui.runtime) ~= "table" then
    ui.runtime = {
      readPending = false,
      requestRebuild = nil,
      lastSessionSignature = nil
    }
  end
end

local function pageText(i18n, key, fallback)
  if t then
    local translated = t(i18n, key, fallback)
    if translated ~= nil and translated ~= "" and translated ~= key then
      return translated
    end
  end
  return fallback
end

local function queueAm32Read(isAutoReload)
  if not MspRuntime or not EscParametersAm32Api or type(MspRuntime.getState) ~= "function" then
    return false, "msp_runtime_unavailable"
  end

  local mspState = MspRuntime.getState()
  local queue = mspState and mspState.queue
  if not queue or type(queue.add) ~= "function" then
    return false, "msp_queue_unavailable"
  end

  if ui.runtime.readPending then return true, nil end

  ui.runtime.readPending = true
  if not isAutoReload then
    ui.loading = true
    ui.progress = 0
    if type(ui.runtime.requestRebuild) == "function" then
      ui.runtime.requestRebuild()
    end
  end

  queue:add({
    command = EscParametersAm32Api.command,
    simulatorResponse = EscParametersAm32Api.simulatorResponse,
    processReply = function(self, buf)
      local parsed = EscParametersAm32Api.parse(buf)
      if parsed then
        for k, v in pairs(ui.config) do
          if parsed[k] ~= nil then
            ui.config[k] = parsed[k]
          end
        end

        ui.parsedCache = parsed

        local session = getSession()
        if session then
          session.setup_esc_motors_esc_tools_am32 = {
            config = {},
            parsedCache = ui.parsedCache
          }
          for k, v in pairs(ui.config) do
            session.setup_esc_motors_esc_tools_am32.config[k] = v
          end
        end
      end

      ui.runtime.readPending = false
      ui.loading = false
      ui.dirty = false
      ui.progress = 100
      if type(ui.runtime.requestRebuild) == "function" then
        ui.runtime.requestRebuild()
      end
    end,
    errorHandler = function()
      ui.runtime.readPending = false
      ui.loading = false
      if type(ui.runtime.requestRebuild) == "function" then
        ui.runtime.requestRebuild()
      end
    end
  })

  return true, nil
end

local function queueAm32Write(requestRebuild)
  if not MspRuntime or not EscParametersAm32Api or type(MspRuntime.getState) ~= "function" then
    return false, "msp_runtime_unavailable"
  end

  local mspState = MspRuntime.getState()
  local queue = mspState and mspState.queue
  if not queue or type(queue.add) ~= "function" then
    return false, "msp_queue_unavailable"
  end

  local writeData = {}
  if ui.parsedCache then
    for k, v in pairs(ui.parsedCache) do
      writeData[k] = v
    end
  end

  for k, v in pairs(ui.config) do
    writeData[k] = v
  end

  ui.saving = true
  if requestRebuild and type(ui.runtime.requestRebuild) == "function" then
    ui.runtime.requestRebuild()
  end

  queue:add({
    command = EscParametersAm32Api.writeCommand,
    payload = EscParametersAm32Api.buildWritePayload(writeData),
    isWrite = true,
    processReply = function(self, buf)
      ui.saving = false
      ui.dirty = false
      if requestRebuild and type(ui.runtime.requestRebuild) == "function" then
        ui.runtime.requestRebuild()
      end
    end,
    errorHandler = function()
      ui.saving = false
      if requestRebuild and type(ui.runtime.requestRebuild) == "function" then
        ui.runtime.requestRebuild()
      end
    end
  })

  return true, nil
end

local function buildSessionSignature()
  local s = tostring(ui.currentSection)
  for k, v in pairs(ui.config) do
    s = s .. ";" .. k .. "=" .. tostring(v)
  end
  return s
end

local function loadFromSession()
  local session = getSession()
  local cached = session and session.setup_esc_motors_esc_tools_am32 or nil
  if type(cached) == "table" and type(cached.config) == "table" then
    for k, v in pairs(ui.config) do
      if cached.config[k] ~= nil then
        ui.config[k] = cached.config[k]
      end
    end
    ui.parsedCache = cached.parsedCache
    return true
  end
  return false
end

local function ensureLoaded()
  if ui.loaded then return end

  if not ui.runtime then
    ui.runtime = {
      readPending = false,
      requestRebuild = nil,
      lastSessionSignature = nil
    }
  end
  ui.loading = false
  ui.saving = false
  ui.runtime.readPending = false

  -- For ESC tools, always show safety warning and read configuration from flight controller on page entry.
  ui.loaded = true
  ui.dirty = false
  ui.runtime.lastSessionSignature = buildSessionSignature()
  
  local warningTitle = pageText(nil, "safety_warning_title", "Safety Warning")
  local warningMsg = pageText(nil, "remove_blades_warning", "Please remove main and tail blades before configuring the ESC!")

  if lvgl then
    if type(lvgl.message) == "function" then
      pcall(lvgl.message, {
        title = warningTitle,
        message = warningMsg
      })
    elseif type(lvgl.alert) == "function" then
      pcall(lvgl.alert, {
        title = warningTitle,
        message = warningMsg
      })
    end
  end
  queueAm32Read(false)
end

function M.onLoad()
  ensureDeps()
  ensureLoaded()
end

function M.onActivate()
  ensureDeps()
  ensureLoaded()
end

function M.wakeup(ctx)
  ensureDeps()
  ensureLoaded()
  
  ui.runtime.requestRebuild = ctx and ctx.requestRebuild or nil
  ui.runtime.syncHeaderTitle = ctx and ctx.syncHeaderTitle or nil

  local signature = buildSessionSignature()
  if signature ~= ui.runtime.lastSessionSignature then
    ui.runtime.lastSessionSignature = signature
    if type(ui.runtime.requestRebuild) == "function" then
      ui.runtime.requestRebuild()
    end
  end
end

function M.getHeaderActions()
  return {
    save = true,
    reload = true,
    menu = true
  }
end

function M.onSave(ctx)
  local ok, err = queueAm32Write(ctx and ctx.requestRebuild)
  if not ok then
    if lvgl and lvgl.alert then
      lvgl.alert({
        title = pageText(ctx and ctx.i18n, "save_error_title", "Error"),
        message = tostring(err or "MSP write failed")
      })
    end
    return false
  end
  return true
end

function M.onReload(ctx)
  ui.dirty = false
  queueAm32Read(false)
  return true
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded()

  ui.runtime.requestRebuild = ctx and ctx.requestRebuild or nil
  ui.runtime.syncHeaderTitle = ctx and ctx.syncHeaderTitle or nil

  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local h = ctx.h
  local i18n = ctx.i18n

  local title = "AM32 Configurator"
  if type(ui.runtime.syncHeaderTitle) == "function" then
    ui.runtime.syncHeaderTitle(title, M.getHeaderActions())
  end

  if ui.loading or ui.saving then
    local titleText = ui.loading and pageText(i18n, "loading", "Loading") or pageText(i18n, "saving", "Saving")
    local msgText = ui.loading and pageText(i18n, "loading_data", "Loading ESC parameters...") or pageText(i18n, "saving_data", "Saving ESC parameters...")
    if LoadingOverlay and type(LoadingOverlay.append) == "function" then
      LoadingOverlay.append(children, {
        x = x, y = y, w = w, h = h,
        title = titleText,
        message = msgText,
        progress = ui.progress / 100
      })
    end
    return
  end

  local cursorY = y
  if Controls and type(Controls.appendStaticSectionHeader) == "function" then
    Controls.appendStaticSectionHeader(children, x, cursorY, w, title)
    cursorY = cursorY + (Controls.STATIC_SECTION_H or 50)
  end
  local sectionOptions = {
    { value = 1, label = "Basic" },
    { value = 2, label = "Advanced" },
    { value = 3, label = "Limits" }
  }
  local rowH = Controls.appendComboSelect(children, x, cursorY, w, "Section", sectionOptions, ui.currentSection, function(val)
    ui.currentSection = val
    if type(ui.runtime.requestRebuild) == "function" then
      ui.runtime.requestRebuild()
    end
  end)
  cursorY = cursorY + rowH

  local function markDirty()
    ui.dirty = true
    if type(ui.runtime.requestRebuild) == "function" then
      ui.runtime.requestRebuild()
    end
  end

  if ui.currentSection == 1 then
    -- Basic Settings
    local dirOpts = {
      { value = 0, label = "Normal" },
      { value = 1, label = "Reversed" }
    }
    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Motor Direction", dirOpts, ui.config.motor_direction, function(val)
      ui.config.motor_direction = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Motor KV", {
      min = 20, max = 10220, step = 40, suffix = "KV",
      get = function() return ui.config.motor_kv end,
      set = function(val)
        ui.config.motor_kv = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Motor Poles", {
      min = 2, max = 36, step = 1,
      get = function() return ui.config.motor_poles end,
      set = function(val)
        ui.config.motor_poles = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Startup Power", {
      min = 50, max = 150, step = 1, suffix = "%",
      get = function() return ui.config.startup_power end,
      set = function(val)
        ui.config.startup_power = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    local brakeOpts = {
      { value = 0, label = "Off" },
      { value = 1, label = "Brake" },
      { value = 2, label = "Active" }
    }
    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Brake on Stop", brakeOpts, ui.config.brake_on_stop, function(val)
      ui.config.brake_on_stop = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Brake Strength", {
      min = 0, max = 10, step = 1,
      get = function() return ui.config.brake_strength end,
      set = function(val)
        ui.config.brake_strength = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Running Brake Level", {
      min = 0, max = 10, step = 1,
      get = function() return ui.config.running_brake_level end,
      set = function(val)
        ui.config.running_brake_level = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Beep Volume", {
      min = 0, max = 11, step = 1,
      get = function() return ui.config.beep_volume end,
      set = function(val)
        ui.config.beep_volume = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

  elseif ui.currentSection == 2 then
    -- Advanced Settings
    local offOnOpts = {
      { value = 0, label = "Off" },
      { value = 1, label = "On" }
    }
    
    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Bidirectional Mode", offOnOpts, ui.config.bidirectional_mode, function(val)
      ui.config.bidirectional_mode = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Sinusoidal Startup", offOnOpts, ui.config.sinusoidal_startup, function(val)
      ui.config.sinusoidal_startup = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Complementary PWM", offOnOpts, ui.config.complementary_pwm, function(val)
      ui.config.complementary_pwm = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    local varPwmOpts = {
      { value = 0, label = "Fixed" },
      { value = 1, label = "Variable" },
      { value = 2, label = "RPM" }
    }
    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Variable PWM Frequency", varPwmOpts, ui.config.variable_pwm_frequency, function(val)
      ui.config.variable_pwm_frequency = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Stuck Rotor Protection", offOnOpts, ui.config.stuck_rotor_protection, function(val)
      ui.config.stuck_rotor_protection = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    local timingOpts = {
      { value = 0, label = "0°" },
      { value = 1, label = "7.5°" },
      { value = 2, label = "15°" },
      { value = 3, label = "22.5°" }
    }
    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Timing Advance", timingOpts, ui.config.timing_advance, function(val)
      ui.config.timing_advance = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "PWM Frequency", {
      min = 8, max = 144, step = 1, suffix = "kHz",
      get = function() return ui.config.pwm_frequency end,
      set = function(val)
        ui.config.pwm_frequency = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Stall Protection", offOnOpts, ui.config.stall_protection, function(val)
      ui.config.stall_protection = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Interval Telemetry", offOnOpts, ui.config.interval_telemetry, function(val)
      ui.config.interval_telemetry = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "RC Car Reversing", offOnOpts, ui.config.rc_car_reversing, function(val)
      ui.config.rc_car_reversing = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Use Hall Sensors", offOnOpts, ui.config.use_hall_sensors, function(val)
      ui.config.use_hall_sensors = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Sine Mode Range", {
      min = 5, max = 25, step = 1,
      get = function() return ui.config.sine_mode_range end,
      set = function(val)
        ui.config.sine_mode_range = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Sine Mode Power", {
      min = 1, max = 10, step = 1,
      get = function() return ui.config.sine_mode_power end,
      set = function(val)
        ui.config.sine_mode_power = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Auto Advance", offOnOpts, ui.config.auto_advance, function(val)
      ui.config.auto_advance = val
      markDirty()
    end)
    cursorY = cursorY + rowH

  elseif ui.currentSection == 3 then
    -- Limits Settings
    rowH = Controls.appendNumberField(children, x, cursorY, w, "Servo Low Threshold", {
      min = 750, max = 1250, step = 2, suffix = "us",
      get = function() return ui.config.servo_low_threshold end,
      set = function(val)
        ui.config.servo_low_threshold = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Servo High Threshold", {
      min = 1750, max = 2250, step = 2, suffix = "us",
      get = function() return ui.config.servo_high_threshold end,
      set = function(val)
        ui.config.servo_high_threshold = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Servo Neutral", {
      min = 1374, max = 1630, step = 1, suffix = "us",
      get = function() return ui.config.servo_neutral end,
      set = function(val)
        ui.config.servo_neutral = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Servo Dead Band", {
      min = 0, max = 100, step = 1,
      get = function() return ui.config.servo_dead_band end,
      set = function(val)
        ui.config.servo_dead_band = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    local lvcOpts = {
      { value = 0, label = "Off" },
      { value = 1, label = "Cell" },
      { value = 2, label = "Absolute" }
    }
    rowH = Controls.appendComboSelect(children, x, cursorY, w, "Low Voltage Cutoff", lvcOpts, ui.config.low_voltage_cutoff, function(val)
      ui.config.low_voltage_cutoff = val
      markDirty()
    end)
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Low Voltage Threshold", {
      min = 250, max = 350, step = 1, suffix = "cV",
      get = function() return ui.config.low_voltage_threshold end,
      set = function(val)
        ui.config.low_voltage_threshold = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Temperature Limit", {
      min = 70, max = 141, step = 1, suffix = "C",
      get = function() return ui.config.temperature_limit end,
      set = function(val)
        ui.config.temperature_limit = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    rowH = Controls.appendNumberField(children, x, cursorY, w, "Current Limit", {
      min = 0, max = 202, step = 2,
      get = function() return ui.config.current_limit end,
      set = function(val)
        ui.config.current_limit = val
        markDirty()
      end
    })
    cursorY = cursorY + rowH

    local protoOpts = {
      { value = 0, label = "Auto" },
      { value = 1, label = "Dshot 300-600" },
      { value = 2, label = "Servo 1-2ms" },
      { value = 3, label = "Serial" },
      { value = 4, label = "BF Safe Arming" }
    }
    rowH = Controls.appendComboSelect(children, x, cursorY, w, "ESC Protocol", protoOpts, ui.config.esc_protocol, function(val)
      ui.config.esc_protocol = val
      markDirty()
    end)
    cursorY = cursorY + rowH
  end

  if ui.dirty then
    children[#children + 1] = {
      type = "label",
      x = x + 16, y = cursorY + 10,
      text = pageText(i18n, "unsaved_changes", "Unsaved changes"),
      color = COLOR_THEME_SECONDARY1,
      font = SMLSIZE
    }
  end
end

function M.onClose()
  if Common and type(Common.resetPageState) == "function" then
    Common.resetPageState(ui, {
      resetLoaded = true,
      resetDirty = true
    })
  end
  Common = nil
  Controls = nil
  MspRuntime = nil
  EscParametersAm32Api = nil
  LoadingOverlay = nil
  ConfirmDialog = nil
  t = nil
end

return M
