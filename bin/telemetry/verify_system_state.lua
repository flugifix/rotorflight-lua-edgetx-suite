-- Offline module contracts; no radio, flight controller or simulator is run.
local count = 0
local function eq(actual, expected, name)
  count = count + 1
  assert(actual == expected, name .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local State = assert(loadfile("src/rfsuite/lib/system_state.lua"))()
local status = State.decode("system_status", 0x1fffffcf)
local config = State.decode("system_config", 0x03eff1d1)
for _, key in ipairs({"armed","airborne","motors_running","rx_link_up","gps_healthy","spooled_up",
  "control_saturated","gyro_overflow","acc_not_calibrated","override_active","blackbox_logging"}) do
  eq(status[key], true, "STAT " .. key)
  eq(State.decode("system_status", 0)[key], false, "zero STAT " .. key)
end
for key, value in pairs({failsafe_phase=7,gps_fix=3,battery_state=7,rescue_state=7,governor_state=15}) do
  eq(status[key], value, "STAT enum " .. key)
end
for _, key in ipairs({"unsaved_changes","saving","reboot_required","beeper_on","acc_present",
  "baro_present","mag_present","gps_present","blackbox_full","rpm_source_active"}) do
  eq(config[key], true, "SCFG " .. key)
  eq(State.decode("system_config", 0)[key], false, "zero SCFG " .. key)
end
eq(config.pid_profile, 1, "PID profile retains low integer bits")
eq(config.rate_profile, 2, "rate profile")
eq(config.battery_profile, 7, "battery profile")
eq(config.governor_mode, 7, "governor mode")
local isolated = {
  system_status = {armed=0,airborne=1,motors_running=2,rx_link_up=3,failsafe_phase=6,gps_fix=9,
    gps_healthy=11,spooled_up=12,battery_state=14,control_saturated=17,gyro_overflow=18,
    acc_not_calibrated=19,override_active=20,rescue_state=21,blackbox_logging=24,governor_state=25},
  system_config = {pid_profile=0,rate_profile=3,battery_profile=6,unsaved_changes=12,saving=13,
    reboot_required=14,beeper_on=15,acc_present=16,baro_present=17,mag_present=18,gps_present=19,
    blackbox_full=21,rpm_source_active=22,governor_mode=23}
}
for source, positions in pairs(isolated) do
  for selected, bit in pairs(positions) do
    local decoded = State.decode(source,1 << bit)
    for key in pairs(positions) do
      local expected = key == selected
      if type(decoded[key]) == "number" then expected = expected and 1 or 0 end
      eq(decoded[key],expected,"isolated " .. selected .. " leaves " .. key)
    end
  end
end
for _, value in ipairs({-1,0.5,0x80000000,math.huge,0/0,"123",false}) do
  eq(State.decode("system_status",value),nil,"invalid status word")
end
eq(State.decode("other",0),nil,"unknown source")
eq(State.read({},"system_status"),nil,"older sensor API")

local clock, values, live, quality = 1000, {}, {}, {}
function getTime() return clock end
function getVersion() return "2.12", "radio" end
function getFieldInfo(name) if values[name] ~= nil then return {id=1} end end
function getValue(name) return values[name] end
function getSourceValue(name)
  if quality[name] == "error" then error("source unavailable") end
  return values[name], live[name]
end
local Sensors = assert(loadfile("src/rfsuite/lib/sensors.lua"))()
local function reset()
  clock = clock + 4000; Sensors.reset()
end
values.STAT, live.STAT = 0, true
eq(Sensors.getLiveValue("system_status"),0,"live zero is data")
eq(State.read(Sensors,"system_status").armed,false,"live zero decodes")
values.STAT = 1 | (9 << 25)
eq(State.read(Sensors,"system_status").armed,true,"next sample")
live.STAT = false
eq(Sensors.getValue("system_status"),values.STAT,"legacy held reading unchanged")
eq(Sensors.getLiveValue("system_status"),nil,"adopted source becomes stale")
eq(State.read(Sensors,"system_status"),nil,"stale word is unknown")
live.STAT = nil
eq(Sensors.getLiveValue("system_status"),nil,"unknown quality is refused")
live.STAT = true; quality.STAT = "error"
eq(Sensors.getLiveValue("system_status"),nil,"source exception is unknown")
quality.STAT = nil
local saved = getSourceValue; getSourceValue = nil
eq(Sensors.getLiveValue("system_status"),nil,"missing quality API is unknown")
getSourceValue = saved
eq(Sensors.getLiveValue("system_status"),values.STAT,"source recovers without reset")
values.SCFG, live.SCFG = 1 | (2 << 3) | (3 << 6) | (7 << 23), true
reset()
eq(Sensors.getLiveValue("pid_profile"),1,"packed PID fallback")
clock = clock + 1
eq(Sensors.getLiveValue("rate_profile"),2,"packed rate fallback")
eq(Sensors.getLiveValue("battery_profile"),3,"packed battery fallback")
clock = clock + 1
eq(Sensors.getLiveValue("governor"),9,"packed governor fallback")
values["PID#"], live["PID#"] = 4, true; reset()
eq(Sensors.getLiveValue("pid_profile"),4,"dedicated source wins")
live["PID#"] = false
eq(Sensors.getLiveValue("pid_profile"),1,"stale dedicated source uses live packed word")
live.SCFG = false
eq(Sensors.getLiveValue("pid_profile"),nil,"both sources stale")
values, live = {}, {}; reset()
eq(Sensors.getLiveValue("system_status"),nil,"absent sensors")
eq(Sensors.getLiveValue(nil),nil,"invalid source")
values.STAT, live.STAT = 8, true; reset()
eq(State.read(Sensors,"system_status").rx_link_up,true,"reconnect after reset")
-- A duplicate native row must not hide the row currently arriving.
values.RxBt, live.RxBt = 12, true
values.telem1, live.telem1 = 1, false
values.telem2, live.telem2 = 8, true
model = {getSensor=function(index)
  if index < 2 then return {name="STAT"} end
end}
reset()
Sensors.getLiveValue("system_status")
clock = clock + 250
eq(Sensors.getLiveValue("system_status"),8,"current duplicate slot is used")
live.telem2 = false
eq(Sensors.getLiveValue("system_status"),nil,"all duplicate slots stale")
live.telem2 = true

-- Count a real steady module read, including decoding, rather than a mock getter.
local instructions = 0
debug.sethook(function() instructions = instructions + 1 end, "", 1)
local received = State.read(Sensors,"system_status")
debug.sethook()
eq(received.rx_link_up,true,"measured read positive control")
assert(instructions < 2000, "live packed read exceeds 2000 instructions: " .. instructions)
print(string.format("Packed state: %d assertions, read %d instructions (<2000)",count,instructions))
-- Stress beyond EdgeTX 2.12's 75-slot maximum, with the live duplicate last.
model.getSensor=function(index) if index < 99 then return {name="STAT"} end end
for index=1,99 do
  values["telem"..index], live["telem"..index] = 8, index == 99
end
reset(); Sensors.getLiveValue("system_status");clock=clock+250
instructions=0
debug.sethook(function() instructions=instructions+1 end,"",1)
received=State.read(Sensors,"system_status")
debug.sethook()
eq(received.rx_link_up,true,"last of 99 duplicate sensors is live")
assert(instructions < 7000,"99-slot stress table exceeds 7000 instructions: " .. instructions)
print(string.format("99-slot stress table: %d instructions (<7000)",instructions))
if arg[1] == "--self-test" then
  for index=1,99 do live["telem"..index]=false end
  live.STAT=false
  eq(State.read(Sensors,"system_status"),nil,"negative-control fixture is stale")
  local original = Sensors.getLiveValue
  Sensors.getLiveValue = Sensors.getValue
  local ok = pcall(function() eq(State.read(Sensors,"system_status"),nil,"held-value negative control") end)
  Sensors.getLiveValue = original
  assert(not ok,"negative control failed to reject a held reading")
  print("Negative control: held-value implementation rejected")
end
