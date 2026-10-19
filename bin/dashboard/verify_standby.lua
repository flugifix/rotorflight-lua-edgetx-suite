MIDSIZE, SMLSIZE = 2, 1
LCD_W, LCD_H = 480, 320
lcd = { sizeText = function(text, font) return #text * (font == MIDSIZE and 10 or 7), font == MIDSIZE and 22 or 16 end }

local batterySample = { volts = nil, pct = nil, low = false }
rfsuite = { require = function(path)
  if path == "lib/radio_status.lua" then
    return { txBattery = function() return batterySample.volts, batterySample.pct, batterySample.low end }
  end
end }

local standby = assert(loadfile("src/rfsuite/widgets/dashboard/standby.lua"))()
local passed = 0
local function check(name, condition)
  if not condition then error("standby regression failed: " .. name, 0) end
  passed = passed + 1
end

local default = standby.decode(nil)
check("default has three items", #default == 3)
check("default fits 480x320", standby.validate(default, 480, 320))
check("default fits 800x480", standby.validate(default, 800, 480))
local fixtureSizeText = lcd.sizeText
lcd.sizeText = function(text, font)
  return #text * (font == MIDSIZE and 8 or 6), font == MIDSIZE and 17 or 12
end
check("default three tiles fit native TX15 font heights", standby.validate(default, 480, 320))
check("single small GPS fits a 240x91 widget zone",
  standby.validate(standby.decode("tx_gps:small"), 240, 91))
check("configured tiles reject a 240x68 widget zone", not standby.validate(default, 240, 68))
check("configured tiles reject a 480x45 widget zone", not standby.validate(default, 480, 45))
check("narrow dashboard zone uses one readable column", standby.validate(default, 320, 400))
lcd.sizeText = function(text, font)
  return #text * (font == MIDSIZE and 10 or 7), font == MIDSIZE and 24 or 18
end
check("default three tiles fit TX15 font heights", standby.validate(default, 480, 320))
check("default three tiles fit short dashboard zone", standby.validate(default, 480, 272))
local compactElrs = standby.decode("elrs:wide,clock:small,tx_battery:small")
check("ELRS wide and two small tiles fit TX15 font heights", standby.validate(compactElrs, 480, 320))
local compactOverflow = standby.decode("clock:full,tx_battery:full,model:full")
local overflowValid, overflowReason, _, overflowIndex = standby.validate(compactOverflow, 480, 320)
check("three full compact rows still reject", not overflowValid and overflowReason == "fit" and overflowIndex == 3)
local _, compactWidthReason, _, compactWidthIndex = standby.validate(default, 480, 320,
  { clock = string.rep("W", 100), tx_battery = "TX", model = "Model" })
check("compact width error identifies its item", compactWidthReason == "width" and compactWidthIndex == 1)
local _, compactSizeReason, _, compactSizeIndex = standby.validate({ { type = "elrs", size = "small" } }, 480, 320)
check("compact size error identifies its item", compactSizeReason == "size" and compactSizeIndex == 1)
local tinyValid, tinyReason, _, tinyIndex = standby.validate(default, 180, 150)
check("impossibly small zone rejects the whole layout", not tinyValid and tinyReason == "fit" and tinyIndex == 1)
lcd.sizeText = fixtureSizeText
local de = assert(loadfile("src/rfsuite/i18n/de.lua"))()
local deStandby = de.widgets.dashboard.standby
local function fitLabels(locale)
  local keys = {
    clock = "module_clock", date = "module_date", tx_battery = "module_tx_battery",
    model = "module_model", timer1 = "module_timer1", timer2 = "module_timer2",
    timer3 = "module_timer3", tx_gps = "module_tx_gps", uptime = "module_uptime",
    firmware = "module_firmware", elrs = "module_elrs",
  }
  local labels = {}
  for id, key in pairs(keys) do labels[id] = assert(locale[key], "missing runtime label " .. key) end
  for _, key in ipairs({ "elrs_last_read", "elrs_packet_rate", "elrs_telemetry_ratio", "elrs_max_power", "elrs_dynamic" }) do
    labels[key] = assert(locale[key], "missing runtime label " .. key)
  end
  return labels
end
local deFitLabels = fitLabels(deStandby)
check("German fit fixture maps runtime tile ids", deFitLabels.clock == deStandby.module_clock
  and deFitLabels.tx_battery == deStandby.module_tx_battery
  and deFitLabels.model == deStandby.module_model)
check("German default fits 480x320", standby.validate(default, 480, 320, deFitLabels))
check("German default fits 800x480", standby.validate(default, 800, 480, deFitLabels))

local empty, emptyErr = standby.decode("-")
check("empty is preserved", #empty == 0 and emptyErr == nil)
check("empty is invalid", not standby.validate(empty, 480, 320))
check("empty round trips", standby.encode(empty) == "-")

local malformed, malformedErr = standby.decode("clock")
check("malformed rejected", #malformed == 0 and malformedErr == "unknown")
local unknown, unknownErr = standby.decode("clock:small,secret:wide")
check("unknown rejected without prefix", #unknown == 0 and unknownErr == "unknown")
local tooMany, countErr = standby.decode("clock:small,date:small,tx_battery:small,model:small,timer1:small,timer2:small,timer3:small,tx_gps:small,uptime:small")
check("count bound rejects whole layout", #tooMany == 0 and countErr == "count")
local badSize, sizeErr = standby.decode("elrs:small")
check("ELRS small rejected", #badSize == 0 and sizeErr == "size")
local elrsFull = standby.decode("elrs:full")
local elrsLabels = {
  elrs = "ELRS TX configuration", elrs_last_read = "Last read %d s ago", elrs_packet_rate = "Packet Rate",
  elrs_telemetry_ratio = "Telemetry Ratio", elrs_max_power = "Max Power", elrs_dynamic = "Dynamic",
}
check("ELRS composite fits supported full row", standby.validate(elrsFull, 480, 320, elrsLabels))
check("ELRS composite fits supported large row", standby.validate(elrsFull, 800, 480, elrsLabels))
check("German ELRS composite fits 480x320", standby.validate(elrsFull, 480, 320, deFitLabels))
check("German ELRS composite fits 800x480", standby.validate(elrsFull, 800, 480, deFitLabels))
for _, malformedValue in ipairs({ ",clock:small", "clock:small,", "clock:small,,date:wide" }) do
  local malformedList, grammarErr = standby.decode(malformedValue)
  check("comma grammar rejected " .. malformedValue, #malformedList == 0 and grammarErr == "malformed")
end

local overflow = standby.decode("clock:full,date:full,tx_battery:full,model:full")
check("480x320 overflow rejected", not standby.validate(overflow, 480, 320))
local longLabels = { clock = string.rep("W", 100), tx_battery = "TX", model = "Model" }
check("localized label width checked", not standby.validate(default, 480, 320, longLabels))

local tick = 100
getTime = function() return tick end
getDateTime = function() return { year = 2026, mon = 10, day = 19, hour = 12, min = 34 } end
getVersion = function() return "2.12.0", "tx16s-simu" end
local gpsCalls = 0
getTxGPS = function()
  gpsCalls = gpsCalls + 1
  return { fix = true, numsat = 7, lat = 52.12345, lon = 13.54321,
    alt = 1234, speed = 56, heading = 2712, hdop = 85 }
end
model = {
  getInfo = function() return { name = string.rep("W", 30) } end,
  getTimer = function(index) return { value = index == 0 and 999999 or 0 } end,
}
local cache = { text = function(_, fallback) return fallback end }
local values, key = standby.snapshot(default, cache)
check("snapshot reads transmitter battery safely", type(values) == "table" and values.tx_battery == "-")
check("default snapshot skips unselected firmware and timers",
  values.firmware == nil and values.timer1 == nil and values.timer2 == nil and values.timer3 == nil)
check("default snapshot skips unselected GPS getter", gpsCalls == 0 and values.tx_gps == nil)
check("clock snapshot retains its date detail", values.date == "2026-10-19")
check("model display is bounded", #values.model == 15)
tick = 101
local selectedSourceValues = standby.snapshot(standby.decode("firmware:wide,timer1:wide"), { text = cache.text })
check("selected snapshot uses firmware version", selectedSourceValues.firmware == "2.12.0")
check("selected timer overflow remains explicit", selectedSourceValues.timer1 == ">999:59")
model.getInfo = function() return { name = "Model\195\169LongEnough" } end
tick = 201
local utf8Values = standby.snapshot(default, cache)
check("UTF-8 model truncates at a codepoint", utf8Values.model == "Model\195\169LongEn...")
check("unselected GPS remains skipped after snapshot cadence", gpsCalls == 0)

local modelOnly = standby.decode("model:full")
local modelOnlyCache = { text = cache.text }
batterySample.volts, batterySample.pct = 8.0, 50
tick = 250
local modelOnlyValues = standby.snapshot(modelOnly, modelOnlyCache)
check("unselected battery leaves no sampled value", modelOnlyValues.tx_battery == nil
  and modelOnlyCache.batteryPercent == nil)

local batteryItems = standby.decode("tx_battery:small")
local batteryCache = { text = cache.text }
batterySample.volts, batterySample.pct, batterySample.low = nil, nil, false
tick = 260
local emptyBatteryValues = standby.snapshot(batteryItems, batteryCache)
local emptyBatteryScene = standby.build({ w = 480, h = 320 }, "Waiting", cache.text,
  batteryItems, emptyBatteryValues, batteryCache)
local batterySize, batteryColor
for i = 1, #emptyBatteryScene do
  local node = emptyBatteryScene[i]
  if node.type == "hline" and type(node.size) == "function" then batterySize, batteryColor = node.size, node.color end
end
local emptyWidth = batterySize()
check("unknown battery draws an empty outline", emptyWidth == 0)
batterySample.volts, batterySample.pct, batterySample.low = 7.8, 50, false
tick = 361
standby.snapshot(batteryItems, batteryCache)
local halfWidth = batterySize()
check("battery graphic follows cached percentage", halfWidth > 0 and halfWidth < 30
  and batteryColor() == COLOR_THEME_SECONDARY1)
batterySample.volts, batterySample.pct, batterySample.low = 6.8, 100, true
tick = 462
standby.snapshot(batteryItems, batteryCache)
local fullWidth = batterySize()
check("battery graphic reaches full and uses warning color", fullWidth > halfWidth
  and batteryColor() == COLOR_THEME_WARNING)

local gpsItems = standby.decode("tx_gps:wide")
local gpsCache = { text = cache.text }
tick = 300
local gpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS reads and formats transmitter fix", gpsCalls == 1 and gpsValues.tx_gps == "Fix · 7")
check("wide GPS formats detailed cached fields", gpsValues._gpsLines
  and gpsValues._gpsLines[1] == "Latitude: 52.12345°"
  and gpsValues._gpsLines[3] == "Altitude: 123.4 m"
  and gpsValues._gpsLines[4] == "Speed: 5.6 m/s"
  and gpsValues._gpsLines[5] == "Course: 271.2°"
  and gpsValues._gpsLines[6] == "HDOP: 0.85")
local gpsBuildCache = { text = cache.text, snapshotValues = gpsValues }
local gpsScene = standby.build({ w = 480, h = 320 }, "Waiting", cache.text,
  gpsItems, gpsValues, gpsBuildCache)
local gpsDetailCount = 0
for i = 1, #gpsScene do
  local node = gpsScene[i]
  if type(node.text) == "function" then
    local text = node.text()
    if type(text) == "string" and (string.find(text, "Latitude:", 1, true)
        or string.find(text, "Longitude:", 1, true) or string.find(text, "Altitude:", 1, true)
        or string.find(text, "Speed:", 1, true) or string.find(text, "Course:", 1, true)
        or string.find(text, "HDOP:", 1, true)) then gpsDetailCount = gpsDetailCount + 1 end
  end
end
check("wide GPS scene renders six detailed fields", gpsDetailCount == 6 and gpsBuildCache.valueOverflow == false)
local gpsTimeFound = false
for i = 1, #gpsScene do
  if gpsScene[i].text == "Time status unknown" then gpsTimeFound = true end
end
check("wide GPS states the GPS time API limit", gpsTimeFound)
tick = 350
local cachedGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS snapshot respects one-second cache", gpsCalls == 1 and cachedGpsValues == gpsValues)
tick = 401
local refreshedGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS refreshes after bounded cadence", gpsCalls == 2 and refreshedGpsValues.tx_gps == "Fix · 7")
getTxGPS = function() gpsCalls = gpsCalls + 1; return { fix = false, numsat = 3 } end
tick = 502
local noFixGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS without fix still shows satellites", gpsCalls == 3
  and noFixGpsValues.tx_gps == "No fix · Sat 3" and noFixGpsValues._gpsLines == nil)
getTxGPS = function() gpsCalls = gpsCalls + 1; return { fix = nil } end
tick = 603
local unknownGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS with missing fix stays unknown", gpsCalls == 4 and unknownGpsValues.tx_gps == "-")
getTxGPS = function() gpsCalls = gpsCalls + 1; return nil end
tick = 704
local unavailableGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected unavailable GPS stays unknown", gpsCalls == 5 and unavailableGpsValues.tx_gps == "-")
getTxGPS = function()
  gpsCalls = gpsCalls + 1
  return { fix = true, numsat = 4, lat = math.huge, lon = 181, alt = 1000000,
    speed = -1, heading = 3600, hdop = 65536 }
end
tick = 805
local malformedGpsValues = standby.snapshot(gpsItems, gpsCache)
check("detailed GPS rejects non-finite and out-of-range members", gpsCalls == 6
  and malformedGpsValues._gpsLines[1] == "Latitude: -"
  and malformedGpsValues._gpsLines[6] == "HDOP: -")
tick = 906
local smallGpsValues = standby.snapshot(standby.decode("tx_gps:small"), { text = cache.text })
check("small GPS does not format unselected detail fields", gpsCalls == 7
  and smallGpsValues.tx_gps == "Fix · 4" and smallGpsValues._gpsLines == nil)
local scene = standby.build({ w = 480, h = 320 }, "Please wait...", cache.text, default, values, cache)
check("standby scene builds", type(scene) == "table" and #scene > 3)
local tinyScene = standby.build({ w = 240, h = 68 }, "Please wait...", cache.text, default, values, {})
check("tiny widget zone shows only a readable fit prerequisite", #tinyScene == 2
  and tinyScene[2].type == "label" and tinyScene[2].y >= 0 and tinyScene[2].y < 68)
local shortScene = standby.build({ w = 480, h = 275 }, "Please wait...", cache.text, default, values, {})
local shortLogo, shortDivider, shortFirstTile
for i = 1, #shortScene do
  local node = shortScene[i]
  if node.type == "image" then shortLogo = node
  elseif node.type == "rectangle" and node.h == 1 then shortDivider = node
  elseif node.type == "rectangle" and node.rounded == 5 and shortFirstTile == nil then shortFirstTile = node end
end
check("short dashboard header keeps logo above divider and tiles", shortLogo and shortDivider and shortFirstTile
  and shortLogo.y + shortLogo.h <= shortDivider.y and shortDivider.y < shortFirstTile.y)
local roundedTiles, invalidRadius = 0, false
for i = 1, #scene do
  local node = scene[i]
  if node.radius ~= nil then invalidRadius = true end
  if node.type == "rectangle" and node.rounded == 5 then roundedTiles = roundedTiles + 1 end
end
check("standby tiles use native rounded property", not invalidRadius and roundedTiles == #default)
local infoScene = standby.build({ w = 480, h = 320 }, "Exact connection reason", cache.text, default, values, cache,
  { text = "Flight controller not detected", level = "info" })
check("general information strip uses calm theme accent", infoScene[5].color == COLOR_THEME_SECONDARY1)
check("general information strip preserves exact status below", infoScene[7].text == "Exact connection reason")
local warningScene = standby.build({ w = 480, h = 320 }, "Unsupported API 9.9", cache.text, default, values, cache,
  { text = "Compatibility check failed", level = "warning" })
check("warning information uses warning marker", warningScene[5].color == COLOR_THEME_WARNING)
local utf8InfoScene = standby.build({ w = 480, h = 320 }, "Waiting", cache.text, default, values, cache,
  { text = string.rep("Pr\195\169requis", 200), level = "info" })
local fittedInfo = utf8InfoScene[6].text
local fittedPrefix = string.sub(fittedInfo, 1, -4)
local asciiPrefix = string.gsub(fittedPrefix, "\195\169", "")
check("long UTF-8 information is visibly bounded",
  string.sub(fittedInfo, -3) == "..." and not string.find(asciiPrefix, "[\128-\255]"))
local largest = standby.decode("elrs:full,clock:small,date:small,tx_battery:small,model:small,timer1:small,timer2:small,timer3:small")
check("largest eight-item layout validates at 800x480", standby.validate(largest, 800, 480, elrsLabels))
local largestCache = { text = cache.text }
local largestValues = standby.snapshot(largest, largestCache)
local largestScene = standby.build({ w = 800, h = 480 }, "Waiting", cache.text, largest, largestValues, largestCache)
local tileCount = 0
for i = 1, #largestScene do
  local node = largestScene[i]
  if node.type == "rectangle" and node.rounded == 7 then tileCount = tileCount + 1 end
end
check("largest eight-item scene renders every tile", largestCache.valueOverflow == false and tileCount == 8)
check("tile captions use the theme accent", scene[9].color == COLOR_THEME_SECONDARY1)
local compactHeaderLabels = 0
for i = 1, #scene do
  local node = scene[i]
  if node.type == "label" and node.y < 43 then compactHeaderLabels = compactHeaderLabels + 1 end
end
check("header omits duplicate battery, title, and module count", compactHeaderLabels == 0)
local largeScene = standby.build({ w = 800, h = 480 }, string.rep("W", 80), cache.text, default, values, cache)
check("status line preserves the full reason", largeScene[7].text == string.rep("W", 80))
local valueClosure = scene[10].text
check("scene exposes reactive value", type(valueClosure) == "function")
local before = valueClosure()
cache.snapshotValues.clock = "12:35"
check("reactive value updates without rebuild", valueClosure() ~= before)

local elrsCache = { text = function(_, fallback) return fallback end }
standby.setElrsSnapshot(elrsCache, {
  status = "ready", readAt = 1, identity = "one", packetRate = "D250", telemetryRatio = "Std",
  maxPower = "25/250", dynamic = "AUX9", fields = { maxPower = { unit = "mW" } },
}, 1)
tick = 300
local elrsValues = standby.snapshot(elrsFull, elrsCache)
standby.build({ w = 480, h = 320 }, "Waiting", elrsCache.text, elrsFull, elrsValues, elrsCache)
check("exact D-rate label is preserved", string.find(elrsValues.elrs, "Packet Rate: D250", 1, true) ~= nil)
check("supported ELRS labels fit", elrsCache.valueOverflow == false)
standby.setElrsSnapshot(elrsCache, {
  status = "ready", readAt = 2, identity = "one", packetRate = string.rep("LongRate", 20), telemetryRatio = "Race",
  maxPower = "1000", dynamic = "Off", fields = { maxPower = { unit = "mW" } },
}, 2)
tick = 401
local longElrsValues = standby.snapshot(elrsFull, elrsCache)
check("arbitrary ELRS label remains exact", string.find(longElrsValues.elrs, string.rep("LongRate", 20), 1, true) ~= nil)
check("arbitrary ELRS overflow invalidates layout", elrsCache.valueOverflow == true)

local elrsWide = standby.decode("elrs:wide")
local wideCache = { text = elrsCache.text }
standby.setElrsSnapshot(wideCache, {
  status = "ready", readAt = 3, identity = "wide", packetRate = "D250", telemetryRatio = "Std",
  maxPower = "250", dynamic = "Dyn", fields = { maxPower = { unit = "mW" } },
}, 3)
tick = 500
local wideValues = standby.snapshot(elrsWide, wideCache)
standby.build({ w = 800, h = 480 }, "Waiting", wideCache.text, elrsWide, wideValues, wideCache)
standby.setElrsSnapshot(wideCache, {
  status = "ready", readAt = 4, identity = "wide", packetRate = string.rep("ExactRate", 12), telemetryRatio = "Std",
  maxPower = "250", dynamic = "Dyn", fields = { maxPower = { unit = "mW" } },
}, 4)
tick = 601
standby.snapshot(elrsWide, wideCache)
check("wide ELRS field overflow invalidates its cell", wideCache.valueOverflow == true)

print(string.format("standby regression: %d checks passed", passed))
