MIDSIZE, SMLSIZE = 2, 1
LCD_W, LCD_H = 480, 320
lcd = { sizeText = function(text, font) return #text * (font == MIDSIZE and 10 or 7), font == MIDSIZE and 22 or 16 end }

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
  return { fix = true, numsat = 7 }
end
model = {
  getInfo = function() return { name = string.rep("W", 30) } end,
  getTimer = function(index) return { value = index == 0 and 999999 or 0 } end,
}
local cache = { text = function(_, fallback) return fallback end }
local values, key = standby.snapshot(default, cache)
check("snapshot reads transmitter battery safely", type(values) == "table" and values.tx_battery == "-")
check("snapshot uses firmware version", values.firmware == "2.12.0")
check("default snapshot skips unselected GPS getter", gpsCalls == 0 and values.tx_gps == nil)
check("model display is bounded", #values.model == 15)
check("timer overflow remains explicit", values.timer1 == ">999:59")
model.getInfo = function() return { name = "Model\195\169LongEnough" } end
tick = 201
local utf8Values = standby.snapshot(default, cache)
check("UTF-8 model truncates at a codepoint", utf8Values.model == "Model\195\169LongEn...")
check("unselected GPS remains skipped after snapshot cadence", gpsCalls == 0)

local gpsItems = standby.decode("tx_gps:wide")
local gpsCache = { text = cache.text }
tick = 300
local gpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS reads and formats transmitter fix", gpsCalls == 1 and gpsValues.tx_gps == "Fix · 7")
tick = 350
local cachedGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS snapshot respects one-second cache", gpsCalls == 1 and cachedGpsValues == gpsValues)
tick = 401
local refreshedGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS refreshes after bounded cadence", gpsCalls == 2 and refreshedGpsValues.tx_gps == "Fix · 7")getTxGPS = function() gpsCalls = gpsCalls + 1; return { fix = nil } end
tick = 502
local unknownGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected GPS with missing fix stays unknown", gpsCalls == 3 and unknownGpsValues.tx_gps == "-")
getTxGPS = function() gpsCalls = gpsCalls + 1; return nil end
tick = 603
local unavailableGpsValues = standby.snapshot(gpsItems, gpsCache)
check("selected unavailable GPS stays unknown", gpsCalls == 4 and unavailableGpsValues.tx_gps == "-")
local scene = standby.build({ w = 480, h = 320 }, "Please wait...", cache.text, default, values, cache)
check("standby scene builds", type(scene) == "table" and #scene > 3)
local infoScene = standby.build({ w = 480, h = 320 }, "Exact connection reason", cache.text, default, values, cache,
  { text = "Flight controller not detected", level = "info" })
check("general information strip uses calm theme accent", infoScene[8].color == COLOR_THEME_SECONDARY1)
check("general information strip preserves exact status below", infoScene[10].text == "Exact connection reason")
local warningScene = standby.build({ w = 480, h = 320 }, "Unsupported API 9.9", cache.text, default, values, cache,
  { text = "Compatibility check failed", level = "warning" })
check("warning information uses warning marker", warningScene[8].color == COLOR_THEME_WARNING)
local utf8InfoScene = standby.build({ w = 480, h = 320 }, "Waiting", cache.text, default, values, cache,
  { text = string.rep("Pr\195\169requis", 200), level = "info" })
local fittedInfo = utf8InfoScene[9].text
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
  if node.type == "rectangle" and node.radius then tileCount = tileCount + 1 end
end
check("largest eight-item scene renders every tile", largestCache.valueOverflow == false and tileCount == 8)
check("tile captions use the theme accent", scene[12].color == COLOR_THEME_SECONDARY1)
check("status line clears small tool control", scene[3].x + scene[3].w <= 480 - 20 - 1 - 6)
local largeScene = standby.build({ w = 800, h = 480 }, string.rep("W", 80), cache.text, default, values, cache)
check("status line clears large tool control", largeScene[3].x + largeScene[3].w <= 800 - 44 - 8 - 6)
check("status line preserves the full reason", largeScene[10].text == string.rep("W", 80))
local valueClosure = scene[13].text
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
