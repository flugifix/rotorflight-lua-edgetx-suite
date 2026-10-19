local source = string.sub(debug.getinfo(1, "S").source, 2)
local root = string.match(source, "^(.*)[/\\]bin[/\\]tests[/\\]") or "."
local now, armChanges, pushes, invalidations, configLoads = 0, 0, {}, 0, 0
local provider = {
  acquire = function() return true end, release = function() end,
  drain = function() return true end, invalidate = function() invalidations = invalidations + 1 end,
  publish = function() end, currentIdentity = function() return "model" end,
}
local armed = {
  isArmed = function() return false end,
  changeCount = function() return armChanges end,
}
local crsf = { popFrame = function() return nil end }
_G.rfsuite = {
  session = {
    isConnected = true, telemetryType = "crsf",
    crsfTelemetryConfig = { linkRate = 500, linkRatio = 4 },
  },
  Log = { emit = function() end },
}
_G.rfsuite.require = function(path)
  if path == "lib/armed.lua" then return armed end
  if path == "lib/elrs_config.lua" then configLoads = configLoads + 1; return provider end
  if path == "lib/crsf.lua" then return crsf end
  return nil
end
getTime = function() return now * 100 end
getVersion = function() return nil, "simu" end
crossfireTelemetryPush = function(kind, payload)
  pushes[#pushes + 1] = { kind = kind, payload = payload }
  return true
end
loadScript = function(path)
  local relative = string.match(path, "/SCRIPTS/TOOLS/rfsuite%-core/(.+)$")
  if relative == "lib/elrs_config.lua" then
    configLoads = configLoads + 1
    return function() return provider end
  end
  if relative == "lib/armed.lua" then return function() return armed end end
  if relative == "lib/crsf.lua" then return function() return crsf end end
  if relative == "lib/elrs_power.lua" then return loadfile(root .. "/src/rfsuite/lib/elrs_power.lua") end
  return nil
end

local Task = assert(loadfile(root .. "/src/rfsuite/app/pages/tools/diagnostics/elrs_link/elrslink_task.lua"))()
Task.reset()
assert(configLoads == 0, "idle diagnostics reset cold-loaded the ELRS provider")

Task.start(Task.MODE_ROTORFLIGHT_TO_ELRS)
assert(configLoads == 1, "diagnostics start did not load the ELRS provider")
armChanges = 1
Task.wakeup()
assert(#pushes == 0 and not Task.isRunning(), "arming transition did not stop the sync before a write")
assert(configLoads == 1, "diagnostics completion loaded the provider a second time")

armChanges, pushes = 0, {}
Task.start(Task.MODE_PROBE)
assert(invalidations == 2, "read-only diagnostics did not preempt the paused parameter reader")
for i = 1, 4 do now = i; Task.wakeup() end
assert(not Task.isRunning() and Task.getRateField(), "simulated read-only probe did not finish")
for i = 1, #pushes do assert(pushes[i].kind ~= 0x2D, "read-only simulated probe emitted a parameter write") end
pushes = {}
assert(Task.selectOption("rate", 0))
now = 5; Task.wakeup()
assert(#pushes == 1 and pushes[1].kind == 0x2D,
  "one selected option writes=" .. tostring(#pushes) .. " kind=" .. tostring(pushes[1] and pushes[1].kind))
now = 6; Task.wakeup()
assert(#pushes == 1, "diagnostics emitted more than one write for one selected option")

do
  local savedLoadScript = loadScript
  local resetCount = 0
  loadScript = function(path)
    local relative = string.match(path, "/SCRIPTS/TOOLS/rfsuite%-core/(.+)$")
    if relative == "app/pages/settings/common.lua" then
      return function() return { pageT = function() return function(_, _, fallback) return fallback end end } end
    end
    if relative == "app/pages/setup_wizard/msp.lua" then return function() return {} end end
    if relative == "app/pages/setup_wizard/log.lua" then
      return function() return { emit = function() end, wanted = function() return false end,
        changed = function() return false end } end
    end
    return nil
  end
  local procedures = assert(loadfile(root .. "/src/rfsuite/app/pages/setup_wizard/proc_radio.lua"))()
  local link
  for i = 1, #procedures do if procedures[i].id == "link" then link = procedures[i] end end
  assert(link and type(link.leave) == "function", "setup wizard link procedure has no leave lifecycle")
  local wizard = { data = { linkProbed = true, linkSignature = "reading",
    linkTask = { reset = function() resetCount = resetCount + 1 end } } }
  link.leave(wizard)
  assert(resetCount == 1 and wizard.data.linkProbed == nil and wizard.data.linkSignature == nil,
    "setup wizard link exit retained its diagnostics task")

  local WizardPage = assert(loadfile(root .. "/src/rfsuite/app/pages/setup_wizard/page.lua"))()
  local pageUi, leaveCurrent
  for index = 1, 20 do
    local name, value = debug.getupvalue(WizardPage.onClose, index)
    if name == "leaveCurrent" then leaveCurrent = value end
    if name == "ui" then pageUi = value break end
    if name == nil then break end
  end
  assert(pageUi, "setup wizard page state was not reachable for the close lifecycle control")
  pageUi.view, pageUi.procedures, pageUi.procIndex = "run", { link }, 1
  pageUi.data = { linkProbed = true, linkSignature = "reading",
    linkTask = { reset = function() resetCount = resetCount + 1 end } }
  for index = 1, 10 do
    local name, value = debug.getupvalue(leaveCurrent, index)
    if name == "wiz" then value.data = pageUi.data break end
    if name == nil then break end
  end
  WizardPage.onClose()
  assert(resetCount == 2, "closing the setup wizard did not release the link task: " .. tostring(resetCount))
  loadScript = savedLoadScript
end

print("elrs_diagnostics_gate_test: ok")
