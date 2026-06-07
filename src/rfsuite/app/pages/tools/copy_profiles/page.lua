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
local MspRuntime = nil
local Controls = nil
local t = nil

local state = {
  profileType = 0, -- 0=PID, 1=Rate
  sourceIndex = 0,
  destIndex = 0,
  isSaving = false,
  requestRebuild = nil,
  i18n = nil
}

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not MspRuntime then MspRuntime = loadModule("tasks/msp/runtime.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not t then t = Common and Common.pageT("tools_copy_profiles") or nil end
end

local function pageText(i18n, key, fallback)
  local obj = i18n or state.i18n
  if t then return t(obj, key, fallback) end
  return fallback
end

function M.getModuleTitle()
  return "Copy Profile"
end

function M.getHeaderActions()
  return { reload = false, save = not state.isSaving, help = true }
end

function M.isPageOpen()
  return true
end

function M.onSave(ctx)
  if state.isSaving then return false end
  
  local i18n = state.i18n
  if state.sourceIndex == state.destIndex then
    -- Ethos just logs this. We could potentially return a message if we had an alert system here.
    return false, pageText(i18n, "warn_same_profile", "Source and destination profiles are the same.")
  end

  local msp = MspRuntime
  local mspState = msp and type(msp.getState) == "function" and msp.getState()
  if not mspState or not mspState.queue then return false, "MSP link unavailable" end

  state.isSaving = true
  
  -- MSP 183: { type, destination, source }
  local payload = { state.profileType, state.destIndex, state.sourceIndex }
  
  mspState.queue:add({
    command = 183,
    payload = payload,
    isWrite = true,
    simulatorResponse = {},
    processReply = function()
      -- Now save to EEPROM
      local eepromApi = loadModule("tasks/msp/api/eeprom_write.lua")
      mspState.queue:add({
        command = eepromApi.writeCommand,
        payload = {},
        isWrite = true,
        processReply = function()
          state.isSaving = false
          if type(state.requestRebuild) == "function" then state.requestRebuild() end
        end,
        errorHandler = function() state.isSaving = false end
      })
    end,
    errorHandler = function() state.isSaving = false end
  })

  return true
end

function M.onHelp(ctx)
  local help = loadModule("app/pages/tools/copy_profiles/help.lua")
  if type(help) == "function" then
    return help(ctx)
  end
  return {
    title = pageText(ctx.i18n, "help_title", "Copy Profile"),
    message = pageText(ctx.i18n, "help_p1", "Copy settings.")
  }
end

function M.build(ctx)
  ensureDeps()
  state.requestRebuild = ctx.requestRebuild
  state.i18n = ctx.i18n

  local i18n = ctx.i18n
  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w

  local cursorY = y + 10
  
  -- Type: PID / Rate
  local typeOptions = {
    { value = 0, label = pageText(i18n, "profile_type_pid", "PID") },
    { value = 1, label = pageText(i18n, "profile_type_rate", "Rate") }
  }
  
  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    pageText(i18n, "profile_type", "Type"),
    typeOptions,
    state.profileType,
    function(val)
      state.profileType = val
    end
  )
  
  -- Source Profile
  local profileOptions = {}
  for i = 1, 6 do
    profileOptions[i] = { value = i - 1, label = tostring(i) }
  end
  
  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    pageText(i18n, "source_profile", "Source"),
    profileOptions,
    state.sourceIndex,
    function(val)
      state.sourceIndex = val
    end
  )

  -- Destination Profile
  cursorY = cursorY + Controls.appendComboSelect(
    children, x, cursorY, w,
    pageText(i18n, "dest_profile", "Destination"),
    profileOptions,
    state.destIndex,
    function(val)
      state.destIndex = val
    end
  )

  return cursorY
end

function M.wakeup()
end

function M.paint()
end

function M.handleEvent(eventData)
  return eventData
end

function M.closePage()
  state.isSaving = false
  state.requestRebuild = nil
  state.i18n = nil
  Common = nil
  MspRuntime = nil
  Controls = nil
  t = nil
end

return M
