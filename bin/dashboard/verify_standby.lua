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
getTxGPS = function() return { fix = nil } end
model = {
  getInfo = function() return { name = string.rep("W", 30) } end,
  getTimer = function(index) return { value = index == 0 and 999999 or 0 } end,
}
local cache = { text = function(_, fallback) return fallback end }
local values, key = standby.snapshot(default, cache)
check("snapshot reads transmitter battery safely", type(values) == "table" and values.tx_battery == "-")
check("snapshot uses firmware version", values.firmware == "2.12.0")
check("missing GPS fix stays unknown", values.tx_gps == "-")
check("model display is bounded", #values.model == 15)
check("timer display is bounded", values.timer1 == "999:59")
local scene = standby.build({ w = 480, h = 320 }, "Please wait...", cache.text, default, values, cache)
check("standby scene builds", type(scene) == "table" and #scene > 3)
local valueClosure
for i = 1, #scene do if type(scene[i].text) == "function" then valueClosure = scene[i].text; break end end
check("scene exposes reactive value", type(valueClosure) == "function")
local before = valueClosure()
cache.snapshotValues.clock = "12:35"
check("reactive value updates without rebuild", valueClosure() ~= before)

print(string.format("standby regression: %d checks passed", passed))
