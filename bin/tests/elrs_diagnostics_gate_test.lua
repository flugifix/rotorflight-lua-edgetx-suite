local root = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]bin[/\\]tests[/\\]") or ".")
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
  local relative = path:match("/SCRIPTS/TOOLS/rfsuite%-core/(.+)$")
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

print("elrs_diagnostics_gate_test: ok")
