-- Host regression checks for Setup > ESC & Motors > Telemetry wiring detection.
local root = (arg and arg[1]) or "."
local function source(path) return root .. "/" .. path end

local TrialApi = assert(loadfile(source("src/rfsuite/tasks/msp/api/esc_sensor_trial.lua")))()
local ConfigApi = assert(loadfile(source("src/rfsuite/tasks/msp/api/esc_sensor_config.lua")))()
local Common = assert(loadfile(source("src/rfsuite/app/pages/settings/common.lua")))()
local ApiVersion = assert(loadfile(source("src/rfsuite/lib/api_version.lua")))()
local now = 100
local armedChanges = 0
local armed = false
local queued = {}
local saveRequest = nil

_G.getTime = function() return now end
_G.COLOR_THEME_SECONDARY1 = 1
_G.SMLSIZE = 1
_G.MIDSIZE = 2

local modules = {
  ["app/pages/settings/common.lua"] = Common,
  ["ui/controls.lua"] = {
    STATIC_SECTION_H = 1,
    appendStaticSectionHeader = function() end,
    appendComboSelect = function() return 1 end,
    appendRadioSwitch = function() return 1 end,
    appendNumberField = function() return 1 end
  },
  ["tasks/msp/runtime.lua"] = {
    getState = function()
      return { queue = { add = function(_, message) queued[#queued + 1] = message end } }
    end
  },
  ["tasks/msp/api/esc_sensor_config.lua"] = ConfigApi,
  ["tasks/msp/api/esc_sensor_trial.lua"] = TrialApi,
  ["ui/loading_overlay.lua"] = { append = function() end },
  ["ui/confirm_dialog.lua"] = {},
  ["lib/api_version.lua"] = ApiVersion,
  ["lib/armed.lua"] = {
    isArmed = function() return armed end,
    isUncertain = function() return false end,
    changeCount = function() return armedChanges end
  },
  ["tasks/msp/save_pipeline.lua"] = {
    takeResult = function() end,
    start = function(request) saveRequest = request; return true end
  }
}

_G.loadScript = function(path)
  local relative = string.match(path, "rfsuite%-core/(.+)$")
  local value = modules[relative]
  if not value then return nil end
  return function() return value end
end

local configReply = { 1, 0, 200, 0, 52, 18, 120, 86, 9, 30, 0, 3, 4, 5 }
local function reply(state, halfDuplex, pinSwap)
  return { state, 0, halfDuplex or 0, pinSwap or 0, 0, 0, 0, 0, 4, 1 }
end

local function newPage(apiVersion)
  queued = {}
  armed, armedChanges, now, saveRequest = false, 0, 100, nil
  _G.rfsuite = { session = {
    signature = "board", apiVersion = apiVersion or "12.0.10",
    isConnected = true, fblConnected = true,
    setup_esc_motors_telemetry = {
      protocol = 1, half_duplex = 0, pin_swap = 0,
      voltage_correction = 0, current_correction = 0, consumption_correction = 0,
      parsedCache = ConfigApi.parse(configReply)
    }
  } }
  local page = assert(loadfile(source("src/rfsuite/app/pages/setup/esc_motors/telemetry/page.lua")))()
  local ctx = { requestRebuild = function() end }
  page.wakeup(ctx)
  assert(#queued == 1 and queued[1].command == ConfigApi.command, "configuration read not queued")
  queued[1].processReply(queued[1], configReply)
  page.wakeup(ctx)
  return page, ctx
end

local function build(page)
  local children = {}
  page.build({ children = children, x = 0, y = 0, w = 600, h = 400,
    i18n = {}, requestRebuild = function() end })
  return children
end

local function press(children, text)
  for i = 1, #children do
    if children[i].type == "button" and children[i].text == text then
      children[i].press()
      return true
    end
  end
  return false
end

do
  local parsed = assert(TrialApi.parse(reply(2, 1, 1)))
  assert(parsed.state == 2 and parsed.half_duplex == 1 and parsed.pin_swap == 1)
  assert(TrialApi.parse({ 1, 2, 3, 4, 5 }) == nil)
  assert(TrialApi.buildPayload(TrialApi.ACTION_CANCEL)[1] == 2)
end

do
  local page = newPage()
  assert(#queued == 2 and queued[2].payload[1] == 0 and queued[2].isWrite == false,
    "capability poll is not an explicit read")
  queued[2].processReply(queued[2], reply(0))
  assert(press(build(page), "Detect wiring"), "Detect wiring button missing")
  local start = queued[#queued]
  assert(start.payload[1] == 1 and start.isWrite == true and start.maxRetries == 0)
  assert(page.canSave() == false and page.onReload({}) == false, "pending trial did not lock Save/Reload")
  start.processReply(start, reply(1))
  assert(page.canSave() == false and page.onReload({}) == false, "running trial did not lock Save/Reload")
  now = now + 50
  page.wakeup({ requestRebuild = function() end })
  local poll = queued[#queued]
  assert(poll.payload[1] == 0 and poll.isWrite == false and poll.maxRetries == nil)
  poll.processReply(poll, reply(2, 1, 1))
  assert(page.hasUnsavedChanges(), "successful trial did not dirty detected wiring")
  assert(page.canSave() == true and page.onSave({ requestRebuild = function() end }) == true,
    "successful trial was not saveable")
  local payload = assert(saveRequest and saveRequest.steps[1] and saveRequest.steps[1].payload)
  assert(payload[1] == 1 and payload[2] == 1 and payload[11] == 1,
    "detected Half Duplex/Pin Swap did not reach Save")
  for _, i in ipairs({ 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14 }) do
    assert(payload[i] == configReply[i], "Save changed preserved byte " .. tostring(i))
  end
  local beforeClose = #queued
  page.onClose()
  assert(#queued == beforeClose, "page close cancelled a successful trial")
end

do
  local page = newPage()
  queued[2].processReply(queued[2], reply(0))
  press(build(page), "Detect wiring")
  queued[#queued].processReply(queued[#queued], reply(1))
  now = now + 50
  page.wakeup({ requestRebuild = function() end })
  local stale = queued[#queued]
  _G.rfsuite.session.isConnected = false
  _G.rfsuite.session.fblConnected = false
  page.wakeup({ requestRebuild = function() end })
  stale.processReply(stale, reply(2, 1, 1))
  assert(not page.hasUnsavedChanges(), "stale success survived disconnect")
end

do
  local page = newPage()
  queued[2].processReply(queued[2], reply(0))
  press(build(page), "Detect wiring")
  local start = queued[#queued]
  armed = true
  armedChanges = armedChanges + 1
  armed = false
  armedChanges = armedChanges + 1
  page.wakeup({ requestRebuild = function() end })
  start.processReply(start, reply(2, 1, 1))
  assert(not page.hasUnsavedChanges() and page.canSave() == false,
    "operation survived an arm/disarm edge")
end

do
  local page = newPage()
  queued[2].processReply(queued[2], reply(0))
  press(build(page), "Detect wiring")
  local start = queued[#queued]
  assert(press(build(page), "Cancel"), "Cancel button missing while start is pending")
  start.processReply(start, reply(2, 1, 1))
  local cancel = queued[#queued]
  assert(cancel.payload[1] == 2 and cancel.maxRetries == 0, "pending Cancel lost a raced success")
  cancel.processReply(cancel, reply(0))
  assert(not page.hasUnsavedChanges() and page.canSave() == false,
    "Cancel did not restore the saved form and require Reload")
  assert(page.onReload({}) == true, "Reload was not offered after Cancel")
  local reload = queued[#queued]
  reload.processReply(reload, configReply)
  assert(page.canSave() == true, "successful Reload did not restore Save")
end

do
  local page = newPage()
  queued[2].processReply(queued[2], reply(0))
  press(build(page), "Detect wiring")
  local start = queued[#queued]
  assert(press(build(page), "Cancel"), "Cancel button missing before lost START reply")
  local beforeError = #queued
  start.errorHandler(start)
  assert(#queued == beforeError + 1, "lost START reply did not queue one Cancel")
  local cancel = queued[#queued]
  assert(cancel.payload[1] == 2 and cancel.maxRetries == 0,
    "lost START reply queued the wrong recovery mutation")
  cancel.errorHandler(cancel)
  assert(#queued == beforeError + 1, "failed Cancel repeated a mutation")
  assert(page.canSave() == false, "unknown Cancel outcome left stale configuration saveable")
end

do
  local page, ctx = newPage()
  queued[2].processReply(queued[2], reply(0))
  press(build(page), "Detect wiring")
  local staleStart = queued[#queued]
  page.onClose()
  page.wakeup(ctx)
  local reopenedRead = queued[#queued]
  staleStart.processReply(staleStart, reply(2, 1, 1))
  assert(not page.hasUnsavedChanges(), "old callback changed a reopened page")
  reopenedRead.processReply(reopenedRead, configReply)
  assert(page.canSave() == true, "reopened page did not accept its own read")
end

do
  local page = newPage()
  queued[2].processReply(queued[2], reply(0))
  press(build(page), "Detect wiring")
  queued[#queued].processReply(queued[#queued], reply(1))
  now = now + 50
  page.wakeup({ requestRebuild = function() end })
  queued[#queued].processReply(queued[#queued], { 1, 2, 3 })
  assert(page.canSave() == false, "malformed running poll left stale configuration saveable")
end

do
  local page = newPage("12.0.9")
  assert(#queued == 1, "unsupported API sent a capability command")
  assert(not press(build(page), "Detect wiring"), "unsupported API showed Detect wiring")
end

print("OK: 9 ESC wiring API/lifecycle cases")
