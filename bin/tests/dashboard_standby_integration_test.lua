local source = string.sub(debug.getinfo(1, "S").source, 2)
local root = string.match(source, "^(.*)[/\\]bin[/\\]tests[/\\]") or "."
local runtimePath = root .. "/src/rfsuite/widgets/dashboard/runtime.lua"
local standbyPath = root .. "/src/rfsuite/widgets/dashboard/standby.lua"
if arg then
  for i = 1, #arg - 1 do
    if arg[i] == "--runtime" then runtimePath = arg[i + 1] end
    if arg[i] == "--standby" then standbyPath = arg[i + 1] end
  end
end
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
  local writes, reports, saveSucceeds = 0, {}, true
  local ctx = {
    preferences = { dashboard = { standby_enabled = false, standby_layout = "clock:small,model:full" } },
    i18n = {}, children = {}, x = 0, y = 0, w = 600,
    requestRebuild = function() end,
    reportSave = function(report) reports[#reports + 1] = report end,
    savePreferences = function() writes = writes + 1; return saveSucceeds, saveSucceeds and nil or "control" end,
  }
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "button" and node.text == "Move down" then node.press(); break end
  end
  Page.onSave(ctx)
  check("valid edited layout saves while standby remains off", writes == 1
    and ctx.preferences.dashboard.standby_enabled == false
    and ctx.preferences.dashboard.standby_layout == "model:full,clock:small")

  ctx.preferences.dashboard.standby_layout = "clock:small,model:full"
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for removed = 1, 2 do
    for i = 1, #ctx.children do
      local node = ctx.children[i]
      if node.type == "button" and node.text == "Remove" then node.press(); break end
    end
    ctx.children = {}
    Page.build(ctx)
  end
  Page.onSave(ctx)
  check("disabled invalid draft saves the off state", writes == 2
    and ctx.preferences.dashboard.standby_enabled == false)
  check("disabled invalid draft preserves the prior saved layout",
    ctx.preferences.dashboard.standby_layout == "clock:small,model:full")
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "toggle" then node.set(true); break end
  end
  Page.onSave(ctx)
  check("enabled invalid draft refuses the preference writer", writes == 2)
  check("enabled invalid draft preserves the prior saved layout",
    ctx.preferences.dashboard.standby_layout == "clock:small,model:full")

  ctx.preferences.dashboard.standby_enabled = false
  ctx.preferences.dashboard.standby_layout = "clock:small,model:full"
  Page.onReload(ctx)
  saveSucceeds = false
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "toggle" then node.set(true); break end
  end
  Page.onSave(ctx)
  check("failed save calls writer once for this attempt", writes == 3)
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

  ctx.preferences.dashboard.standby_layout = "-"
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "choice" and node.title == "Position 1" then
      for option = 1, #node.values do
        if node.values[option] == "ELRS TX configuration" then node.set(option); break end
      end
      break
    end
  end
  ctx.children = {}
  Page.build(ctx)
  local elrsSize
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "choice" and node.title == "Size" then elrsSize = node.get(); break end
  end
  check("selecting ELRS chooses a supported wide size", elrsSize == 2)
  Page.onSave(ctx)
  check("fresh ELRS selection saves without an invalid intermediate size",
    ctx.preferences.dashboard.standby_layout == "elrs:wide")

  ctx.preferences.dashboard.standby_layout = "-"
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "choice" and node.title == "Position 1" then node.set(2); break end
  end
  ctx.children = {}
  Page.build(ctx)
  local ordinarySize
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "choice" and node.title == "Size" then ordinarySize = node.get(); break end
  end
  check("ordinary new item keeps the supported small size", ordinarySize == 1)
  Page.onSave(ctx)
  check("ordinary new item saves at small size", ctx.preferences.dashboard.standby_layout == "clock:small")

  local savedLcdW, savedLcdH = LCD_W, LCD_H
  local savedSizeText = lcd.sizeText
  LCD_W, LCD_H = 480, 320
  lcd.sizeText = function(text, font)
    return #tostring(text) * (font == MIDSIZE and 12 or 8), font == MIDSIZE and 24 or 18
  end
  ctx.preferences.dashboard.standby_layout = "tx_gps:small"
  Page.onReload(ctx)
  local function choose(position, label)
    ctx.children = {}
    Page.build(ctx)
    for i = 1, #ctx.children do
      local node = ctx.children[i]
      if node.type == "choice" and node.title == "Position " .. position then
        for option = 1, #node.values do
          if node.values[option] == label then node.set(option); return true end
        end
      end
    end
    return false
  end
  check("ordinary clock can be added after saved GPS", choose(2, "Clock"))
  check("ordinary battery can be added after GPS and clock", choose(3, "TX battery"))
  Page.onSave(ctx)
  check("GPS clock battery layout saves on 480x320 with conservative font heights",
    ctx.preferences.dashboard.standby_layout == "tx_gps:small,clock:small,tx_battery:small")

  local writesBeforeOverflow = writes
  ctx.preferences.dashboard.standby_layout = "clock:full,date:full,tx_battery:full,model:full"
  Page.onReload(ctx)
  Page.onSave(ctx)
  check("genuine 480x320 overcapacity still refuses the writer", writes == writesBeforeOverflow)
  check("genuine overcapacity remains the active unsaved draft",
    ctx.preferences.dashboard.standby_layout == "clock:full,date:full,tx_battery:full,model:full")

  -- The page must map the validator's compact selected-item index back to the visible slot.
  -- Leave slot 2 empty, then make ELRS in slot 3 invalid at Small: selected index 2 is slot 3.
  local de = assert(loadfile(root .. "/src/rfsuite/i18n/de.lua"))()
  local function translated(key)
    local value = de
    for part in string.gmatch(key, "[^.]+") do
      value = type(value) == "table" and value[part] or nil
      if value == nil then return key end
    end
    return value
  end
  ctx.i18n = { t = translated }
  local pageText = de.app.pages.settings_dashboard_standby
  ctx.preferences.dashboard.standby_layout = "clock:full,tx_battery:full,model:full"
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  local expectedHeightFit = string.format(pageText.fit_item_height, 3, pageText.module_model)
  local heightWarning
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "label" and node.text == expectedHeightFit then heightWarning = i; break end
  end
  check("third full row identifies selected item 3 as the height overflow", heightWarning ~= nil)
  local writesBeforeHeightSave, reportsBeforeHeightSave = writes, #reports
  Page.onSave(ctx)
  check("height-overflow save refuses the writer", writes == writesBeforeHeightSave)
  check("height-overflow save message equals its inline warning",
    #reports == reportsBeforeHeightSave + 1 and reports[#reports].message == expectedHeightFit)

  ctx.preferences.dashboard.standby_layout = "clock:small"
  Page.onReload(ctx)
  ctx.children = {}
  Page.build(ctx)
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "choice" and node.title == string.format(pageText.position, 3) then
      for option = 1, #node.values do
        if node.values[option] == pageText.module_elrs then node.set(option); break end
      end
      break
    end
  end
  ctx.children = {}
  Page.build(ctx)
  local sizeSeen = 0
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "choice" and node.title == pageText.size then
      sizeSeen = sizeSeen + 1
      if sizeSeen == 2 then node.set(1); break end
    end
  end
  ctx.children = {}
  Page.build(ctx)
  local expectedFit = string.format(pageText.fit_item_size, 3, pageText.module_elrs)
  local sizeIndex, warningIndex, nextPositionIndex
  sizeSeen = 0
  for i = 1, #ctx.children do
    local node = ctx.children[i]
    if node.type == "choice" and node.title == pageText.size then
      sizeSeen = sizeSeen + 1
      if sizeSeen == 2 then sizeIndex = i end
    elseif node.type == "label" and node.text == expectedFit then
      warningIndex = i
      check("offending slot warning uses warning color and small font",
        node.color == COLOR_THEME_WARNING and node.font == SMLSIZE)
    elseif node.type == "choice" and node.title == string.format(pageText.position, 4) then
      nextPositionIndex = i
    end
  end
  check("selected-item index maps to visible slot 3 with localized tile name", warningIndex ~= nil)
  check("inline warning follows offending size and precedes the next position",
    sizeIndex ~= nil and warningIndex > sizeIndex and nextPositionIndex ~= nil and warningIndex < nextPositionIndex)
  local writesBeforeInlineSave, reportsBeforeInlineSave = writes, #reports
  Page.onSave(ctx)
  check("inline-invalid save refuses the writer", writes == writesBeforeInlineSave)
  check("save refusal exactly matches the inline warning",
    #reports == reportsBeforeInlineSave + 1 and reports[#reports].message == expectedFit)
  ctx.i18n = {}
  lcd.sizeText = savedSizeText
  LCD_W, LCD_H = savedLcdW, savedLcdH
  Page.onClose()
end

-- Timer detail captions use the same item-specific keys populated by the runtime. A generic
-- fallback would make every translated timer caption silently display English.
do
  local Standby = assert(loadfile(standbyPath))()
  local savedSizeText = lcd.sizeText
  lcd.sizeText = function(text, font)
    return #tostring(text) * (font == MIDSIZE and 9 or 6), font == MIDSIZE and 17 or 12
  end
  check("default layout fits native TX15 English font heights",
    Standby.validate(Standby.decode(nil), 480, 320))
  lcd.sizeText = savedSizeText
  local cache = {}
  local labels = { timer1_detail = "Localized timer one" }
  local tree = Standby.build({ x = 0, y = 0, w = 800, h = 480 }, "waiting",
    function(key, fallback) return labels[key] or fallback end,
    Standby.decode("timer1:small"), { timer1 = "00:42" }, cache, { text = "info", level = "info" })
  local localized = false
  for i = 1, #tree do
    local node = tree[i]
    if node.type == "label" and node.text == "Localized timer one" then localized = true; break end
  end
  check("timer tile uses its item-specific localized detail key", localized)

  local compactItems = Standby.decode(nil)
  local compactCache = {}
  local compactTree = Standby.build({ x = 0, y = 0, w = 480, h = 320 }, "waiting",
    function(_, fallback) return fallback end, compactItems, {}, compactCache,
    { text = "info", level = "info" })
  local Controls = assert(_G.rfsuite.require("widgets/dashboard/fullscreen_controls.lua"))
  Controls.appendTool(compactTree, { zone = { x = 0, y = 0, w = 480, h = 320 }, state = { armed = false } })
  local toolBottom, firstTileY
  for i = 1, #compactTree do
    local node = compactTree[i]
    if node.type == "button" and node.x == 459 and node.y == 1 and node.w == 20 and node.h == 20 then
      toolBottom = node.y + node.h
    elseif node.type == "rectangle" and node.rounded == 5 then
      firstTileY = firstTileY and math.min(firstTileY, node.y) or node.y
    end
  end
  check("compact Suite control stays above the first standby tile",
    toolBottom == 21 and firstTileY ~= nil and toolBottom < firstTileY)

  for _, size in ipairs({ { 240, 68 }, { 480, 45 } }) do
    local fitText = "Localized layout fit message"
    local tinyTree = Standby.build({ x = 0, y = 0, w = size[1], h = size[2] }, "waiting",
      function(key, fallback) if key == "layout_invalid" then return fitText end; return fallback end,
      Standby.decode(nil), {}, {}, { text = "info", level = "info" })
    local bounded, foundFit = #tinyTree == 2, false
    for i = 1, #tinyTree do
      local node = tinyTree[i]
      if node.type == "label" and node.text == fitText then foundFit = true end
      if type(node.x) == "number" and type(node.y) == "number" then
        bounded = bounded and node.x >= 0 and node.y >= 0
          and (type(node.w) ~= "number" or node.x + node.w <= size[1])
          and (type(node.h) ~= "number" or node.y + node.h <= size[2])
      end
    end
    check("minimum standard EdgeTX zone uses bounded localized fit surface "
        .. size[1] .. "x" .. size[2], bounded and foundFit)
  end
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
  local originalMspProgress = MspRuntime.getProgressValues
  local forceRawConnected, forceUnsupported = false, false
  MspRuntime.getState = function()
    if forceUnsupported then
      return { lastConnected = true, versionReadCompleted = true, unsupportedApi = true, refusedApiVersion = "9.9" }
    end
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

  local treesBeforeEntry = #Stubs.lvgl.trees
  Stubs.tick()
  widget:refresh(0, nil)
  local afterState = calls.request
  check("eligible fullscreen drives standby provider", afterState > 0 and calls.step > 0)
  check("missing controller selects the general prerequisite summary",
    widget.state.standbyInfoKind == "controller_missing")
  widget:refresh(0, nil)
  check("standby build pass does not probe provider", calls.request == afterState)
  check("standby entry builds one scene", #Stubs.lvgl.trees == treesBeforeEntry + 1)
  widget:refresh(0, nil)
  check("standby entry does not enqueue a nil-to-false overflow rebuild",
    #Stubs.lvgl.trees == treesBeforeEntry + 1 and widget._job == nil)
  local standbyTree = Stubs.lvgl.trees[#Stubs.lvgl.trees] or {}
  local suiteButton, suiteGlyphLines = nil, 0
  for i = 1, #standbyTree do
    local node = standbyTree[i]
    if node.type == "button" and node.x == 748 and node.y == 8 and node.w == 44 and node.h == 44 then
      suiteButton = node
    elseif node.type == "line" and node.color == WHITE then
      suiteGlyphLines = suiteGlyphLines + 1
    end
  end
  check("standby uses the existing fullscreen Suite launch control",
    suiteButton and suiteButton.color == COLOR_THEME_PRIMARY1
      and type(suiteButton.press) == "function" and suiteGlyphLines == 6)

  -- A visible zone receives the same waiting surface at its own dimensions, without the
  -- fullscreen-only Suite control. Hidden/background and disabled widgets must not sample GPS.
  local savedGetTxGPS, gpsReads = getTxGPS, 0
  getTxGPS = function()
    gpsReads = gpsReads + 1
    return { fix = true, numsat = 8, lat = 48.12345, lon = 11.54321,
      alt = 6123, speed = 45, heading = 1274, hdop = 123 }
  end
  local deLocale = assert(loadfile(root .. "/src/rfsuite/i18n/de.lua"))()
  local function deText(key, fallback)
    local value = deLocale
    for part in string.gmatch(key, "[^.]+") do
      value = type(value) == "table" and value[part] or nil
      if value == nil then return fallback end
    end
    return value
  end
  local gpsText = deLocale.widgets.dashboard.standby
  local function firstGpsSnapshot(name, layout)
    local before = gpsReads
    local gpsWidget = Runtime.new({ x = 0, y = 0, w = 480, h = 320 }, {})
    gpsWidget.i18n = { t = deText }
    gpsWidget.preferences.dashboard = gpsWidget.preferences.dashboard or {}
    gpsWidget.preferences.dashboard.standby_enabled = true
    gpsWidget.preferences.dashboard.standby_layout = layout
    gpsWidget.preferences.audio_events = gpsWidget.preferences.audio_events or {}
    gpsWidget.preferences.audio_events.tpwr_alert = false
    gpsWidget.state.fblConnected, gpsWidget.state.armed = false, false
    gpsWidget.state.hadInflightFlight, gpsWidget.flightMode = false, "preflight"
    Stubs.tick(); gpsWidget:refresh(nil, nil)
    local firstGps = gpsWidget._standbyCache and gpsWidget._standbyCache.snapshotValues
    check(name, gpsReads == before + 1 and firstGps
      and firstGps._gpsTime == gpsText.gps_time_unavailable
      and firstGps._gpsLines[1] == gpsText.gps_latitude .. ": 48.12345°"
      and firstGps._gpsLines[6] == gpsText.gps_hdop .. ": 1.23")
    gpsWidget:background()
  end
  firstGpsSnapshot("first large GPS snapshot is localized before its build pass", "tx_gps:full")
  firstGpsSnapshot("large then small duplicate keeps first-frame GPS detail localization",
    "tx_gps:wide,tx_gps:small")
  firstGpsSnapshot("small then large duplicate keeps first-frame GPS detail localization",
    "tx_gps:small,tx_gps:wide")
  local gpsReadsBeforeZone = gpsReads
  local zoneWidget = Runtime.new({ x = 4, y = 6, w = 300, h = 180 }, {})
  zoneWidget.preferences.dashboard = zoneWidget.preferences.dashboard or {}
  zoneWidget.preferences.dashboard.standby_enabled = true
  zoneWidget.preferences.dashboard.standby_layout = "clock:small"
  zoneWidget.preferences.audio_events = zoneWidget.preferences.audio_events or {}
  zoneWidget.preferences.audio_events.tpwr_alert = false
  zoneWidget.state.fblConnected, zoneWidget.state.armed = false, false
  zoneWidget.state.hadInflightFlight, zoneWidget.flightMode = false, "preflight"
  local zoneTreesBefore, previousTree, requestsBeforeZone = #Stubs.lvgl.trees, Stubs.lvgl.trees[1], calls.request
  Stubs.tick(); zoneWidget:refresh(nil, nil)
  zoneWidget:refresh(nil, nil)
  local zoneTree = Stubs.lvgl.trees[#Stubs.lvgl.trees] or {}
  local zoneHasTool, zoneContained, zoneNode, zoneOverflow = false, true, false, nil
  for i = 1, #zoneTree do
    local node = zoneTree[i]
    if node.type == "button" and type(node.press) == "function" then zoneHasTool = true; break end
    if type(node.x) == "number" and type(node.y) == "number" then
      zoneNode = true
      if node.x < 0 or node.y < 0
          or (type(node.w) == "number" and node.x + node.w > 300)
          or (type(node.h) == "number" and node.y + node.h > 180) then
        zoneContained = false
        zoneOverflow = tostring(node.type) .. "@" .. tostring(node.x) .. "," .. tostring(node.y)
          .. "+" .. tostring(node.w) .. "x" .. tostring(node.h)
      end
    end
  end
  check("normal widget builds standby at the actual zone without Suite control trees="
      .. tostring(zoneTreesBefore) .. "->" .. tostring(#Stubs.lvgl.trees)
      .. " kind=" .. tostring(zoneWidget._treeKind)
      .. " fs=" .. tostring(zoneWidget._standbyFullscreen)
      .. " tool=" .. tostring(zoneHasTool)
      .. " changed=" .. tostring(zoneTree ~= previousTree)
      .. " node=" .. tostring(zoneNode) .. " contained=" .. tostring(zoneContained)
      .. " overflow=" .. tostring(zoneOverflow),
    zoneTreesBefore == 1 and #Stubs.lvgl.trees == 1 and zoneTree ~= previousTree
      and zoneNode and zoneContained and zoneWidget._treeKind == "standby"
      and zoneWidget._standbyFullscreen == false and not zoneHasTool)
  check("normal non-ELRS standby does not touch the shared ELRS reader",
    calls.request == requestsBeforeZone)
  check("unselected GPS is not sampled in normal standby", gpsReads == gpsReadsBeforeZone)
  zoneWidget.zone = { x = 0, y = 0, w = 480, h = 320 }
  Stubs.tick(); zoneWidget:refresh(0, nil)
  zoneWidget:refresh(0, nil)
  local fullscreenTree = Stubs.lvgl.trees[1] or {}
  local fullscreenHasTool = false
  for i = 1, #fullscreenTree do
    if fullscreenTree[i].type == "button" and type(fullscreenTree[i].press) == "function" then
      fullscreenHasTool = true; break
    end
  end
  check("normal-to-fullscreen transition rebuilds with Suite control",
    zoneWidget._treeKind == "standby" and zoneWidget._standbyFullscreen == true and fullscreenHasTool)
  zoneWidget.zone = { x = 4, y = 6, w = 300, h = 180 }
  Stubs.tick(); zoneWidget:refresh(nil, nil)
  zoneWidget:refresh(nil, nil)
  local returnedZoneTree = Stubs.lvgl.trees[1] or {}
  local returnedZoneHasTool = false
  for i = 1, #returnedZoneTree do
    if returnedZoneTree[i].type == "button" and type(returnedZoneTree[i].press) == "function" then
      returnedZoneHasTool = true; break
    end
  end
  check("fullscreen-to-normal transition rebuilds without Suite control",
    zoneWidget._treeKind == "standby" and zoneWidget._standbyFullscreen == false
      and not returnedZoneHasTool)
  zoneWidget:background()
  check("background releases normal standby display state",
    zoneWidget._standbyModule == nil and zoneWidget._standbyCache == nil
      and zoneWidget._standbyFullscreen == nil)
  zoneWidget.preferences.dashboard.standby_enabled = false
  Stubs.tick(); zoneWidget:refresh(nil, nil)
  check("disabled normal widget does not sample GPS", gpsReads == gpsReadsBeforeZone)
  getTxGPS = savedGetTxGPS

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
  MspRuntime.getProgressValues = function() return 0, 1 end
  local beforeRawRequest, beforeRawStep = calls.request, calls.step
  Stubs.tick()
  widget:refresh(0, nil)
  check("raw MSP link yields probing but keeps standby render and refreshes cancelled status",
    calls.request == beforeRawRequest and calls.step == beforeRawStep
      and widget._standbyActive ~= true and widget._standbyCache.elrs.status ~= "reading"
      and ((widget._job and widget._job.kind == "standby")
        or (type(widget.renderKey) == "string" and string.sub(widget.renderKey, 1, 8) == "standby|")))
  widget._job = nil
  Stubs.tick()
  widget:refresh(0, nil)
  check("raw MSP startup takes priority over missing-controller summary: "
      .. tostring(widget.state.standbyInfoKind),
    widget.state.standbyInfoKind == "suite_loading")
  check("summary transition invalidates cached localized prerequisite",
    widget._standbyTexts == nil)
  MspRuntime.getProgressValues = originalMspProgress
  forceRawConnected = false

  forceUnsupported = true
  widget._job = nil
  Stubs.tick()
  widget:refresh(0, nil)
  check("unsupported API has the highest compatibility summary priority",
    widget.state.standbyInfoKind == "api_unsupported")
  forceUnsupported = false

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

  -- Once the normal dashboard is already up, a standby-only prerequisite change must not enqueue
  -- another scene build. Cover both the default-off case and an enabled feature excluded by flight
  -- history; the active-standby transition above separately proves its text cache is invalidated.
  local originalIsFblConnected = MspRuntime.isFblConnected
  local EventsRuntime = assert(_G.rfsuite.require("tasks/events/runtime.lua"))
  local originalEventActive = EventsRuntime.isOnconnectActive
  local originalEventProgress = EventsRuntime.getOnconnectProgress
  local originalEventPending = EventsRuntime.getOnconnectPendingTaskName
  local savedResolved = _G.rfsuite.session and _G.rfsuite.session.modelPreferencesResolved
  MspRuntime.getState = function()
    return { lastConnected = true, versionReadCompleted = true, unsupportedApi = false,
      values = { apiVersion = "12.0" } }
  end
  MspRuntime.getProgressValues = function() return 1, 1 end
  MspRuntime.isFblConnected = function() return true end
  EventsRuntime.isOnconnectActive = function() return false end
  EventsRuntime.getOnconnectProgress = function() return { done = 1, total = 1 } end
  EventsRuntime.getOnconnectPendingTaskName = function() return nil end
  if _G.rfsuite.session then _G.rfsuite.session.modelPreferencesResolved = true end
  local function readyWidget(enabled, flown)
    local readyWidget = Runtime.new({ x = 0, y = 0, w = 800, h = 480 }, {})
    readyWidget.preferences.dashboard = readyWidget.preferences.dashboard or {}
    readyWidget.preferences.dashboard.standby_enabled = enabled
    readyWidget.preferences.audio_events = readyWidget.preferences.audio_events or {}
    readyWidget.preferences.audio_events.tpwr_alert = false
    readyWidget.state.batteryTelemetrySeen = true
    readyWidget.state.rfTelemetrySeen = true
    readyWidget.pendingSince = -1000
    for _ = 1, 8 do Stubs.tick(); readyWidget:refresh(0, nil) end
    if flown then
      readyWidget.state.hadInflightFlight = true
      for _ = 1, 3 do Stubs.tick(); readyWidget:refresh(0, nil) end
    end
    return readyWidget
  end
  local function infoChangeDoesNotBuild(name, readyWidget)
    for _ = 1, 3 do readyWidget:refresh(0, nil) end
    local treesBefore = #Stubs.lvgl.trees
    local keyBefore, builtBefore = readyWidget.renderKey, readyWidget.built
    local textsBefore = { marker = name }
    readyWidget._standbyTexts = textsBefore
    readyWidget.state.standbyInfoKind = "stale-standby-only-value"
    readyWidget._lastWorkTick = nil
    readyWidget._lastLogicTick = -1000
    Stubs.tick()
    readyWidget:refresh(0, nil)
    local statePassStable = readyWidget.renderKey == keyBefore and readyWidget.built == builtBefore
      and readyWidget._job == nil
    readyWidget:refresh(0, nil)
    check(name .. " module=" .. tostring(readyWidget._standbyModule)
      .. " trees=" .. tostring(treesBefore) .. "->" .. tostring(#Stubs.lvgl.trees)
      .. " ready=" .. tostring(readyWidget.connectionReady)
      .. " info=" .. tostring(readyWidget.state.standbyInfoKind)
      .. " status=" .. tostring(readyWidget.statusLine),
      readyWidget.connectionReady == true and builtBefore == true
        and readyWidget.state.standbyInfoKind ~= "stale-standby-only-value"
        and readyWidget._standbyModule == nil and readyWidget._standbyTexts == textsBefore
        and statePassStable and #Stubs.lvgl.trees == treesBefore)
  end
  infoChangeDoesNotBuild("feature-off prerequisite change does not rebuild ready dashboard",
    readyWidget(false, false))
  infoChangeDoesNotBuild("flight-excluded prerequisite change does not rebuild ready dashboard",
    readyWidget(true, true))
  MspRuntime.isFblConnected = originalIsFblConnected
  EventsRuntime.isOnconnectActive = originalEventActive
  EventsRuntime.getOnconnectProgress = originalEventProgress
  EventsRuntime.getOnconnectPendingTaskName = originalEventPending
  if _G.rfsuite.session then _G.rfsuite.session.modelPreferencesResolved = savedResolved end

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

  local releasedCache = first._standbyCache
  first.preferences.dashboard.standby_enabled = false
  first._job = nil
  first:refresh(0, nil)
  check("disabled exit evicts last standby display module", first._standbyModule == nil
    and first._standbyCache == nil and first._standbyElrsConfig == nil and first._standbyCrsf == nil
    and _G.rfsuite.modules[standbyPath] == nil)
  check("standby exit retains shared ELRS provider", _G.rfsuite.modules[configPath] == sharedConfig)

  first.preferences.dashboard.standby_enabled = true
  first._job = nil
  first:refresh(0, nil)
  local reloadedModule = first._standbyModule
  check("standby re-entry reloads a fresh display module", standbyLoads == 2
    and reloadedModule ~= nil and reloadedModule ~= firstModule
    and first._standbyCache ~= nil and first._standbyCache ~= releasedCache)

  local second = newWidget(true)
  second:refresh(0, nil)
  check("two widgets share one loaded standby display module", standbyLoads == 2
    and second._standbyModule == reloadedModule and reloadedModule.consumerCount() == 2)
  first:background()
  check("first widget exit retains module for second widget", first._standbyModule == nil
    and first._standbyCache == nil and first._standbyElrsConfig == nil
    and second._standbyModule == reloadedModule and _G.rfsuite.modules[standbyPath] == reloadedModule
    and reloadedModule.consumerCount() == 1)
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
