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
local PidProfileApi = nil
local GovernorProfileApi = nil
local GovernorConfigApi = nil
local LoadingOverlay = nil
local Sensors = nil
local ApiVersion = nil
local t = nil

local function newRuntime()
  return {
    readPending = false,
    requestRebuild = nil,
    lastSessionSignature = nil
  }
end

local ui = {
  loaded = false,
  dirty = false,
  config = {},
  runtime = newRuntime(),
  loading = false,
  progress = 0,
  baseTitle = nil
}

local function getSession()
  local root = _G and _G.rfsuite
  return root and root.session or nil
end

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not MspRuntime then MspRuntime = loadModule("tasks/msp/runtime.lua") end
  if not PidProfileApi then PidProfileApi = loadModule("tasks/msp/api/pid_profile.lua") end
  if not GovernorProfileApi then GovernorProfileApi = loadModule("tasks/msp/api/governor_profile.lua") end
  if not GovernorConfigApi then GovernorConfigApi = loadModule("tasks/msp/api/governor_config.lua") end
  if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
  if not Sensors then Sensors = loadModule("lib/sensors.lua") end
  if not ApiVersion then ApiVersion = loadModule("lib/api_version.lua") end
  if not t then t = Common and Common.pageT("flight_tuning_advanced_tail_rotor") or nil end
  
  if Common then
    if not ui.runtimeBase then
      ui.runtimeBase = Common.createProfileAwareRuntime({
        profileGetter = function()
          local sensorProfile = nil
          if Sensors and type(Sensors.getValue) == "function" then
            sensorProfile = tonumber(Sensors.getValue("pid_profile"))
          end
          if sensorProfile and sensorProfile > 0 then
            return math.floor(sensorProfile)
          end
          local session = getSession()
          local activeProfile = session and session.activeProfile
          if activeProfile ~= nil then
            return math.floor(tonumber(activeProfile) or 0) + 1
          end
          return 1
        end
      })
    end
    if type(ui.runtime) ~= "table" then
      ui.runtime = newRuntime()
      setmetatable(ui.runtime, { __index = ui.runtimeBase })
    end
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

local function loadFromSession()
  local session = getSession()
  if not session then return end
  local pidConfig = session.pid_profile or {}
  local govConfig = session.governor_profile or {}
  for k, v in pairs(pidConfig) do
    ui.config[k] = v
  end
  for k, v in pairs(govConfig) do
    ui.config[k] = v
  end
end

local function isAtLeastVersion(req)
  local session = getSession()
  local rawApiVersion = session and session.apiVersion
  if not rawApiVersion or rawApiVersion == "" or tostring(rawApiVersion) == "0" then
    return true -- default true for offline/simulator
  end
  return ApiVersion and ApiVersion.isAtLeast and ApiVersion.isAtLeast(rawApiVersion, req)
end

