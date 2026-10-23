-- Exercises absent flight-statistic sources with desktop Lua 5.3:
--   lua5.3 bin/telemetry/verify_flight_record_absent.lua
--   lua5.3 bin/telemetry/verify_flight_record_absent.lua --record <pre-fix-record.lua>
--   lua5.3 bin/telemetry/verify_flight_record_absent.lua --common <pre-fix-common.lua>
-- The flight record and dashboard statistic reader are real; only the EdgeTX clock,
-- session and sensor reads are stubbed. Controlled checks, no hardware or timing claim.
-- Exit status: 0 green, 1 failed expectations, 2 invalid arguments/unreadable source.

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]telemetry$") or (dir .. "/../..") end
end
local recordPath = ROOT .. "/src/rfsuite/tasks/events/telemetry/flight_record.lua"
local commonPath = ROOT .. "/src/rfsuite/widgets/dashboard/objects/common.lua"
local i = 1
while i <= #arg do
  if arg[i] == "--record" and arg[i + 1] then
    i = i + 1
    recordPath = arg[i]
  elseif arg[i] == "--common" and arg[i + 1] then
    i = i + 1
    commonPath = arg[i]
  else
    io.stderr:write("usage: lua5.3 bin/telemetry/verify_flight_record_absent.lua [--record <file>] [--common <file>]\n")
    os.exit(2)
  end
  i = i + 1
end
local function source(path)
  local chunk, err = loadfile(path)
  if not chunk then io.stderr:write(tostring(err) .. "\n"); os.exit(2) end
  return chunk
end
local recordChunk, commonChunk = source(recordPath), source(commonPath)
local function equal(actual, expected, label)
  assert(actual == expected, label .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function newWorld()
  local world = { now = 0, reads = {}, sensors = {
    rpm = 2000, link = 100, temp_mcu = 40, bec_voltage = 8,
    throttle_percent = 60, current = 10, voltage = 24, watts = 240,
    smartconsumption = 100, governor = 0, pid_profile = 1, fuel = 80,
  } }
  local modules = {
    ["lib/sensors.lua"] = { getValue = function(name)
      world.reads[name] = (world.reads[name] or 0) + 1
      return world.sensors[name]
    end },
  }
  _G.getTime = function() return world.now * 100 end
  _G.rfsuite = { session = {}, require = function(path) return assert(modules[path], path) end }
  world.session = _G.rfsuite.session
  world.record = recordChunk()
  function world:fly(beforeSample)
    self.reads = {}
    self.record.open()
    -- Include both endpoints: 25 samples, 0.5 s apart, over 12 armed seconds.
    for sample = 1, 25 do
      if beforeSample then beforeSample(self.sensors, sample) end
      self.record.wakeup(true, true)
      if sample < 25 then self.now = self.now + 0.5 end
    end
    self.record.close()
    equal(self.session.flight.lastSeconds, 12, "armed seconds")
    equal(self.reads.temp_esc, 25, "ESC sensor samples")
    equal(self.reads.altitude, 25, "altitude sensor samples")
    return self.session.flight.last
  end
  return world
end
local function present(sensors, sample)
  sensors.temp_esc = 45 + math.floor((sample - 1) * 5 / 24)
  sensors.altitude = 10
end
local function absent(last)
  equal(last.minEscTemp, nil, "minEscTemp")
  equal(last.maxEscTemp, nil, "maxEscTemp")
  equal(last.maxAltitude, nil, "maxAltitude")
end
local function extremes(last)
  equal(last.minEscTemp, 45, "minEscTemp")
  equal(last.maxEscTemp, 50, "maxEscTemp")
  equal(last.maxAltitude, 10, "maxAltitude")
end
local cases = {}
local function case(name, run) cases[#cases + 1] = { name = name, run = run } end

case("A: absent ESC temperature and altitude", function()
  local last = newWorld():fly()
  equal(last.maxRpm, 2000, "present RPM positive control")
  absent(last)
end)
case("B: present sensors positive control", function()
  local world = newWorld()
  extremes(world:fly(present))
  -- Missing answers within the same connection keep readings across flights.
  world.sensors.temp_esc, world.sensors.altitude = nil, nil
  local last = world:fly()
  equal(last.minEscTemp, 50, "held minEscTemp")
  equal(last.maxEscTemp, 50, "held maxEscTemp")
  equal(last.maxAltitude, 10, "held maxAltitude")
end)
case("C: ESC temperature first answers on second sample", function()
  local last = newWorld():fly(function(sensors, sample)
    if sample > 1 then sensors.temp_esc = 45 end
    sensors.altitude = 10
  end)
  equal(last.minEscTemp, 45, "minEscTemp")
end)
case("D: reset drops the previous session's readings", function()
  local world = newWorld()
  extremes(world:fly(present))
  world.record.reset()
  world.sensors.temp_esc, world.sensors.altitude = nil, nil
  absent(world:fly())
end)
case("E: powered gate accepts absent sources", function()
  local variants = {
    { name = "RPM only", rpm = 2000 },
    { name = "RPM absent", throttle = 60, current = 10 },
    { name = "throttle absent", rpm = 2000, current = 10, minimum = 2000 },
    { name = "current absent", rpm = 2000, throttle = 60, minimum = 2000 },
  }
  for _, variant in ipairs(variants) do
    local world = newWorld()
    world.sensors.rpm = variant.rpm
    world.sensors.throttle_percent = variant.throttle
    world.sensors.current = variant.current
    local ok, last = pcall(function() return world:fly() end)
    assert(ok, variant.name .. ": " .. tostring(last))
    equal(last.minRpm, variant.minimum, variant.name .. " powered minimum")
  end
end)
case("F: dashboard uses only the current flight while armed", function()
  _G.__rfsuiteObjectsCommonModule = nil
  local utils = commonChunk()
  local flight = { armed = true, current = {}, last = { maxEscTemp = 50 } }
  equal(utils.statFromRecord(flight, "maxEscTemp"), nil, "armed absent statistic")
  flight.armed = false
  equal(utils.statFromRecord(flight, "maxEscTemp"), 50, "disarmed fallback")
  flight.current.maxEscTemp = 47
  equal(utils.statFromRecord(flight, "maxEscTemp"), 47, "disarmed current first")
  flight.armed = true
  equal(utils.statFromRecord(flight, "maxEscTemp"), 47, "armed current statistic")
end)
case("G: late current flushes the previous session's delay line", function()
  local world = newWorld()
  world.sensors.governor = nil
  world.sensors.current = 5
  equal(world:fly().minCurrent, 5, "previous session positive control")
  world.record.reset()
  world.sensors.current = nil
  local last = world:fly(function(sensors, sample)
    if sample > 12 then sensors.current = 30 end
  end)
  equal(last.minCurrent, 30, "new session minCurrent")
end)

local failures = 0
for _, item in ipairs(cases) do
  local ok, err = pcall(item.run)
  if not ok then failures = failures + 1 end
  print((ok and "PASS" or "FAIL") .. ": " .. item.name .. (ok and "" or (": " .. tostring(err))))
end
print(string.format("%d cases, %d failures", #cases, failures))
os.exit(failures == 0 and 0 or 1)
