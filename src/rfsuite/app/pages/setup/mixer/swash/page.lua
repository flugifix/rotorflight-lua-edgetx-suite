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
local MixerConfigApi = nil
local MixerInputPitchApi = nil
local MixerInputRollApi = nil
local MixerInputCollectiveApi = nil
local LoadingOverlay = nil
local t = nil

local needsReboot = false

local function u16_to_s16(u)
  if u >= 0x8000 then
    return u - 0x10000
  else
    return u
  end
end

local function s16_to_u16(s)
  if s < 0 then return s + 0x10000 end
  return s
end

local function rateToDir(u16rate)
  return (u16_to_s16(u16rate) < 0) and 0 or 1
end

local function dirSign(d)
  return (d == 0) and -1 or 1
end

local function applyDirectionToRate(u16rate, dir01)
  if u16rate == nil then return nil end
  local s = u16_to_s16(u16rate)
  local mag = math.abs(s)
  local signed = mag * dirSign(dir01)
  return s16_to_u16(signed)
end

local ui = {
  loaded = false,
  dirty = false,
  loading = false,
  progress = 0,
  baseTitle = nil,
  config = {
    swash_type = 0,
    main_rotor_dir = 0,
    ail_direction = 1,
    ele_direction = 1,
    col_direction = 1
  },
  apiData = {},
  runtime = {
    readPending = false,
    requestRebuild = nil
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
  if not MixerConfigApi then MixerConfigApi = loadModule("tasks/msp/api/mixer_config.lua") end
  if not MixerInputPitchApi then MixerInputPitchApi = loadModule("tasks/msp/api/get_mixer_input_pitch.lua") end
  if not MixerInputRollApi then MixerInputRollApi = loadModule("tasks/msp/api/get_mixer_input_roll.lua") end
  if not MixerInputCollectiveApi then MixerInputCollectiveApi = loadModule("tasks/msp/api/get_mixer_input_collective.lua") end
  if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
  if not t then t = Common and Common.pageT("setup_mixer") or nil end

  if type(ui.runtime) ~= "table" then
    ui.runtime = {
      readPending = false,
      requestRebuild = nil
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

local function getRcConfig(session)
  if type(session) ~= "table" then return nil end
  if type(session.setup_mixer_swash) ~= "table" then
    session.setup_mixer_swash = {}
  end
  return session.setup_mixer_swash
end

local function loadFromSession()
  local session = getSession()
  local rcConfig = getRcConfig(session)
  if not rcConfig then return end
  ui.config.swash_type = rcConfig.swash_type or 0
  ui.config.main_rotor_dir = rcConfig.main_rotor_dir or 0
  ui.config.ail_direction = rcConfig.ail_direction or 1
  ui.config.ele_direction = rcConfig.ele_direction or 1
  ui.config.col_direction = rcConfig.col_direction or 1

  if type(rcConfig.apiData) == "table" then
    ui.apiData = rcConfig.apiData
  end
end

local function saveToSession()
  local session = getSession()
  local rcConfig = getRcConfig(session)
  if not rcConfig then return end
  rcConfig.swash_type = ui.config.swash_type
  rcConfig.main_rotor_dir = ui.config.main_rotor_dir
  rcConfig.ail_direction = ui.config.ail_direction
  rcConfig.ele_direction = ui.config.ele_direction
  rcConfig.col_direction = ui.config.col_direction
  rcConfig.apiData = ui.apiData
end

local function queueSwashRead(isAutoReload)
  if ui.runtime.readPending then return false, "read_pending" end
  if not MspRuntime or not MixerConfigApi or not MixerInputPitchApi or not MixerInputRollApi or not MixerInputCollectiveApi or type(MspRuntime.getState) ~= "function" then
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

  -- Step 1: Read MIXER_CONFIG
  queue:add({
    command = MixerConfigApi.command,
    simulatorResponse = MixerConfigApi.simulatorResponse,
    processReply = function(self, buf)
      local parsed = MixerConfigApi.parse(buf)
      if parsed then
        ui.apiData.MIXER_CONFIG = parsed
        ui.config.swash_type = parsed.swash_type or 0
        ui.config.main_rotor_dir = parsed.main_rotor_dir or 0
      end

      ui.progress = 25
      if type(ui.runtime.requestRebuild) == "function" then
        ui.runtime.requestRebuild()
      end

      -- Step 2: Read GET_MIXER_INPUT_PITCH
      queue:add({
        command = MixerInputPitchApi.command,
        payload = { 2 },
        simulatorResponse = MixerInputPitchApi.simulatorResponse,
        processReply = function(self, buf)
          local parsed = MixerInputPitchApi.parse(buf)
          if parsed then
            ui.apiData.GET_MIXER_INPUT_PITCH = parsed
            ui.config.ele_direction = rateToDir(parsed.rate_stabilized_pitch)
          end

          ui.progress = 50
          if type(ui.runtime.requestRebuild) == "function" then
            ui.runtime.requestRebuild()
          end

          -- Step 3: Read GET_MIXER_INPUT_ROLL
          queue:add({
            command = MixerInputRollApi.command,
            payload = { 1 },
            simulatorResponse = MixerInputRollApi.simulatorResponse,
            processReply = function(self, buf)
              local parsed = MixerInputRollApi.parse(buf)
              if parsed then
                ui.apiData.GET_MIXER_INPUT_ROLL = parsed
                ui.config.ail_direction = rateToDir(parsed.rate_stabilized_roll)
              end

              ui.progress = 75
              if type(ui.runtime.requestRebuild) == "function" then
                ui.runtime.requestRebuild()
              end

              -- Step 4: Read GET_MIXER_INPUT_COLLECTIVE
              queue:add({
                command = MixerInputCollectiveApi.command,
                payload = { 4 },
                simulatorResponse = MixerInputCollectiveApi.simulatorResponse,
                processReply = function(self, buf)
                  local parsed = MixerInputCollectiveApi.parse(buf)
                  if parsed then
                    ui.apiData.GET_MIXER_INPUT_COLLECTIVE = parsed
                    ui.config.col_direction = rateToDir(parsed.rate_stabilized_collective)
                  end

                  saveToSession()

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

local function queueSwashWrite()
  if not MspRuntime or not MixerConfigApi or not MixerInputPitchApi or not MixerInputRollApi or not MixerInputCollectiveApi or type(MspRuntime.getState) ~= "function" then
    return false, "msp_runtime_unavailable"
  end

  local mspState = MspRuntime.getState()
  local queue = mspState and mspState.queue
  if not queue or type(queue.add) ~= "function" then
    return false, "msp_queue_unavailable"
  end

  if type(ui.apiData.MIXER_CONFIG) == "table" then
    ui.apiData.MIXER_CONFIG.swash_type = ui.config.swash_type
    ui.apiData.MIXER_CONFIG.main_rotor_dir = ui.config.main_rotor_dir
  else
    return false, "loaded_data_missing"
  end

  if type(ui.apiData.GET_MIXER_INPUT_PITCH) == "table" then
    ui.apiData.GET_MIXER_INPUT_PITCH.rate_stabilized_pitch =
      applyDirectionToRate(ui.apiData.GET_MIXER_INPUT_PITCH.rate_stabilized_pitch, ui.config.ele_direction)
  else
    return false, "loaded_data_missing"
  end

  if type(ui.apiData.GET_MIXER_INPUT_ROLL) == "table" then
    ui.apiData.GET_MIXER_INPUT_ROLL.rate_stabilized_roll =
      applyDirectionToRate(ui.apiData.GET_MIXER_INPUT_ROLL.rate_stabilized_roll, ui.config.ail_direction)
  else
    return false, "loaded_data_missing"
  end

  if type(ui.apiData.GET_MIXER_INPUT_COLLECTIVE) == "table" then
    ui.apiData.GET_MIXER_INPUT_COLLECTIVE.rate_stabilized_collective =
      applyDirectionToRate(ui.apiData.GET_MIXER_INPUT_COLLECTIVE.rate_stabilized_collective, ui.config.col_direction)
  else
    return false, "loaded_data_missing"
  end

  local mixerCfgPayload = MixerConfigApi.buildWritePayload(ui.apiData.MIXER_CONFIG)
  local pitchPayload = MixerInputPitchApi.buildWritePayload(ui.apiData.GET_MIXER_INPUT_PITCH)
  local rollPayload = MixerInputRollApi.buildWritePayload(ui.apiData.GET_MIXER_INPUT_ROLL)
  local collectivePayload = MixerInputCollectiveApi.buildWritePayload(ui.apiData.GET_MIXER_INPUT_COLLECTIVE)

  queue:add({
    command = MixerConfigApi.writeCommand,
    payload = mixerCfgPayload,
    isWrite = true,
    processReply = function()
      queue:add({
        command = MixerInputPitchApi.writeCommand,
        payload = pitchPayload,
        isWrite = true,
        processReply = function()
          queue:add({
            command = MixerInputRollApi.writeCommand,
            payload = rollPayload,
            isWrite = true,
            processReply = function()
              queue:add({
                command = MixerInputCollectiveApi.writeCommand,
                payload = collectivePayload,
                isWrite = true,
                processReply = function()
                  local eepromApi = loadModule("tasks/msp/api/eeprom_write.lua")
                  if eepromApi then
                    queue:add({
                      command = eepromApi.writeCommand,
                      payload = {},
                      isWrite = true,
                      processReply = function()
                        if needsReboot then
                          local rebootApi = loadModule("tasks/msp/api/reboot.lua")
                          if rebootApi then
                            queue:add({
                              command = rebootApi.writeCommand,
                              payload = rebootApi.buildWritePayload({ rebootMode = 0 }),
                              isWrite = true,
                              processReply = function() end,
                              errorHandler = function() end
                            })
                          end
                          needsReboot = false
                        end
                      end,
                      errorHandler = function() end
                    })
                  end
                end,
                errorHandler = function() end
              })
            end,
            errorHandler = function() end
          })
        end,
        errorHandler = function() end
      })
    end,
    errorHandler = function() end
  })

  return true, nil
end

local function buildSessionSignature()
  return "1"
end

local function getBaseTitle()
  return pageText(nil, "swash", "Swashplate")
end

local function ensureLoaded()
  if ui.loaded then return end
  loadFromSession()
  ui.loaded = true
  ui.dirty = false
  ui.runtime.lastSessionSignature = buildSessionSignature()
  ui.baseTitle = getBaseTitle()
  queueSwashRead(false)
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
    queueSwashRead(false)
  end
end

function M.getHeaderActions()
  return {
    save = true,
    reload = true,
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
      message = pageText(i18n, "loading", "Reading swashplate configuration..."),
      progress = ui.progress / 100
    })
    return
  end

  local displayTitle = ui.baseTitle or getBaseTitle()

  if type(ui.runtime) == "table" and type(ui.runtime.syncHeaderTitle) == "function" then
    ui.runtime.syncHeaderTitle(displayTitle, M.getHeaderActions())
  end

  local cursorY = y
  if Controls and type(Controls.appendStaticSectionHeader) == "function" then
    Controls.appendStaticSectionHeader(children, x, cursorY, w, displayTitle)
    cursorY = cursorY + (Controls.STATIC_SECTION_H or 50)
  end

  cursorY = cursorY + 10

  -- 1) Swashplate Type
  local swashTypeChoices = {
    { value = 0, label = pageText(i18n, "swash_none", "None") },
    { value = 1, label = pageText(i18n, "swash_direct", "Direct") },
    { value = 2, label = "CPPM 120" },
    { value = 3, label = "CPPM 135" },
    { value = 4, label = "CPPM 140" },
    { value = 5, label = "FPM 90 L" },
    { value = 6, label = "FPM 90 V" }
  }
  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    pageText(i18n, "swash_type", "Swashplate type"),
    swashTypeChoices,
    ui.config.swash_type,
    function(newVal)
      if ui.config.swash_type ~= newVal then
        ui.config.swash_type = newVal
        ui.dirty = true
        needsReboot = true
      end
    end
  )

  -- 2) Rotor Direction
  local rotorDirChoices = {
    { value = 0, label = pageText(i18n, "cw", "CW") },
    { value = 1, label = pageText(i18n, "ccw", "CCW") }
  }
  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    pageText(i18n, "main_rotor_dir", "Main rotor direction"),
    rotorDirChoices,
    ui.config.main_rotor_dir,
    function(newVal)
      if ui.config.main_rotor_dir ~= newVal then
        ui.config.main_rotor_dir = newVal
        ui.dirty = true
      end
    end
  )

  -- 3) Aileron Direction
  local dirChoices = {
    { value = 0, label = pageText(i18n, "reversed", "Reversed") },
    { value = 1, label = pageText(i18n, "normal", "Normal") }
  }
  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    pageText(i18n, "aileron_direction", "Aileron direction"),
    dirChoices,
    ui.config.ail_direction,
    function(newVal)
      if ui.config.ail_direction ~= newVal then
        ui.config.ail_direction = newVal
        ui.dirty = true
      end
    end
  )

  -- 4) Elevator Direction
  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    pageText(i18n, "elevator_direction", "Elevator direction"),
    dirChoices,
    ui.config.ele_direction,
    function(newVal)
      if ui.config.ele_direction ~= newVal then
        ui.config.ele_direction = newVal
        ui.dirty = true
      end
    end
  )

  -- 5) Collective Direction
  cursorY = cursorY + Controls.appendComboSelect(children, x, cursorY, w,
    pageText(i18n, "collective_direction", "Collective direction"),
    dirChoices,
    ui.config.col_direction,
    function(newVal)
      if ui.config.col_direction ~= newVal then
        ui.config.col_direction = newVal
        ui.dirty = true
      end
    end
  )
end

function M.onSave(ctx)
  local ok, err = queueSwashWrite()
  if not ok then
    if lvgl and lvgl.message then
      lvgl.message({
        title = pageText(ctx and ctx.i18n, "save_error_title", "Error"),
        message = tostring(err or "MSP write failed")
      })
    end
    return false
  end

  ui.dirty = false
  if lvgl and lvgl.message then
    lvgl.message({
      title = pageText(ctx and ctx.i18n, "saved_title", "Saved"),
      message = pageText(ctx and ctx.i18n, "saved_message", "Swashplate settings saved")
    })
  end
  return true
end

function M.onReload(ctx)
  local session = getSession()
  if session then
    loadFromSession()
    ui.dirty = false
    queueSwashRead(false)
  end
  return true
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
  MixerConfigApi = nil
  MixerInputPitchApi = nil
  MixerInputRollApi = nil
  MixerInputCollectiveApi = nil
  LoadingOverlay = nil
  t = nil
end

return M
