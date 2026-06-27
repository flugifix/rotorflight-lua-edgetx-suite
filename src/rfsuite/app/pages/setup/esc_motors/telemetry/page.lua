local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local Controls = nil
local Common = nil
local MspRuntime = nil
local EscSensorConfigApi = nil
local LoadingOverlay = nil
local ConfirmDialog = nil
local ApiVersion = nil
local t = nil

local ui = {
  loaded = false,
  dirty = false,
  loading = false,
  saving = false,
  progress = 0,
  baseTitle = nil,
  config = {
    protocol = 0,
    half_duplex = 0,
    pin_swap = 0,
    voltage_correction = 0,
    current_correction = 0,
    consumption_correction = 0
  },
  parsedCache = {},
  runtime = {
    readPending = false,
    requestRebuild = nil,
    lastSessionSignature = nil,
    syncHeaderTitle = nil
  }
}

local function getSession()
  local root = _G and _G.rfsuite
  return root and root.session or nil
end

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not MspRuntime then MspRuntime = loadModule("tasks/msp/runtime.lua") end
  if not EscSensorConfigApi then EscSensorConfigApi = loadModule("tasks/msp/api/esc_sensor_config.lua") end
  if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
  if not ConfirmDialog then ConfirmDialog = loadModule("ui/confirm_dialog.lua") end
  if not ApiVersion then ApiVersion = loadModule("lib/api_version.lua") end
  if not t then t = Common and Common.pageT("setup_esc_motors") or nil end
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

local function buildSessionSignature()
  local session = getSession()
  return session and session.signature or "1"
end

local function loadFromSession()
  local session = getSession()
  if not session or type(session.setup_esc_motors_telemetry) ~= "table" then return end
  local cached = session.setup_esc_motors_telemetry
  ui.config.protocol = tonumber(cached.protocol) or 0
  ui.config.half_duplex = tonumber(cached.half_duplex) or 0
  ui.config.pin_swap = tonumber(cached.pin_swap) or 0
  ui.config.voltage_correction = tonumber(cached.voltage_correction) or 0
  ui.config.current_correction = tonumber(cached.current_correction) or 0
  ui.config.consumption_correction = tonumber(cached.consumption_correction) or 0
  ui.parsedCache = cached.parsedCache or {}
end

