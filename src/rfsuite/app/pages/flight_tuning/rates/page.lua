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
local RcTuningApi = nil
local LoadingOverlay = nil
local Sensors = nil
local t = nil

M.eepromWrite = true

local RATE_TABLES = {
  [0] = { -- None
    nameKey = "none",
    cols = { "rc_rate", "rate", "expo" },
    fields = {
      { { apikey="rcRates_1", scale=1 }, { apikey="rates_1", scale=1 }, { apikey="rcExpo_1", scale=1 } },
      { { apikey="rcRates_2", scale=1 }, { apikey="rates_2", scale=1 }, { apikey="rcExpo_2", scale=1 } },
      { { apikey="rcRates_3", scale=1 }, { apikey="rates_3", scale=1 }, { apikey="rcExpo_3", scale=1 } },
      { { apikey="rcRates_4", scale=1 }, { apikey="rates_4", scale=1 }, { apikey="rcExpo_4", scale=1 } }
    }
  },
  [1] = { -- Betaflight
    nameKey = "betaflight",
    cols = { "rc_rate", "superrate", "expo" },
    fields = {
      { { apikey="rcRates_1", scale=100 }, { apikey="rates_1", scale=100 }, { apikey="rcExpo_1", scale=100 } },
      { { apikey="rcRates_2", scale=100 }, { apikey="rates_2", scale=100 }, { apikey="rcExpo_2", scale=100 } },
      { { apikey="rcRates_3", scale=100 }, { apikey="rates_3", scale=100 }, { apikey="rcExpo_3", scale=100 } },
      { { apikey="rcRates_4", scale=100 }, { apikey="rates_4", scale=100 }, { apikey="rcExpo_4", scale=100 } }
    }
  },
  [2] = { -- Raceflight
    nameKey = "raceflight",
    cols = { "rc_rate", "acroplus", "expo" },
    fields = {
      { { apikey="rcRates_1", scale=1, mult=10 }, { apikey="rates_1", scale=1 }, { apikey="rcExpo_1", scale=1 } },
      { { apikey="rcRates_2", scale=1, mult=10 }, { apikey="rates_2", scale=1 }, { apikey="rcExpo_2", scale=1 } },
      { { apikey="rcRates_3", scale=1, mult=10 }, { apikey="rates_3", scale=1 }, { apikey="rcExpo_3", scale=1 } },
      { { apikey="rcRates_4", scale=4 }, { apikey="rates_4", scale=1 }, { apikey="rcExpo_4", scale=1 } }
    }
  },
  [3] = { -- KISS
    nameKey = "kiss",
    cols = { "rc_rate", "rate", "rc_curve" },
    fields = {
      { { apikey="rcRates_1", scale=100 }, { apikey="rates_1", scale=100 }, { apikey="rcExpo_1", scale=100 } },
      { { apikey="rcRates_2", scale=100 }, { apikey="rates_2", scale=100 }, { apikey="rcExpo_2", scale=100 } },
      { { apikey="rcRates_3", scale=100 }, { apikey="rates_3", scale=100 }, { apikey="rcExpo_3", scale=100 } },
      { { apikey="rcRates_4", scale=100 }, { apikey="rates_4", scale=100 }, { apikey="rcExpo_4", scale=100 } }
    }
  },
  [4] = { -- Actual
    nameKey = "actual",
    cols = { "center_sensitivity", "max_rate", "expo" },
    fields = {
      { { apikey="rcRates_1", scale=1, mult=10 }, { apikey="rates_1", scale=1, mult=10 }, { apikey="rcExpo_1", scale=100 } },
      { { apikey="rcRates_2", scale=1, mult=10 }, { apikey="rates_2", scale=1, mult=10 }, { apikey="rcExpo_2", scale=100 } },
      { { apikey="rcRates_3", scale=1, mult=10 }, { apikey="rates_3", scale=1, mult=10 }, { apikey="rcExpo_3", scale=100 } },
      { { apikey="rcRates_4", scale=4 }, { apikey="rates_4", scale=4 }, { apikey="rcExpo_4", scale=100 } }
    }
  },
  [5] = { -- Quick
    nameKey = "quick",
    cols = { "rc_rate", "max_rate", "expo" },
    fields = {
      { { apikey="rcRates_1", scale=100 }, { apikey="rates_1", scale=1, mult=10 }, { apikey="rcExpo_1", scale=100 } },
      { { apikey="rcRates_2", scale=100 }, { apikey="rates_2", scale=1, mult=10 }, { apikey="rcExpo_2", scale=100 } },
      { { apikey="rcRates_3", scale=100 }, { apikey="rates_3", scale=1, mult=10 }, { apikey="rcExpo_3", scale=100 } },
      { { apikey="rcRates_4", scale=100 }, { apikey="rates_4", scale=1, mult=4.807 }, { apikey="rcExpo_4", scale=100 } }
    }
  },
  [6] = { -- Rotorflight
    nameKey = "rotorflight",
    cols = { "rate", "shape", "expo" },
    fields = {
      { { apikey="rcRates_1", scale=1, mult=5 }, { apikey="rates_1", scale=1 }, { apikey="rcExpo_1", scale=1 } },
      { { apikey="rcRates_2", scale=1, mult=5 }, { apikey="rates_2", scale=1 }, { apikey="rcExpo_2", scale=1 } },
      { { apikey="rcRates_3", scale=1, mult=5 }, { apikey="rates_3", scale=1 }, { apikey="rcExpo_3", scale=1 } },
      { { apikey="rcRates_4", scale=40, mult=5 }, { apikey="rates_4", scale=1 }, { apikey="rcExpo_4", scale=1 } }
    }
  }
}

