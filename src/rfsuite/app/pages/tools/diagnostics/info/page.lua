local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Version = loadModule("lib/version.lua")
local MspRuntime = loadModule("tasks/msp/runtime.lua")
local VariantApi = loadModule("tasks/msp/api/variant.lua")
local BoardInfoApi = loadModule("tasks/msp/api/board_info.lua")
local BuildInfoApi = loadModule("tasks/msp/api/build_info.lua")
local LoadingOverlay = loadModule("ui/loading_overlay.lua")

local ROW_KEYS = {
  "version",
  "edgetx_version",
  "rf_version",
  "fc_version",
  "variant",
  "board_info",
  "build_info",
  "msp_version",
  "msp_transport",
  "supported_versions",
  "simulation"
}

local state = {
  started = false,
  attached = false,
  loading = false,
  showLoadingOverlay = false,
  loadingStartedAt = 0,
  loadingTimeoutSec = 12,
  refreshIntervalSec = 45,
  lastFetchAt = 0,
  progress = 0,
  done = 0,
  total = 0,
  errorMessage = nil,
  rebuild = nil,
  values = {
    fc_version = nil,
    rf_version = nil,
    variant = "-",
    board_info = "-",
    build_info = "-"
  }
}

local function t(i18n, key, fallback)
  if i18n and i18n.t then
    return i18n.t("app.pages.diagnostics_info." .. key)
  end
  return fallback
end

local function readRuntimeField(name, fallback)
  local root = _G and _G.rfsuite
  if type(root) ~= "table" then return fallback end

  local diagnostics = root.diagnostics
  if type(diagnostics) == "table" and diagnostics[name] ~= nil then
    return tostring(diagnostics[name])
  end

  local session = root.session
  if type(session) == "table" and session[name] ~= nil then
    return tostring(session[name])
  end

  return fallback
end

local function readEdgeTxVersion()
  if type(system) == "table" and type(system.getVersion) == "function" then
    local ok, v = pcall(system.getVersion)
    if ok and type(v) == "table" then
      if v.major and v.minor and v.revision then
        return string.format("%s.%s.%s", tostring(v.major), tostring(v.minor), tostring(v.revision))
      end
      if v.version then
        return tostring(v.version)
      end
    end
  end

  if type(getVersion) == "function" then
    local ok, a = pcall(getVersion)
    if ok and type(a) == "string" and a ~= "" then
      return a
    end
  end

  return "-"
end

local function readSimulationState()
  if type(getVersion) == "function" then
    local ok, _, fw = pcall(getVersion)
    if ok and type(fw) == "string" then
      return string.sub(string.lower(fw), -4) == "simu" and "ON" or "OFF"
    end
  end
  return "OFF"
end

local function buildInfoValues()
  local runtimeState = MspRuntime and MspRuntime.getState and MspRuntime.getState() or nil
  local transport = "-"
  if type(runtimeState) == "table" then
    if runtimeState.isSimulator == true then
      transport = "SIMULATOR"
    elseif runtimeState.protocol and runtimeState.protocol ~= "" then
      transport = runtimeState.protocol
    end
  end
  if transport == "-" then
    transport = readRuntimeField("mspProtocol", "-")
  end

  return {
    version = Version.getVersionString and Version.getVersionString() or "-",
    edgetx_version = readEdgeTxVersion(),
    rf_version = state.values.rf_version or readRuntimeField("rfVersion", "-"),
    fc_version = state.values.fc_version or readRuntimeField("fcVersion", "-"),
    variant = state.values.variant,
    board_info = state.values.board_info,
    build_info = state.values.build_info,
    msp_version = readRuntimeField("apiVersion", "-"),
    msp_transport = string.upper(tostring(transport or "-")),
    supported_versions = (Version.getSupportedMspApiVersionsString and Version.getSupportedMspApiVersionsString()) or "-",
    simulation = readSimulationState()
  }
end

local function requestRebuild()
  if type(state.rebuild) == "function" then
    state.rebuild()
  end
end

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, ticks = pcall(getTime)
    if ok and type(ticks) == "number" then
      return ticks / 100
    end
  end
  if type(os) == "table" and type(os.clock) == "function" then
    return os.clock()
  end
  return 0
end

local function readRuntimeErrorMessage()
  local root = _G and _G.rfsuite
  if type(root) ~= "table" then return nil end
  local diagnostics = root.diagnostics
  if type(diagnostics) == "table" and diagnostics.mspLastError and diagnostics.mspLastError ~= "" then
    return tostring(diagnostics.mspLastError)
  end
  local session = root.session
  if type(session) == "table" and session.mspLastError and session.mspLastError ~= "" then
    return tostring(session.mspLastError)
  end
  return nil
end

local function markStepDone()
  state.done = state.done + 1
  if state.total > 0 then
    state.progress = state.done / state.total
  else
    state.progress = 1
  end
  if state.done >= state.total then
    state.loading = false
    state.showLoadingOverlay = false
    state.lastFetchAt = nowSeconds()
  end
  requestRebuild()
end

local function abortLoading(i18n, reason)
  state.done = state.total
  state.progress = 1
  state.loading = false
  state.showLoadingOverlay = false
  local prefix = t(i18n, "loading_failed", "Loading failed")
  if reason and reason ~= "" then
    state.errorMessage = prefix .. ": " .. tostring(reason)
  else
    state.errorMessage = prefix
  end
  requestRebuild()
end