local function queueTelemetryRead(isAutoReload)
  if ui.runtime.readPending then return false, "read_pending" end
  if not MspRuntime or not EscSensorConfigApi or type(MspRuntime.getState) ~= "function" then
    return false, "msp_runtime_unavailable"
  end

  local mspState = MspRuntime.getState()
  local queue = mspState and mspState.queue
  if not queue or type(queue.add) ~= "function" then
    return false, "msp_queue_unavailable"
  end

  ui.runtime.readPending = true
  if not isAutoReload then
    ui.loading = true
    ui.progress = 0
    if type(ui.runtime.requestRebuild) == "function" then
      ui.runtime.requestRebuild()
    end
  end

  queue:add({
    command = EscSensorConfigApi.command,
    simulatorResponse = EscSensorConfigApi.simulatorResponse,
    processReply = function(self, buf)
      local parsed = EscSensorConfigApi.parse(buf)
      if parsed then
        ui.config.protocol = parsed.protocol or 0
        ui.config.half_duplex = parsed.half_duplex or 0
        ui.config.pin_swap = parsed.pin_swap or 0
        ui.config.voltage_correction = parsed.voltage_correction or 0
        ui.config.current_correction = parsed.current_correction or 0
        ui.config.consumption_correction = parsed.consumption_correction or 0

        ui.parsedCache = parsed

        local session = getSession()
        if session then
          session.setup_esc_motors_telemetry = {
            protocol = ui.config.protocol,
            half_duplex = ui.config.half_duplex,
            pin_swap = ui.config.pin_swap,
            voltage_correction = ui.config.voltage_correction,
            current_correction = ui.config.current_correction,
            consumption_correction = ui.config.consumption_correction,
            parsedCache = ui.parsedCache
          }
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

local function queueTelemetryWrite(requestRebuild)
  if not MspRuntime or not EscSensorConfigApi or type(MspRuntime.getState) ~= "function" then
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

  writeData.protocol = ui.config.protocol
  writeData.half_duplex = ui.config.half_duplex
  writeData.pin_swap = ui.config.pin_swap
  writeData.voltage_correction = ui.config.voltage_correction
  writeData.current_correction = ui.config.current_correction
  writeData.consumption_correction = ui.config.consumption_correction

  local payload = EscSensorConfigApi.buildWritePayload(writeData)

  ui.saving = true
  ui.progress = 0
  if type(requestRebuild) == "function" then
    requestRebuild()
  end

  queue:add({
    command = EscSensorConfigApi.writeCommand,
    payload = payload,
    isWrite = true,
    simulatorResponse = {},
    processReply = function()
      -- Step 2: Write EEPROM
      local eepromApi = loadModule("tasks/msp/api/eeprom_write.lua")
      if eepromApi then
        queue:add({
          command = eepromApi.writeCommand,
          payload = {},
          isWrite = true,
          simulatorResponse = {},
          processReply = function()
            -- Step 3: Reboot FC
            local rebootApi = loadModule("tasks/msp/api/reboot.lua")
            if rebootApi then
              queue:add({
                command = rebootApi.writeCommand,
                payload = rebootApi.buildWritePayload({ rebootMode = 0 }),
                isWrite = true,
                simulatorResponse = {},
                processReply = function()
                  ui.dirty = false
                  ui.saving = false
                  queueTelemetryRead(true)
                end,
                errorHandler = function()
                  ui.saving = false
                  if type(requestRebuild) == "function" then
                    requestRebuild()
                  end
                end
              })
            else
              ui.dirty = false
              ui.saving = false
              queueTelemetryRead(true)
            end
          end,
          errorHandler = function()
            ui.saving = false
            if type(requestRebuild) == "function" then
              requestRebuild()
            end
          end
        })
      else
        ui.dirty = false
        ui.saving = false
        if type(requestRebuild) == "function" then
          requestRebuild()
        end
      end
    end,
    errorHandler = function()
      ui.saving = false
      if type(requestRebuild) == "function" then
        requestRebuild()
      end
    end
  })

  return true, nil
end

local function ensureLoaded()
  if ui.loaded then return end

  ui.config = {
    protocol = 0,
    half_duplex = 0,
    pin_swap = 0,
    voltage_correction = 0,
    current_correction = 0,
    consumption_correction = 0
  }
  ui.parsedCache = {}

  loadFromSession()
  ui.loaded = true
  ui.dirty = false
  ui.runtime.lastSessionSignature = buildSessionSignature()

  local session = getSession()
  local rawApiVersion = session and session.apiVersion
  local isSupported = rawApiVersion and ApiVersion and ApiVersion.isAtLeast(rawApiVersion, {12, 0, 6})

  if isSupported then
    queueTelemetryRead(false)
  else
    ui.loading = false
  end
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
    ui.loaded = false
    ensureLoaded()
  end
end

function M.getHeaderActions()
  local session = getSession()
  local rawApiVersion = session and session.apiVersion
  local isSupported = rawApiVersion and ApiVersion and ApiVersion.isAtLeast(rawApiVersion, {12, 0, 6})

  return {
    save = isSupported == true,
    reload = isSupported == true,
    help = true,
    menu = true
  }
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

  if ui.loading or ui.saving then
    local titleText = ui.loading and pageText(i18n, "loading_telemetry", "Loading") or pageText(i18n, "saving_telemetry", "Saving")
    local msgText = ui.loading and pageText(i18n, "loading_telemetry", "Loading telemetry configuration...") or pageText(i18n, "saving_telemetry", "Saving telemetry configuration...")
    LoadingOverlay.append(children, {
      x = x, y = y, w = w, h = h,
      title = titleText,
      message = msgText,
      progress = ui.progress / 100
    })
    return
  end

  local displayTitle = ui.baseTitle or "Telemetry"
  local title = pageText(i18n, "title_telemetry", displayTitle)
  if type(ui.runtime.syncHeaderTitle) == "function" then
    ui.runtime.syncHeaderTitle(title, M.getHeaderActions())
  end

  local cursorY = y
  if Controls and type(Controls.appendStaticSectionHeader) == "function" then
    Controls.appendStaticSectionHeader(children, x, cursorY, w, title)
    cursorY = cursorY + (Controls.STATIC_SECTION_H or 50)
  end

  local session = getSession()
  local rawApiVersion = session and session.apiVersion
  local isSupported = rawApiVersion and ApiVersion and ApiVersion.isAtLeast(rawApiVersion, {12, 0, 6})

  if not isSupported then
    children[#children + 1] = {
      type = "label",
      x = x + 10, y = cursorY + 10,
      text = "Unsupported API version",
      color = COLOR_THEME_SECONDARY1,
      font = MIDSIZE
    }
    return
  end

  local hasPinSwap = ApiVersion.isAtLeast(rawApiVersion, {12, 0, 7})
  local hasCorrections = ApiVersion.isAtLeast(rawApiVersion, {12, 0, 8})

  local protocolOptions = {
    { label = "NONE", value = 0 },
    { label = "BLHELI32", value = 1 },
    { label = "HOBBYWING V4", value = 2 },
    { label = "HOBBYWING V5", value = 3 },
    { label = "SCORPION", value = 4 },
    { label = "KONTRONIK", value = 5 },
    { label = "OMP", value = 6 },
    { label = "ZTW", value = 7 },
    { label = "APD", value = 8 },
    { label = "OPENYGE", value = 9 },
    { label = "FLYROTOR", value = 10 },
    { label = "GRAUPNER", value = 11 },
    { label = "XDFLY", value = 12 },
    { label = "FrSky F.BUS", value = 13 },
    { label = "RECORD", value = 14 }
  }

  local proto = ui.config.protocol

  -- 1. Telemetry Protocol
  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    pageText(i18n, "telemetry_protocol", "Telemetry Protocol"),
    protocolOptions,
    proto,
    function(newVal)
      local val = tonumber(newVal) or 0
      if ui.config.protocol ~= val then
        ui.config.protocol = val
        ui.dirty = true
        if type(ui.runtime.requestRebuild) == "function" then
          ui.runtime.requestRebuild()
        end
      end
    end
  )

  -- 2. Half Duplex
  cursorY = cursorY + Controls.appendRadioSwitch(
    children, x, cursorY, w,
    pageText(i18n, "half_duplex", "Half Duplex"),
    function() return ui.config.half_duplex ~= 0 end,
    function(nextBool)
      ui.config.half_duplex = nextBool and 1 or 0
      ui.dirty = true
    end,
    function() return proto ~= 0 end
  )

  -- 3. Pin Swap (if apiVersion >= 12.0.7)
  if hasPinSwap then
    cursorY = cursorY + Controls.appendRadioSwitch(
      children, x, cursorY, w,
      pageText(i18n, "pin_swap", "Pin Swap"),
      function() return ui.config.pin_swap ~= 0 end,
      function(nextBool)
        ui.config.pin_swap = nextBool and 1 or 0
        ui.dirty = true
      end,
      function() return proto ~= 0 end
    )
  end

  -- 4. Voltage Correction (if apiVersion >= 12.0.8)
  if hasCorrections then
    cursorY = cursorY + Controls.appendNumberField(
      children, x, cursorY, w,
      pageText(i18n, "voltage_correction", "Voltage Correction"),
      {
        min = -99,
        max = 125,
        suffix = "%",
        active = function() return proto ~= 0 end,
        get = function() return ui.config.voltage_correction end,
        set = function(v)
          ui.config.voltage_correction = tonumber(v) or 0
          ui.dirty = true
        end
      }
    )

    -- 5. Current Correction
    cursorY = cursorY + Controls.appendNumberField(
      children, x, cursorY, w,
      pageText(i18n, "current_correction", "Current Correction"),
      {
        min = -99,
        max = 125,
        suffix = "%",
        active = function() return proto ~= 0 end,
        get = function() return ui.config.current_correction end,
        set = function(v)
          ui.config.current_correction = tonumber(v) or 0
          ui.dirty = true
        end
      }
    )

    -- 6. Consumption Correction
    cursorY = cursorY + Controls.appendNumberField(
      children, x, cursorY, w,
      pageText(i18n, "consumption_correction", "Consumption Correction"),
      {
        min = -99,
        max = 125,
        suffix = "%",
        active = function() return proto ~= 0 end,
        get = function() return ui.config.consumption_correction end,
        set = function(v)
          ui.config.consumption_correction = tonumber(v) or 0
          ui.dirty = true
        end
      }
    )
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

function M.onSave(ctx)
  local ok, err = queueTelemetryWrite(ctx and ctx.requestRebuild)
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
  local session = getSession()
  if session then
    ui.dirty = false
    loadFromSession()
    queueTelemetryRead(false)
  end
  return true
end

function M.onHelp(ctx)
  local help = loadModule("app/pages/setup/esc_motors/telemetry/help.lua")
  if type(help) == "function" then
    return help(ctx)
  end
  return { title = "Help", message = "No help available" }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onClose()
  if Common and type(Common.resetPageState) == "function" then
    Common.resetPageState(ui, {
      resetLoaded = true,
      resetDirty = true
    })
  end
  Controls = nil
  Common = nil
  MspRuntime = nil
  EscSensorConfigApi = nil
  LoadingOverlay = nil
  ConfirmDialog = nil
  ApiVersion = nil
  t = nil
end

return M
