local root = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]bin[/\\]tests[/\\]") or ".")
local runtimePath = root .. "/src/rfsuite/widgets/dashboard/runtime.lua"
if arg and arg[1] == "--runtime" and arg[2] then runtimePath = arg[2] end
local Stubs = assert(loadfile(root .. "/bin/accounting/stubs/edgetx.lua"))()
local FC = assert(loadfile(root .. "/bin/accounting/stubs/fc.lua"))()

local passed = 0
local function check(name, condition)
  if not condition then error("dashboard standby integration failed: " .. name, 0) end
  passed = passed + 1
end

local function install()
  Stubs.install(root)
  FC.install(Stubs)
  Stubs.reset()
  FC.reset()
end

-- Exercise the actual settings page and its controls. An invalid draft must stop before the
-- writer; a failed writer must leave the live preferences exactly as they were.
install()
Stubs.installTool()
do
  local Page = assert(loadfile(root .. "/src/rfsuite/app/pages/settings/dashboard/standby/page.lua"))()
  local writes, reports, saveSucceeds = 0, {}, false
  local ctx = {
    preferences = { dashboard = { standby_enabled = false, standby_layout = "-" } },
    i18n = {}, children = {}, x = 0, y = 0, w = 600,
    requestRebuild = function() end,
    reportSave = function(report) reports[#reports + 1] = report end,
    savePreferences = function() writes = writes + 1; return saveSucceeds, saveSucceeds and nil or "control" end,
  }
  Page.onReload(ctx)
  Page.onSave(ctx)
  check("invalid draft never calls preference writer", writes == 0)

  ctx.preferences.dashboard.standby_enabled = false
  ctx.preferences.dashboard.standby_layout = "clock:small,model:full"
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "toggle" then node.set(true); break end
  end
  Page.onSave(ctx)
  check("failed save calls writer once", writes == 1)
  check("failed save restores enabled preference", ctx.preferences.dashboard.standby_enabled == false)
  check("failed save restores layout preference",
    ctx.preferences.dashboard.standby_layout == "clock:small,model:full")

  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "button" and node.text == "Move down" then node.press(); break end
  end
  saveSucceeds = true
  Page.onSave(ctx)
  check("successful toggle survives save", ctx.preferences.dashboard.standby_enabled == true)
  check("move preserves item size association",
    ctx.preferences.dashboard.standby_layout == "model:full,clock:small")
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "button" and node.text == "Remove" then node.press(); break end
  end
  Page.onSave(ctx)
  check("remove keeps the remaining item and size",
    ctx.preferences.dashboard.standby_layout == "clock:small")
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "toggle" then
      check("saved enable value reads back through actual control", node.get() == true)
      break
    end
  end
  Page.onClose()
end

-- Use the actual dashboard runtime with the accounting radio/FC surface. The provider methods
-- are observed at their public boundary; no copy of the standby predicate lives in this test.
install()
do
  local Config = assert(_G.rfsuite.require("lib/elrs_config.lua"))
  local calls = { identity = 0, request = 0, step = 0, cancel = 0, requestOwners = {}, cancelOwners = {} }
  local original = {
    currentIdentity = Config.currentIdentity, request = Config.request,
    step = Config.step, cancel = Config.cancel,
  }
  Config.currentIdentity = function() calls.identity = calls.identity + 1; return "integration-model" end
  Config.request = function(_, context)
    calls.request = calls.request + 1
    calls.requestOwners[#calls.requestOwners + 1] = context and context.owner
    return true, "reading"
  end
  Config.step = function(context)
    calls.step = calls.step + 1
    return { status = "ready", identity = "integration-model", readAt = calls.step,
      packetRate = tostring(context and context.owner), telemetryRatio = "1:16",
      maxPower = "1000", dynamic = "Off", fields = {} }
  end
  Config.cancel = function(owner)
    calls.cancel = calls.cancel + 1
    calls.cancelOwners[#calls.cancelOwners + 1] = owner
  end

  local Runtime = assert(loadfile(runtimePath))()
  local MspRuntime = assert(_G.rfsuite.require("tasks/msp/runtime.lua"))
  local originalFbl = MspRuntime.isFblConnected
  local forceFbl = false
  MspRuntime.isFblConnected = function()
    if forceFbl then return true end
    return type(originalFbl) == "function" and originalFbl() or false
  end
  local widget = Runtime.new({ x = 0, y = 0, w = 800, h = 480 }, {})
  widget.preferences.dashboard = widget.preferences.dashboard or {}
  widget.preferences.dashboard.standby_enabled = true
  widget.preferences.dashboard.standby_layout = "elrs:full"
  widget.state.fblConnected = false
  widget.state.armed = false
  widget.state.hadInflightFlight = false
  widget.flightMode = "preflight"

  Stubs.tick()
  widget:refresh(0, nil)
  local afterState = calls.request
  check("eligible fullscreen drives standby provider", afterState > 0 and calls.step > 0)
  widget:refresh(0, nil)
  check("standby build pass does not probe provider", calls.request == afterState)

  local identityBefore = calls.identity
  widget._job = nil
  Stubs.tick()
  widget:refresh(0, nil)
  check("identity is cached below one second", calls.identity == identityBefore)
  for _ = 1, 30 do Stubs.tick() end
  widget._job = nil
  widget:refresh(0, nil)
  check("identity refreshes on its bounded cadence", calls.identity > identityBefore)
  check("ELRS snapshot reaches standby cache", widget._standbyCache
    and widget._standbyCache.elrs and widget._standbyCache.elrs.packetRate ~= nil)

  widget._job = nil
  widget._standbyActive = false
  widget.state.armed, widget.state.hadInflightFlight = false, false
  widget.flightMode = "preflight"
  forceFbl = true
  local beforeFblRequest, beforeFblStep = calls.request, calls.step
  Stubs.tick()
  widget:refresh(0, nil)
  check("detected FBL keeps standby render while yielding module transport",
    calls.request == beforeFblRequest and calls.step == beforeFblStep
      and widget._standbyActive ~= true
      and ((widget._job and widget._job.kind == "standby")
        or (type(widget.renderKey) == "string" and string.sub(widget.renderKey, 1, 8) == "standby|")))
  forceFbl = false

  local function excluded(name, setup)
    widget._job = nil
    widget._standbyActive = false
    setup()
    local before = calls.request
    Stubs.tick()
    widget:refresh(0, nil)
    check(name, calls.request == before and widget._standbyActive ~= true
      and not (widget._job and widget._job.kind == "standby")
      and not (type(widget.renderKey) == "string" and string.sub(widget.renderKey, 1, 8) == "standby|"))
  end
  excluded("armed state excludes standby", function() widget.state.armed = true end)
  excluded("prior flight excludes standby", function()
    widget.state.armed = false; widget.state.hadInflightFlight = true; widget.flightMode = "preflight"
  end)
  excluded("postflight excludes standby", function()
    widget.state.hadInflightFlight = true; widget.state.rfConnected = true; widget.flightMode = "postflight"
  end)
  excluded("offline excludes standby", function()
    widget.state.hadInflightFlight = true; widget.state.rfConnected = false; widget.flightMode = "offline"
  end)

  widget.state.armed, widget.state.hadInflightFlight, widget.flightMode = false, false, "preflight"
  widget._job = nil
  widget:refresh(0, nil)
  check("standby re-entry starts a fresh request", widget._standbyActive == true)
  widget._toolHost = { phase = "run", home = { run = function() return 0 end }, cpuHits = 0 }
  local beforeCancel = calls.cancel
  widget:refresh(0, nil)
  check("hosted tool releases standby owner", calls.cancel > beforeCancel and widget._standbyActive ~= true)

  widget._toolHost = nil
  widget._job = nil
  widget:refresh(0, nil)
  check("standby enters after hosted tool closes", widget._standbyActive == true)
  beforeCancel = calls.cancel
  widget:background()
  check("background transition releases standby owner", calls.cancel > beforeCancel
    and widget._standbyActive ~= true)

  local firstOwner = calls.requestOwners[1]
  local second = Runtime.new({ x = 0, y = 0, w = 800, h = 480 }, {})
  second.preferences.dashboard = second.preferences.dashboard or {}
  second.preferences.dashboard.standby_enabled = true
  second.preferences.dashboard.standby_layout = "elrs:full"
  second.state.fblConnected, second.state.armed = false, false
  second.state.hadInflightFlight, second.flightMode = false, "preflight"
  second:refresh(0, nil)
  local secondOwner = calls.requestOwners[#calls.requestOwners]
  check("separate widgets use separate standby owners", firstOwner ~= nil and secondOwner ~= nil
    and type(firstOwner) == "string" and type(secondOwner) == "string" and firstOwner ~= secondOwner)
  check("separate widgets keep separate standby caches", second._standbyCache ~= widget._standbyCache
    and second._standbyCache.elrs.packetRate ~= widget._standbyCache.elrs.packetRate)

  for key, value in pairs(original) do Config[key] = value end
  MspRuntime.isFblConnected = originalFbl
end

Stubs.releaseCard()
print(string.format("dashboard_standby_integration_test: %d checks passed", passed))
