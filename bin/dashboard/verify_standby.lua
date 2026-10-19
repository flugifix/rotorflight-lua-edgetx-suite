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

local overflow = standby.decode("clock:full,date:full,tx_battery:full,model:full")
check("480x320 overflow rejected", not standby.validate(overflow, 480, 320))
local longLabels = { clock = string.rep("W", 100), tx_battery = "TX", model = "Model" }
check("localized label width checked", not standby.validate(default, 480, 320, longLabels))

print(string.format("standby regression: %d checks passed", passed))
