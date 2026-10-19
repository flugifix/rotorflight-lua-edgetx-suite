local source = string.sub(debug.getinfo(1, "S").source, 2)
local root = string.match(source, "^(.*)[/\\]bin[/\\]tests[/\\]") or "."
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
  local MspRuntime = assert(_G.__rfsuite_msp_runtime_module
    or _G.rfsuite.require("tasks/msp/runtime.lua"))
  local originalMspState = MspRuntime.getState
  local forceRawConnected = false
  MspRuntime.getState = function()
    if forceRawConnected then return { lastConnected = true, versionReadCompleted = false } end
    return { lastConnected = false, versionReadCompleted = false }
  end
  local widget = Runtime.new({ x = 0, y = 0, w = 800, h = 480 }, {})
  widget.preferences.dashboard = widget.preferences.dashboard or {}
  widget.preferences.dashboard.standby_enabled = true
  widget.preferences.dashboard.standby_layout = "elrs:full"
  widget.preferences.audio_events = widget.preferences.audio_events or {}
  widget.preferences.audio_events.tpwr_alert = false
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

  check("active standby has cached localized texts before global reload",
    type(widget._standbyTexts) == "table"
      and type(widget.renderKey) == "string" and string.sub(widget.renderKey, 1, 8) == "standby|")
  widget:reload(true)
  check("global reload invalidates standby texts and visible render key",
    widget._standbyTexts == nil and widget.renderKey == nil)
  widget.preferences.dashboard = widget.preferences.dashboard or {}
  widget.preferences.dashboard.standby_enabled = true
  widget.preferences.dashboard.standby_layout = "elrs:full"

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
  widget._standbyActive = true
  widget.state.fblConnected, widget.state.armed, widget.state.hadInflightFlight = false, false, false
  widget.flightMode = "preflight"
  widget._standbyCache.elrs = { status = "reading", identity = "integration-model" }
  forceRawConnected = true
  local beforeRawRequest, beforeRawStep = calls.request, calls.step
  Stubs.tick()
  widget:refresh(0, nil)
  check("raw MSP link yields probing but keeps standby render and refreshes cancelled status",
    calls.request == beforeRawRequest and calls.step == beforeRawStep
      and widget._standbyActive ~= true and widget._standbyCache.elrs.status ~= "reading"
      and ((widget._job and widget._job.kind == "standby")
        or (type(widget.renderKey) == "string" and string.sub(widget.renderKey, 1, 8) == "standby|")))
  forceRawConnected = false

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
  local firstCache = widget._standbyCache
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
  check("separate widgets keep separate standby caches", widget._standbyCache == nil
    and second._standbyCache ~= firstCache
    and second._standbyCache.elrs.packetRate ~= firstCache.elrs.packetRate)

  second:background()

  for key, value in pairs(original) do Config[key] = value end
  MspRuntime.getState = originalMspState
end

-- Standby is a display-only module. Exercise its lifetime through the actual loader and runtime:
-- disabled widgets must not load it, active widgets share one instance, and the last exit must
-- release every widget-held reference without evicting the shared ELRS provider.
install()
do
  local standbyPath = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/standby.lua"
  local configPath = "/SCRIPTS/TOOLS/rfsuite-core/lib/elrs_config.lua"
  _G.rfsuite.clearModule("widgets/dashboard/standby.lua")
  local sharedConfig = assert(_G.rfsuite.require("lib/elrs_config.lua"))
  local originalLoadScript = loadScript
  local standbyLoads = 0
  _G.loadScript = function(path, mode)
    if path == standbyPath then standbyLoads = standbyLoads + 1 end
    return originalLoadScript(path, mode)
  end

  local Runtime = assert(loadfile(runtimePath))()
  local MspRuntime = assert(_G.__rfsuite_msp_runtime_module
    or _G.rfsuite.require("tasks/msp/runtime.lua"))
  local originalMspState = MspRuntime.getState
  MspRuntime.getState = function()
    return { lastConnected = false, versionReadCompleted = false }
  end

  local function newWidget(enabled)
    local widget = Runtime.new({ x = 0, y = 0, w = 800, h = 480 }, {})
    widget.preferences.dashboard = widget.preferences.dashboard or {}
    widget.preferences.dashboard.standby_enabled = enabled
    widget.preferences.dashboard.standby_layout = "elrs:full"
    widget.preferences.audio_events = widget.preferences.audio_events or {}
    widget.preferences.audio_events.tpwr_alert = false
    widget.state.fblConnected, widget.state.armed = false, false
    widget.state.hadInflightFlight, widget.flightMode = false, "preflight"
    return widget
  end

  local first = newWidget(false)
  first:refresh(0, nil)
  check("disabled standby does not load display module", standbyLoads == 0
    and _G.rfsuite.modules[standbyPath] == nil and first._standbyModule == nil)

  first.preferences.dashboard.standby_enabled = true
  first._job = nil
  first:refresh(0, nil)
  local firstModule = first._standbyModule
  check("standby entry loads and owns display module", standbyLoads == 1
    and firstModule ~= nil and _G.rfsuite.modules[standbyPath] == firstModule
    and firstModule.consumerCount() == 1)
  check("standby entry holds the shared ELRS provider", first._standbyElrsConfig == sharedConfig)

  first.preferences.dashboard.standby_enabled = false
  first._job = nil
  first:refresh(0, nil)
  check("disabled exit evicts last standby display module", first._standbyModule == nil
    and first._standbyCache == nil and first._standbyElrsConfig == nil and first._standbyCrsf == nil
    and firstModule._testCache == nil and _G.rfsuite.modules[standbyPath] == nil)
  check("standby exit retains shared ELRS provider", _G.rfsuite.modules[configPath] == sharedConfig)

  first.preferences.dashboard.standby_enabled = true
  first._job = nil
  first:refresh(0, nil)
  local reloadedModule = first._standbyModule
  check("standby re-entry reloads a fresh display module", standbyLoads == 2
    and reloadedModule ~= nil and reloadedModule ~= firstModule)

  local second = newWidget(true)
  second:refresh(0, nil)
  check("two widgets share one loaded standby display module", standbyLoads == 2
    and second._standbyModule == reloadedModule and reloadedModule.consumerCount() == 2)
  first:background()
  check("first widget exit retains module for second widget", first._standbyModule == nil
    and first._standbyCache == nil and first._standbyElrsConfig == nil
    and second._standbyModule == reloadedModule and _G.rfsuite.modules[standbyPath] == reloadedModule
    and reloadedModule.consumerCount() == 1 and reloadedModule._testCache == nil)
  second:background()
  check("last widget exit evicts shared standby display module", second._standbyModule == nil
    and _G.rfsuite.modules[standbyPath] == nil and reloadedModule.consumerCount() == 0)
  check("two-widget exit still retains shared ELRS provider", _G.rfsuite.modules[configPath] == sharedConfig)

  first._foreground = true
  first._job = nil
  first:refresh(0, nil)
  check("backgrounded widget re-entry reloads display module", standbyLoads == 3
    and first._standbyModule ~= nil)
  first._toolHost = { phase = "run", home = { run = function() return 0 end }, cpuHits = 0 }
  first:refresh(0, nil)
  check("hosted tool exit evicts standby display module", first._standbyModule == nil
    and first._standbyElrsConfig == nil and _G.rfsuite.modules[standbyPath] == nil
    and first._treeKind ~= "standby")

  MspRuntime.getState = originalMspState
  _G.loadScript = originalLoadScript
end

Stubs.releaseCard()
print(string.format("dashboard_standby_integration_test: %d checks passed", passed))