local function startLiveLoad()
  if state.started then return end
  state.started = true

  if MspRuntime and type(MspRuntime.attach) == "function" and not state.attached then
    MspRuntime.attach("info-page")
    state.attached = true
  end

  local runtimeState = MspRuntime and MspRuntime.getState and MspRuntime.getState() or nil
  local queue = runtimeState and runtimeState.queue

  if type(queue) ~= "table" or type(queue.add) ~= "function" then
    state.started = false
    return
  end

  local now = nowSeconds()
  local hasCachedSlowFields = (state.values.variant and state.values.variant ~= "-")
    and (state.values.board_info and state.values.board_info ~= "-")
    and (state.values.build_info and state.values.build_info ~= "-")
  local cacheFresh = state.lastFetchAt > 0 and (now - state.lastFetchAt) < state.refreshIntervalSec

  if hasCachedSlowFields and cacheFresh then
    state.loading = false
    state.showLoadingOverlay = false
    state.progress = 1
    state.done = state.total
    return
  end

  state.loading = true
  state.showLoadingOverlay = not hasCachedSlowFields
  state.loadingStartedAt = nowSeconds()
  state.done = 0
  state.total = 3
  state.progress = 0
  state.errorMessage = nil

  local function onFailure(name, cmd)
    local runtimeMsg = readRuntimeErrorMessage()
    local details = runtimeMsg or (tostring(name or "MSP") .. " failed (cmd=" .. tostring(cmd or "?") .. ")")
    abortLoading(nil, details)
  end

  queue:add({
    command = VariantApi.command,
    simulatorResponse = VariantApi.simulatorResponse,
    processReply = function(_, buf)
      local parsed = VariantApi.parse(buf)
      if parsed and parsed.variant and parsed.variant ~= "" then
        state.values.variant = parsed.variant
      end
      markStepDone()
    end,
    errorHandler = function() onFailure("VARIANT", VariantApi.command) end
  })

  queue:add({
    command = BoardInfoApi.command,
    simulatorResponse = BoardInfoApi.simulatorResponse,
    retryDelay = 1.6,
    timeout = 4.0,
    processReply = function(_, buf)
      local parsed = BoardInfoApi.parse(buf)
      if parsed then
        if parsed.boardName and parsed.boardName ~= "" then
          state.values.board_info = parsed.boardName
        else
          state.values.board_info = string.format("ID %d", tonumber(parsed.boardId) or 0)
        end
      end
      markStepDone()
    end,
    errorHandler = function() onFailure("BOARD_INFO", BoardInfoApi.command) end
  })

  queue:add({
    command = BuildInfoApi.command,
    simulatorResponse = BuildInfoApi.simulatorResponse,
    retryDelay = 1.6,
    timeout = 4.0,
    processReply = function(_, buf)
      local parsed = BuildInfoApi.parse(buf)
      if parsed and parsed.buildInfo and parsed.buildInfo ~= "" then
        state.values.build_info = parsed.buildInfo
      end
      markStepDone()
    end,
    errorHandler = function() onFailure("BUILD_INFO", BuildInfoApi.command) end
  })

  requestRebuild()
end

function M.getModuleTitle()
  return "Info"
end

function M.isPageOpen()
  return true
end

function M.build(ctx)
  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local h = ctx.h
  local i18n = ctx.i18n

  state.rebuild = ctx.requestRebuild
  startLiveLoad()

  local values = buildInfoValues()
  local rowY = y + 6
  local rowH = 44
  local labelW = math.floor(w * 0.56)
  local valueX = x + labelW
  local valueW = w - labelW

  for i = 1, #ROW_KEYS do
    local key = ROW_KEYS[i]
    local thisY = rowY + (i - 1) * rowH
    local labelText = t(i18n, key, key)
    local valueText = values[key] or "-"

    children[#children + 1] = {
      type = "label",
      x = x,
      y = thisY + 8,
      w = labelW - 10,
      text = labelText,
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }

    children[#children + 1] = {
      type = "label",
      x = valueX,
      y = thisY + 8,
      w = valueW - 6,
      text = tostring(valueText),
      color = COLOR_THEME_PRIMARY1,
      align = RIGHT,
      font = SMLSIZE
    }

    children[#children + 1] = {
      type = "rectangle",
      x = x,
      y = thisY + rowH - 2,
      w = w,
      h = 1,
      color = COLOR_THEME_SECONDARY1,
      filled = true
    }
  end

  if state.loading and state.showLoadingOverlay then
    local elapsed = nowSeconds() - (state.loadingStartedAt or 0)
    if elapsed >= (state.loadingTimeoutSec or 12) then
      abortLoading(i18n, readRuntimeErrorMessage() or t(i18n, "loading_timeout", "Timeout"))
    end
    local title = t(i18n, "loading_title", "Loading")
    local message = string.format("%s %d/%d", t(i18n, "loading_message", "Reading live data"), state.done, state.total)
    LoadingOverlay.append(children, {
      x = x,
      y = y,
      w = w,
      h = h,
      title = title,
      message = message,
      progress = state.progress
    })
  elseif state.errorMessage and state.errorMessage ~= "" then
    children[#children + 1] = {
      type = "label",
      x = x,
      y = y + 6,
      w = w,
      text = state.errorMessage,
      color = RED,
      font = SMLSIZE
    }
  end
end

function M.wakeup()
end

function M.paint()
end

function M.handleEvent(eventData)
  return eventData
end

function M.closePage()
  if state.attached and MspRuntime and type(MspRuntime.detach) == "function" then
    MspRuntime.detach("info-page")
  end
  state.started = false
  state.attached = false
  state.loading = false
  state.loadingStartedAt = 0
  state.progress = 0
  state.done = 0
  state.total = 0
  state.errorMessage = nil
  state.rebuild = nil
end

return M