local function queueRcRead(isAutoReload)
  if ui.runtime.readPending then return false, "read_pending" end
  if not PidProfileApi or not GovernorConfigApi or not MspRuntime or type(MspRuntime.getState) ~= "function" then
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

  local session = getSession()

  -- Step 1: Read Governor Config
  queue:add({
    command = GovernorConfigApi.command,
    simulatorResponse = GovernorConfigApi.simulatorResponse,
    processReply = function(self, buf)
      local parsedGovConfig = GovernorConfigApi.parse(buf)
      if parsedGovConfig and session then
        session.governor_config = parsedGovConfig
        session.governorMode = parsedGovConfig.gov_mode
      end
      
      -- Step 2: Read Pid Profile
      queue:add({
        command = PidProfileApi.command,
        simulatorResponse = PidProfileApi.simulatorResponse,
        processReply = function(self, buf)
          local parsedPid = PidProfileApi.parse(buf)
          if parsedPid and session then
            session.pid_profile = parsedPid
          end
          
          -- Step 3: Read Governor Profile if api version >= 12.0.9
          if isAtLeastVersion({12, 0, 9}) and GovernorProfileApi then
            queue:add({
              command = GovernorProfileApi.command,
              simulatorResponse = GovernorProfileApi.simulatorResponse,
              processReply = function(self, buf)
                local parsedGov = GovernorProfileApi.parse(buf)
                if parsedGov and session then
                  session.governor_profile = parsedGov
                end
                
                loadFromSession()
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
          else
            loadFromSession()
            ui.runtime.readPending = false
            ui.loading = false
            ui.dirty = false
            ui.progress = 100
            if type(ui.runtime.requestRebuild) == "function" then
              ui.runtime.requestRebuild()
            end
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

local function writeEeprom(queue)
  ui.dirty = false
  local eepromApi = loadModule("tasks/msp/api/eeprom_write.lua")
  if eepromApi then
    queue:add({
      command = eepromApi.command,
      payload = {},
      isWrite = true,
      processReply = function()
        queueRcRead(true)
      end
    })
  else
    queueRcRead(true)
  end
end

local function queueRcWrite()
  if not PidProfileApi or not MspRuntime or type(MspRuntime.getState) ~= "function" then
    return false, "msp_runtime_unavailable"
  end

  local mspState = MspRuntime.getState()
  local queue = mspState and mspState.queue
  if not queue or type(queue.add) ~= "function" then
    return false, "msp_queue_unavailable"
  end

  local session = getSession()
  if not session then return false, "no_session" end
  
  session.pid_profile = session.pid_profile or {}
  session.governor_profile = session.governor_profile or {}

  local pidKeys = {
    "yaw_cw_stop_gain", "yaw_ccw_stop_gain", "yaw_precomp_cutoff",
    "yaw_cyclic_ff_gain", "yaw_collective_ff_gain",
    "yaw_inertia_precomp_gain", "yaw_inertia_precomp_cutoff",
    "yaw_collective_dynamic_gain", "yaw_collective_dynamic_decay"
  }
  for _, k in ipairs(pidKeys) do
    if ui.config[k] ~= nil then
      session.pid_profile[k] = ui.config[k]
    end
  end

  local govKeys = {
    "governor_tta_gain", "governor_tta_limit"
  }
  for _, k in ipairs(govKeys) do
    if ui.config[k] ~= nil then
      session.governor_profile[k] = ui.config[k]
    end
  end

  queue:add({
    command = PidProfileApi.writeCommand,
    payload = PidProfileApi.buildWritePayload(session.pid_profile),
    isWrite = true,
    processReply = function()
      if isAtLeastVersion({12, 0, 9}) and GovernorProfileApi then
        queue:add({
          command = GovernorProfileApi.writeCommand,
          payload = GovernorProfileApi.buildWritePayload(session.governor_profile),
          isWrite = true,
          processReply = function()
            writeEeprom(queue)
          end,
          errorHandler = function() end
        })
      else
        writeEeprom(queue)
      end
    end,
    errorHandler = function() end
  })

  return true, nil
end

local function getLiveProfile()
  if Sensors and type(Sensors.getValue) == "function" then
    local raw = tonumber(Sensors.getValue("pid_profile"))
    if raw and raw > 0 then
      return math.floor(raw)
    end
  end
  local session = getSession()
  local activeProfile = tonumber(session and session.activeProfile)
  if activeProfile ~= nil then
    return math.floor(activeProfile) + 1
  end
  return 1
end

local function getBaseTitle()
  return pageText(nil, "title", "Tail Rotor")
end

local function buildSessionSignature()
  return tostring(getLiveProfile() or "1")
end

local function ensureLoaded()
  if ui.loaded then return end
  loadFromSession()
  ui.loaded = true
  ui.dirty = false
  ui.runtime.lastSessionSignature = buildSessionSignature()
  ui.baseTitle = getBaseTitle()
  queueRcRead(false)
end

local function formatValue(val, spec)
  val = tonumber(val) or 0
  local scale = spec.scale or 1
  local mult = spec.mult or 1
  local decimals = spec.decimals or 0
  
  local displayVal = (val * mult) / scale
  local fmt = "%." .. tostring(decimals) .. "f"
  return string.format(fmt, displayVal)
end

local function appendDualFieldRow(children, x, y, w, rowLabel, label1, key1, spec1, label2, key2, spec2)
  local rowH = 52
  local labelY = y + 16
  local cellTop = y + 4
  
  local mainW    = math.floor(w * 0.31)
  local labelW1  = math.floor(w * 0.19)
  local editW1   = math.floor(w * 0.14)
  local labelGap = 6
  
  -- Left main label
  children[#children + 1] = {
    type  = "label",
    x = x, y = labelY,
    w = mainW,
    text  = rowLabel,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE
  }
  
  -- Column 1
  local xLabel1 = x + mainW
  local xEdit1  = xLabel1 + labelW1
  
  children[#children + 1] = {
    type  = "label",
    x = xLabel1, y = labelY,
    w = labelW1 - labelGap,
    text  = label1,
    color = COLOR_THEME_PRIMARY1,
    font  = SMLSIZE,
    align = RIGHT
  }
  
  local spec = spec1
  local rawMin = spec.min or 0
  local rawMax = spec.max or 1000
  local stepSize = spec.step or 1
  local activeA = spec.active == nil or spec.active
  if type(activeA) == "function" then activeA = activeA() end
  
  children[#children + 1] = {
    type = "numberEdit",
    x = xEdit1,
    y = cellTop,
    w = editW1,
    h = 44,
    min = math.floor(rawMin / stepSize),
    max = math.ceil(rawMax / stepSize),
    active = function() return activeA end,
    get = function()
      local rVal = ui.config[key1] or rawMin
      if rVal < rawMin then rVal = rawMin end
      if rVal > rawMax then rVal = rawMax end
      return math.floor(rVal / stepSize)
    end,
    set = function(val)
      local rVal = math.floor((tonumber(val) or math.floor(rawMin / stepSize)) * stepSize)
      if rVal < rawMin then rVal = rawMin end
      if rVal > rawMax then rVal = rawMax end
      ui.config[key1] = rVal
      ui.dirty = true
    end,
    display = function(val)
      local rVal = math.floor((tonumber(val) or math.floor(rawMin / stepSize)) * stepSize)
      return formatValue(rVal, spec) .. spec.suffix
    end
  }

  -- Column 2
  if label2 and key2 and spec2 then
    local labelW2 = math.floor(w * 0.20)
    local editW2  = math.floor(w * 0.14)
    local xLabel2 = xEdit1 + editW1 + 5
    local xEdit2  = xLabel2 + labelW2
    
    local activeB = spec2.active == nil or spec2.active
    if type(activeB) == "function" then activeB = activeB() end

    children[#children + 1] = {
      type  = "label",
      x = xLabel2, y = labelY,
      w = labelW2 - labelGap,
      text  = label2,
      color = COLOR_THEME_PRIMARY1,
      font  = SMLSIZE,
      align = RIGHT
    }
    
    local specB = spec2
    local rawMinB = specB.min or 0
    local rawMaxB = specB.max or 1000
    local stepSizeB = specB.step or 1
    children[#children + 1] = {
      type = "numberEdit",
      x = xEdit2,
      y = cellTop,
      w = editW2,
      h = 44,
      min = math.floor(rawMinB / stepSizeB),
      max = math.ceil(rawMaxB / stepSizeB),
      active = function() return activeB end,
      get = function()
        local rVal = ui.config[key2] or rawMinB
        if rVal < rawMinB then rVal = rawMinB end
        if rVal > rawMaxB then rVal = rawMaxB end
        return math.floor(rVal / stepSizeB)
      end,
      set = function(val)
        local rVal = math.floor((tonumber(val) or math.floor(rawMinB / stepSizeB)) * stepSizeB)
        if rVal < rawMinB then rVal = rawMinB end
        if rVal > rawMaxB then rVal = rawMaxB end
        ui.config[key2] = rVal
        ui.dirty = true
      end,
      display = function(val)
        local rVal = math.floor((tonumber(val) or math.floor(rawMinB / stepSizeB)) * stepSizeB)
        return formatValue(rVal, specB) .. specB.suffix
      end
    }
  end

  children[#children + 1] = {
    type   = "rectangle",
    x = x, y = y + rowH,
    w = w, h = 1,
    color  = GREY_DEFAULT, filled = true
  }

  return rowH + 1
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
  if type(ctx) == "table" and type(ctx.requestRebuild) == "function" then
    ui.runtime.requestRebuild = ctx.requestRebuild
  end

  local signature = buildSessionSignature()
  if signature ~= ui.runtime.lastSessionSignature then
    ui.runtime.lastSessionSignature = signature
    queueRcRead(false)
  end
end

function M.getHeaderActions()
  return {
    save = true,
    reload = true,
    help = true,
    menu = true
  }
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded()
  ui.runtime.requestRebuild = ctx and ctx.requestRebuild or nil

  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local h = ctx.h
  local i18n = ctx.i18n
  
  if ui.loading then
    LoadingOverlay.append(children, {
      x = x, y = y, w = w, h = h,
      title = pageText(i18n, "loading_title", "Loading"),
      message = pageText(i18n, "loading_message", "Reading Tail Rotor Settings"),
      progress = ui.progress / 100
    })
    return
  end

  local title = ui.baseTitle or getBaseTitle()
  local profile = getLiveProfile()
  local displayTitle = string.format("%s #%d", title, profile)

  if type(ui.runtime) == "table" and type(ui.runtime.syncHeaderTitle) == "function" then
    ui.runtime.syncHeaderTitle(title, M.getHeaderActions())
  end

  local cursorY = y
  if Controls and type(Controls.appendStaticSectionHeader) == "function" then
    Controls.appendStaticSectionHeader(children, x, cursorY, w, displayTitle)
    cursorY = cursorY + (Controls.STATIC_SECTION_H or 50)
  end

  cursorY = cursorY + 10

  -- Specs
  local specGain    = { scale=1, mult=1, min=0, max=250, suffix="", decimals=0 }
  local specCutoff  = { scale=1, mult=1, min=0, max=250, suffix="Hz", decimals=0 }
  local specCutoff1 = { scale=10, mult=1, min=0, max=250, suffix="Hz", decimals=1 }
  local specLimit   = { scale=1, mult=1, min=0, max=100, suffix="%", decimals=0 }

  local session = getSession()
  local govMode = tonumber(session and session.governorMode or 0) or 0
  local isTtaActive = (govMode >= 1)

  -- 1) Yaw stop gain (CW & CCW)
  cursorY = cursorY + appendDualFieldRow(children, x, cursorY, w,
    pageText(i18n, "yaw_stop_gain", "Yaw stop gain"),
    pageText(i18n, "cw", "CW"), "yaw_cw_stop_gain", specGain,
    pageText(i18n, "ccw", "CCW"), "yaw_ccw_stop_gain", specGain
  )

  -- 2) Precomp Cutoff
  cursorY = cursorY + appendDualFieldRow(children, x, cursorY, w,
    pageText(i18n, "precomp_cutoff", "Precomp Cutoff"),
    pageText(i18n, "cutoff", "Cutoff"), "yaw_precomp_cutoff", specCutoff,
    nil, nil, nil
  )

  -- 3) Cyclic FF gain
  cursorY = cursorY + appendDualFieldRow(children, x, cursorY, w,
    pageText(i18n, "cyclic_ff_gain", "Cyclic FF gain"),
    pageText(i18n, "gain", "Gain"), "yaw_cyclic_ff_gain", specGain,
    nil, nil, nil
  )

  -- 4) Collective FF gain
  cursorY = cursorY + appendDualFieldRow(children, x, cursorY, w,
    pageText(i18n, "collective_ff_gain", "Collective FF gain"),
    pageText(i18n, "gain", "Gain"), "yaw_collective_ff_gain", specGain,
    nil, nil, nil
  )

  -- 5) Inertia Precomp (12.0.8+) OR Collective Impulse FF (<=12.0.7)
  if isAtLeastVersion({12, 0, 8}) then
    cursorY = cursorY + appendDualFieldRow(children, x, cursorY, w,
      pageText(i18n, "inertia_precomp", "Inertia Precomp"),
      pageText(i18n, "gain", "Gain"), "yaw_inertia_precomp_gain", specGain,
      pageText(i18n, "cutoff", "Cutoff"), "yaw_inertia_precomp_cutoff", specCutoff1
    )
  else
    cursorY = cursorY + appendDualFieldRow(children, x, cursorY, w,
      pageText(i18n, "collective_impulse_ff", "Collective Impulse FF"),
      pageText(i18n, "gain", "Gain"), "yaw_collective_dynamic_gain", specGain,
      pageText(i18n, "decay", "Decay"), "yaw_collective_dynamic_decay", specGain
    )
  end

  -- 6) Tail Torque Assist (12.0.9+)
  if isAtLeastVersion({12, 0, 9}) then
    local specTtaGain = { scale=1, mult=1, min=0, max=250, suffix="", decimals=0, active = isTtaActive }
    local specTtaLimit = { scale=1, mult=1, min=0, max=100, suffix="%", decimals=0, active = isTtaActive }
    
    cursorY = cursorY + appendDualFieldRow(children, x, cursorY, w,
      pageText(i18n, "tail_torque_assist", "Tail Torque Assist"),
      pageText(i18n, "tta_gain", "Gain"), "governor_tta_gain", specTtaGain,
      pageText(i18n, "tta_limit", "Limit"), "governor_tta_limit", specTtaLimit
    )
  end
end

function M.onSave(ctx)
  queueRcWrite()
  return true
end

function M.onReload(ctx)
  local session = getSession()
  if session then
    loadFromSession()
    ui.dirty = false
    queueRcRead(false)
  end
  return true
end

function M.onHelp(ctx)
  local help = loadModule("app/pages/flight_tuning/advanced/tail_rotor/help.lua")
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
  PidProfileApi = nil
  GovernorProfileApi = nil
  GovernorConfigApi = nil
  LoadingOverlay = nil
  Sensors = nil
  ApiVersion = nil
  t = nil
end

M.ui = ui
return M