local ROWS_STANDARD = { "roll", "pitch", "yaw", "collective" }
local ROWS_POLAR = { "cyclic", "yaw", "collective" }

local function newRuntime()
  return {
    readPending = false,
    requestRebuild = nil,
    fieldSetters = {},
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

local function ensureRuntime()
  if type(ui.runtime) ~= "table" then
    ui.runtime = newRuntime()
  end
end

local function getSession()
  local root = _G and _G.rfsuite
  return root and root.session or nil
end

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not MspRuntime then MspRuntime = loadModule("tasks/msp/runtime.lua") end
  if not RcTuningApi then RcTuningApi = loadModule("tasks/msp/api/rc_tuning.lua") end
  if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
  if not Sensors then Sensors = loadModule("lib/sensors.lua") end
  if not t then t = Common and Common.pageT("flight_tuning_rates") or nil end
  if Common and not ui.runtimeBase then
    ui.runtimeBase = Common.createProfileAwareRuntime({
      profileGetter = function()
        local sensorProfile = nil
        if Sensors and type(Sensors.getValue) == "function" then
          sensorProfile = tonumber(Sensors.getValue("rate_profile"))
        end
        if sensorProfile and sensorProfile > 0 then
          return math.floor(sensorProfile)
        end
        local session = getSession()
        local activeProfile = session and session.activeRateProfile
        if activeProfile ~= nil then
          return math.floor(tonumber(activeProfile) or 0) + 1
        end
        return nil
      end
    })
    if type(ui.runtime) ~= "table" then
      ui.runtime = newRuntime()
    end
    setmetatable(ui.runtime, { __index = ui.runtimeBase })
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

local function getRcConfig(session)
  if type(session) ~= "table" then return nil end
  if type(session.rc_tuning) ~= "table" then
    if type(session.rcTuning) == "table" then
      session.rc_tuning = session.rcTuning
    else
      session.rc_tuning = {}
    end
  end
  session.rcTuning = session.rc_tuning
  return session.rc_tuning
end

local function markDirty()
  ui.dirty = true
end

-- Formats a raw value into a display string based on scale and mult
local function formatValue(val, scale, mult)
  val = tonumber(val) or 0
  scale = tonumber(scale) or 1
  mult = tonumber(mult) or 1
  
  local displayVal = (val * mult) / scale
  
  if scale == 100 then
    return string.format("%.2f", displayVal)
  elseif scale == 10 then
    return string.format("%.1f", displayVal)
  elseif scale == 4 then
    return string.format("%.1f", displayVal)
  elseif scale == 40 then
    return string.format("%.2f", displayVal)
  else
    return string.format("%.0f", displayVal)
  end
end

-- Parses a string input back into a raw value
local function parseValue(str, scale, mult)
  local num = tonumber(str)
  if not num then return 0 end
  scale = tonumber(scale) or 1
  mult = tonumber(mult) or 1
  return math.floor((num * scale) / mult + 0.5)
end

local function getFieldSetter(fieldName, spec)
  local setter = ui.runtime.fieldSetters[fieldName]
  if setter then return setter end
  setter = function(value)
    -- Value comes in as string from UI (or raw number from increment)
    local rawVal
    if type(value) == "string" then
      rawVal = parseValue(value, spec.scale, spec.mult)
    else
      rawVal = parseValue(tostring(value), spec.scale, spec.mult)
    end
    
    if ui.config[fieldName] == rawVal then return end
    ui.config[fieldName] = rawVal
    markDirty()
  end
  ui.runtime.fieldSetters[fieldName] = setter
  return setter
end

local function buildSessionSignature()
  local profile = nil
  if Sensors and type(Sensors.getValue) == "function" then
    profile = tonumber(Sensors.getValue("rate_profile"))
  end
  if profile == nil or profile <= 0 then
    local session = getSession()
    profile = math.floor(tonumber(session and session.activeRateProfile) or 0) + 1
  end
  return tostring(profile)
end

local function loadFromSession()
  local session = getSession()
  local rcConfig = getRcConfig(session)
  if not rcConfig then return end
  
  -- We don't have a specific FIELD_KEYS array since it's dynamic, 
  -- but we can just copy the whole dict.
  for k, v in pairs(rcConfig) do
    ui.config[k] = v
  end
end

local function getBaseTitle()
  local root = _G and _G.rfsuite
  local app = root and root.app or nil
  local title = nil
  if app and type(app.getPageTitle) == "function" then
    title = app.getPageTitle()
  end
  return title or "Rates"
end

local function queueRcRead()
  if not RcTuningApi or not MspRuntime or type(MspRuntime.getState) ~= "function" then
    return false, "msp_runtime_unavailable"
  end

  local mspState = MspRuntime.getState()
  local queue = mspState and mspState.queue
  if not queue or type(queue.add) ~= "function" then
    return false, "msp_queue_unavailable"
  end

  ui.runtime.readPending = true
  ui.loading = true
  ui.progress = 0

  queue:add({
    command = RcTuningApi.command,
    simulatorResponse = RcTuningApi.simulatorResponse,
    timeout = 5.0,
    processReply = function(self, buf)
      local parsed = RcTuningApi.parse(buf)
      if parsed then
        local session = getSession()
        if session then
          local rcConfig = getRcConfig(session)
          for k, v in pairs(parsed) do
            rcConfig[k] = v
          end
          loadFromSession()
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
      ui.progress = 1
    end
  })

  return true, nil
end

local function ensureLoaded()
  ensureRuntime()
  if ui.loaded then return end
  loadFromSession()
  ui.loaded = true
  ui.dirty = false
  ui.runtime.lastSessionSignature = buildSessionSignature()
  ui.baseTitle = getBaseTitle()
  queueRcRead()
end

local function queueRcWrite(session)
  if not RcTuningApi or not MspRuntime or type(MspRuntime.getState) ~= "function" then
    return false, "msp_runtime_unavailable"
  end

  local mspState = MspRuntime.getState()
  local queue = mspState and mspState.queue
  if not queue or type(queue.add) ~= "function" then
    return false, "msp_queue_unavailable"
  end

  local rcConfig = getRcConfig(session)
  if not rcConfig then
    return false, "rc_config_unavailable"
  end

  queue:add({
    command = RcTuningApi.writeCommand,
    payload = RcTuningApi.buildWritePayload(rcConfig),
    timeout = 5.0,
    isWrite = true,
    processReply = function() end,
    errorHandler = function() end
  })

  return true, nil
end

local function applyConfigToSession(session)
  local rcConfig = getRcConfig(session)
  if not rcConfig then return nil end
  for k, v in pairs(ui.config) do
    rcConfig[k] = v
  end
  session.rc_tuning = rcConfig
  session.rcTuning = rcConfig
  return rcConfig
end

local function getGridMetrics(w, numCols)
  local labelMin = 84
  local labelMax = 132
  local gapMin = 3
  local gapMax = 8
  local cellMin = 54
  if w >= 700 then
    labelMin = 96
    labelMax = 152
    gapMin = 5
    gapMax = 10
    cellMin = 62
  end

  if Controls and type(Controls.computeGridMetrics) == "function" then
    local m = Controls.computeGridMetrics(w, numCols, {
      labelRatio = 0.24,
      labelMin = labelMin,
      labelMax = labelMax,
      gapMin = gapMin,
      gapMax = gapMax,
      cellMin = cellMin
    })
    return m.labelW, m.gap, m.cellW
  end
  local labelW = math.floor(w * 0.24)
  local gap = 8
  local cellW = math.floor((w - labelW - (gap * (numCols - 1))) / numCols)
  return labelW, gap, cellW
end

local function getLayoutProfile(w, h)
  local profile = {
    headerFont = MIDSIZE,
    headerTextY = 0,
    headerLineY = 36,
    headerH = 40,
    rowFont = MIDSIZE,
    rowH = 44,
    rowLabelY = 8,
    cellTop = 4,
    afterHeaderGap = 6
  }

  if w >= 700 then
    profile.headerFont = MIDSIZE
    profile.headerTextY = 2
    profile.headerLineY = 40
    profile.headerH = 44
    profile.rowFont = MIDSIZE
    profile.rowH = 46
    profile.rowLabelY = 10
    profile.cellTop = 6
    profile.afterHeaderGap = 6
  elseif w < 560 then
    profile.headerFont = SMLSIZE
    profile.headerTextY = 0
    profile.headerLineY = 24
    profile.headerH = 30
    profile.rowFont = SMLSIZE
    profile.rowH = 40
    profile.rowLabelY = 10
    profile.cellTop = 4
    profile.afterHeaderGap = 6
  end

  return profile
end

local function drawColumnHeader(children, x, y, w, i18n, layout, cols)
  local labelW, gap, cellW = getGridMetrics(w, #cols)
  local headerFont = (layout and layout.headerFont) or MIDSIZE
  local headerTextY = (layout and layout.headerTextY) or 0
  local headerLineY = (layout and layout.headerLineY) or 28
  local headerH = (layout and layout.headerH) or 34

  children[#children + 1] = {
    type = "rectangle",
    x = x,
    y = y + headerLineY,
    w = w,
    h = 1,
    color = GREY_DEFAULT,
    filled = true
  }

  for i = 1, #cols do
    local cellX = x + labelW + ((i - 1) * (cellW + gap))
    local headerText = string.upper(pageText(i18n, cols[i], string.upper(cols[i])))
    children[#children + 1] = {
      type = "label",
      x = cellX,
      y = y + headerTextY,
      w = cellW,
      text = headerText,
      color = COLOR_THEME_PRIMARY1,
      font = headerFont,
      align = CENTER
    }
  end
  return headerH
end

local function drawGrid(children, x, y, w, i18n, layoutParams, tableDef, rowsConfig)
  local labelW, gap, cellW = getGridMetrics(w, #tableDef.cols)
  local cursorY = y
  local rowH = (layoutParams and layoutParams.rowH) or 44
  local rowLabelY = (layoutParams and layoutParams.rowLabelY) or 8
  local cellTop = (layoutParams and layoutParams.cellTop) or 4

  for i = 1, #rowsConfig do
    local rowKey = rowsConfig[i]
    local labelText = pageText(i18n, rowKey, rowKey)

    children[#children + 1] = {
      type = "label",
      x = x,
      y = cursorY + rowLabelY,
      w = labelW,
      text = labelText,
      color = COLOR_THEME_PRIMARY1,
      font = layoutParams and layoutParams.rowFont or MIDSIZE
    }

    local rowFields = tableDef.fields[i]
    for j = 1, #rowFields do
      local spec = rowFields[j]
      local cellX = x + labelW + ((j - 1) * (cellW + gap))
      
      if spec and not spec.disable then
        local rawVal = ui.config[spec.apikey] or 0
        local displayVal = formatValue(rawVal, spec.scale, spec.mult)
        
        Controls.appendNumberField(
          children,
          cellX,
          cursorY + cellTop,
          cellW,
          rowH - (cellTop * 2),
          displayVal,
          getFieldSetter(spec.apikey, spec),
          nil, nil, nil, -- min, max, step not strictly used in display text mode
          nil, COLOR_THEME_PRIMARY1
        )
      end
    end
    cursorY = cursorY + rowH
  end

  return cursorY
end

function M.getModuleTitle()
  return ui.baseTitle or "Rates"
end

function M.isPageOpen()
  return true
end

function M.getHeaderActions()
  return { reload = true, save = true, help = true }
end

function M.onReload(ctx)
  local session = getSession()
  if session then
    loadFromSession()
    ui.dirty = false
    queueRcRead()
  end
  return true
end

function M.onSave(ctx)
  local session = getSession()
  if session then
    applyConfigToSession(session)
    queueRcWrite(session)
    ui.dirty = false
    
    local mspState = MspRuntime and type(MspRuntime.getState) == "function" and MspRuntime.getState()
    if mspState and mspState.queue then
      local eepromApi = loadModule("tasks/msp/api/eeprom_write.lua")
      if eepromApi then
        mspState.queue:add({
          command = eepromApi.command,
          payload = {},
          isWrite = true,
          processReply = function() end
        })
      end
    end
  end
  return true
end

function M.onHelp(ctx)
  local help = loadModule("app/pages/flight_tuning/rates/help.lua")
  if type(help) == "function" then
    return help(ctx)
  end
  return { title = "Help", message = "No help available" }
end

function M.build(ctx)
  ensureDeps()
  ui.runtime.requestRebuild = ctx.requestRebuild
  local i18n = ctx.i18n

  ensureLoaded()

  if ui.runtime.readPending and ui.loading then
    if LoadingOverlay then
      LoadingOverlay.append(ctx.children, {
        x = ctx.x, y = ctx.y, w = ctx.w, h = ctx.h,
        title = pageText(i18n, "loading_title", "Loading"),
        message = pageText(i18n, "loading_message", "Reading Rates"),
        progress = ui.progress
      })
    end
    return
  end

  local sig = buildSessionSignature()
  if sig ~= ui.runtime.lastSessionSignature then
    ui.runtime.lastSessionSignature = sig
    if not ui.dirty then
      loadFromSession()
      queueRcRead()
    end
  end

  local ratesType = ui.config.rates_type or 6 -- Default Rotorflight
  local tableDef = RATE_TABLES[ratesType]
  
  if not tableDef then
    ctx.children[#ctx.children + 1] = {
      type = "label",
      x = ctx.x, y = ctx.y + 20, w = ctx.w,
      text = "Unsupported rates type",
      color = COLOR_THEME_WARNING,
      align = CENTER
    }
    return
  end

  local isPolar = ui.config.cyclic_polarity == 1
  local rowsConfig = isPolar and ROWS_POLAR or ROWS_STANDARD
  
  -- If polar, we skip roll/pitch and use cyclic, mapping it correctly
  -- For display, we just map row 1, 2, 3 of fields.
  if isPolar then
    -- adjust fields index if needed. Ethos uses same rows but maps cyclic to row 1.
    -- Assuming field arrays match rows 1:1
  end

  -- Update title
  local typeName = pageText(i18n, tableDef.nameKey, string.upper(tableDef.nameKey))
  ui.baseTitle = typeName .. " " .. pageText(i18n, "title", "Rates")

  local layoutProfile = getLayoutProfile(ctx.w, ctx.h)

  local cursorY = ctx.y
  local headerH = drawColumnHeader(ctx.children, ctx.x, cursorY, ctx.w, i18n, layoutProfile, tableDef.cols)
  cursorY = cursorY + headerH + (layoutProfile.afterHeaderGap or 6)

  cursorY = drawGrid(ctx.children, ctx.x, cursorY, ctx.w, i18n, layoutProfile, tableDef, rowsConfig)
end

function M.wakeup()
  if ui.runtime and type(ui.runtime.wakeup) == "function" then
    ui.runtime.wakeup()
  end
end

function M.paint()
end

function M.handleEvent(eventData)
  return eventData
end

function M.closePage()
  if ui.dirty then
    -- We could implement auto-save here, but Ethos typically uses confirmation dialogs.
  end
  ui.loaded = false
end

return M
