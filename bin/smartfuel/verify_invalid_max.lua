-- Exercises missing/invalid SmartFuel Max handling with desktop Lua 5.3:
--   lua5.3 bin/smartfuel/verify_invalid_max.lua [--verbose]
--   lua5.3 bin/smartfuel/verify_invalid_max.lua --source-root <other-checkout>
-- Smart.wakeup, its reserve/version helpers and the flight-record reader are real.
-- Only EdgeTX's clock, telemetry reads/publications and MSP armed state are stubbed.
-- The override runs these same expectations against a frozen pre-fix source tree.
-- Controlled state/numeric checks; no hardware, simulator or timing claim.
-- Exit status: 0 green, 1 failed expectations, 2 invalid arguments/unreadable source.

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]smartfuel$") or (dir .. "/../..") end
end
local sourceRoot, verbose = ROOT, false
local i = 1
while i <= #arg do
  if arg[i] == "--verbose" then
    verbose = true
  elseif arg[i] == "--source-root" and arg[i + 1] then
    i = i + 1
    sourceRoot = arg[i]
  else
    io.stderr:write("usage: lua5.3 bin/smartfuel/verify_invalid_max.lua [--verbose] [--source-root <checkout>]\n")
    os.exit(2)
  end
  i = i + 1
end
local SRC = sourceRoot .. "/src/rfsuite/"
local function loadModule(path)
  local chunk, err = loadfile(SRC .. path)
  if not chunk then io.stderr:write(tostring(err) .. "\n"); os.exit(2) end
  return chunk()
end
local function equal(actual, expected, label)
  assert(actual == expected, label .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end
local function near(actual, expected, label)
  assert(type(actual) == "number" and math.abs(actual - expected) < 0.000001,
    label .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function newWorld(mode)
  local world = { now = 0, publications = {}, reads = {}, sensors = { voltage = 25.8, consumption = 0 } }
  local battery = { batteryCapacity = 5000, batteryCellCount = 0,
    vbatmincellvoltage = 330, vbatmaxcellvoltage = 430, vbatfullcellvoltage = 410 }
  local session = { isConnected = true, apiVersion = { 12, 0, 9 }, battery_config = battery,
    smartfuel_config = { smartfuel_mode = 0 }, modelPreferences = { battery = {
      smartfuel_source = mode or 1, smartfuel_publish = true, stabilize_delay = 0,
      consumption_warning_percentage = 15,
    } } }
  local modules = {
    ["lib/sensors.lua"] = { getValue = function(name)
      world.reads[name] = (world.reads[name] or 0) + 1
      return world.sensors[name]
    end },
    ["tasks/msp/runtime.lua"] = { getState = function() return { lastArmed = false } end },
    ["lib/log.lua"] = { emit = function() end },
    ["lib/api_version.lua"] = loadModule("lib/api_version.lua"),
    ["lib/smartfuel_reserve.lua"] = loadModule("lib/smartfuel_reserve.lua"),
  }
  _G.getTime = function() return world.now * 100 end
  _G.setTelemetryValue = function(id, subId, instance, value, unit, precision, name)
    world.publications[#world.publications + 1] = {
      id = id, subId = subId, instance = instance, value = value, unit = unit, precision = precision, name = name,
    }
  end
  _G.rfsuite = { session = session, require = function(path) return assert(modules[path], path) end }
  world.session, world.battery = session, battery
  world.smart = loadModule("tasks/events/telemetry_bg/smart.lua")
  function world:tick(count)
    for _ = 1, count or 1 do self.now = self.now + 1; self.smart.wakeup() end
  end
  function world:ready()
    self:tick(12)
    near(self.session.smartfuel and self.session.smartfuel.fuel, 100, "initial fuel")
    assert(#self.publications > 0, "positive control: initial fuel was never published")
    return self
  end
  return world
end
local function unavailable(world)
  local values = world.session.smartfuel
  assert(type(values) == "table", "missing SmartFuel unavailable state")
  equal(values.unavailable, true, "unavailable marker")
  equal(values.fuel, nil, "fuel handover")
  equal(values.consumption, nil, "consumption handover")
end
local cases = {}
local function case(name, run) cases[#cases + 1] = { name = name, run = run } end

-- The firmware supports raw Max 100..500 centivolts. Max is needed only for local
-- estimation without a configured or sensed count.
local invalid = {
  { "missing", nil }, { "nonnumeric", "unknown" }, { "false", false },
  { "zero", 0 }, { "negative", -430 }, { "NaN", 0 / 0 },
  { "positive infinity", math.huge }, { "negative infinity", -math.huge },
  { "below supported range", 99 }, { "above supported range", 501 },
}
for _, variant in ipairs(invalid) do
  case("invalid Max: " .. variant[1], function()
    local world = newWorld():ready()
    local before = #world.publications
    world.battery.vbatmaxcellvoltage = variant[2]
    world:tick()
    unavailable(world)
    world:tick(6)
    unavailable(world)
    equal(#world.publications, before, "publications while unavailable")
  end)
end
case("invalid Max before first estimate", function()
  local world = newWorld()
  world.battery.vbatmaxcellvoltage = nil
  world:tick(12)
  unavailable(world)
  equal(#world.publications, 0, "publications without valid Max")
end)
case("missing entire battery configuration", function()
  local world = newWorld():ready()
  local before = #world.publications
  world.session.battery_config = nil
  world:tick()
  unavailable(world)
  world:tick(6)
  equal(#world.publications, before, "publications without configuration")
end)
case("unavailable stays latched until a fresh estimate", function()
  local world = newWorld():ready()
  world.battery.vbatmaxcellvoltage = 0
  world:tick()
  unavailable(world)
  local before = #world.publications
  world.battery.vbatmaxcellvoltage = 430
  world.sensors.voltage = 2.5
  for _ = 1, 4 do
    world:tick()
    unavailable(world)
    equal(#world.publications, before, "publications during recovery stabilization")
  end
  world:tick()
  equal(world.session.smartfuel.unavailable, nil, "recovered marker")
  near(world.session.smartfuel.fuel, 0, "fresh recovered fuel")
  near(world.session.smartfuel.consumption, 4250, "fresh recovered consumption")
  equal(#world.publications, before + 2, "fresh recovery publications")
end)
case("current mode drops its starting-consumption history", function()
  local world = newWorld(0):ready()
  world.battery.vbatmaxcellvoltage = 0
  world:tick()
  unavailable(world)
  world.battery.vbatmaxcellvoltage = 430
  world.sensors.voltage = 2.5
  for _ = 1, 4 do world:tick(); unavailable(world) end
  world:tick()
  near(world.session.smartfuel.fuel, 0, "fresh current-mode estimate")
  equal(world.session.smartfuel.consumption, nil, "current-mode virtual consumption")
  equal(world.session.smartfuel.unavailable, nil, "current-mode recovered marker")
end)
case("configuration recovery keeps unavailable during stabilization", function()
  local world = newWorld():ready()
  world.session.battery_config = nil
  world:tick()
  unavailable(world)
  world.session.battery_config = world.battery
  for _ = 1, 4 do world:tick(); unavailable(world) end
  world:tick()
  near(world.session.smartfuel.fuel, 100, "recovered configuration fuel")
  equal(world.session.smartfuel.unavailable, nil, "configuration recovered marker")
end)
case("configured count has priority over invalid Max", function()
  local world = newWorld()
  world.battery.batteryCellCount = 6
  world.battery.vbatmaxcellvoltage = 0
  world:ready()
  equal(world.session.smartfuel.unavailable, nil, "configured-count marker")
end)
case("sensed count has priority over invalid Max", function()
  local world = newWorld()
  world.sensors.battery_cell_count = 6
  world.battery.vbatmaxcellvoltage = nil
  world:ready()
  equal(world.session.smartfuel.unavailable, nil, "sensed-count marker")
end)
case("held sensed count survives sensor gap and invalid Max", function()
  local world = newWorld()
  world.sensors.battery_cell_count = 6
  world:ready()
  world.sensors.battery_cell_count = nil
  world.battery.vbatmaxcellvoltage = 0
  world:tick(8)
  near(world.session.smartfuel.fuel, 100, "held-count fuel")
  equal(world.session.smartfuel.unavailable, nil, "held-count marker")
end)
case("numeric-string Max remains accepted", function()
  local world = newWorld()
  world.battery.vbatmaxcellvoltage = "430"
  world:ready()
  equal(world.session.smartfuel.unavailable, nil, "numeric-string marker")
end)
case("supported upper Max boundary remains accepted", function()
  local world = newWorld()
  world.battery.vbatmaxcellvoltage = 500
  world:ready()
  equal(world.session.smartfuel.unavailable, nil, "upper-bound marker")
end)
case("supported lower Max boundary remains accepted", function()
  local world = newWorld()
  world.battery.vbatmaxcellvoltage = 100
  world.sensors.voltage = 3.9
  world:tick(12)
  near(world.session.smartfuel.fuel, 0, "lower-bound fuel")
  equal(world.session.smartfuel.unavailable, nil, "lower-bound marker")
end)
case("dynamic Max is used on each wake", function()
  local world = newWorld()
  world.sensors.voltage = 23.7
  world:tick(12)
  assert(world.session.smartfuel.fuel < 100, "Max 430 did not infer six cells")
  near(world.session.smartfuel.fuel, 95.294117647059, "Max 430 fuel")
  world.battery.vbatmaxcellvoltage = 440
  world:tick(6)
  near(world.session.smartfuel.fuel, 100, "Max 440 infers five cells")
  equal(world.battery.vbatmaxcellvoltage, 440, "firmware Max remains unchanged")
end)
case("dynamic Full remains independent from Max", function()
  local world = newWorld()
  world.sensors.voltage = 24.6
  world.battery.batteryCellCount = 6
  world:ready()
  world.battery.vbatfullcellvoltage = 420
  world:tick(6)
  assert(world.session.smartfuel.fuel < 100, "changed Full was ignored")
  near(world.session.smartfuel.fuel, 98.823529411765, "changed Full fuel")
  equal(world.battery.vbatfullcellvoltage, 420, "firmware Full remains unchanged")
  equal(world.battery.vbatmaxcellvoltage, 430, "Full does not replace Max")
end)
case("missing Full retains the existing 410 fallback", function()
  local world = newWorld()
  world.sensors.voltage = 24.6
  world.battery.vbatfullcellvoltage = nil
  world:ready()
  equal(world.battery.vbatfullcellvoltage, nil, "Full fallback is not written to firmware config")
end)
case("firmware-source mode does not need local Max", function()
  local world = newWorld()
  world.session.smartfuel_config.smartfuel_mode = 1
  world.battery.vbatmaxcellvoltage = 0
  world.sensors.fuel = 66
  world:tick(12)
  near(world.session.smartfuel.fuel, 60, "firmware fuel with reserve")
  equal(world.session.smartfuel.unavailable, nil, "firmware-source marker")
  equal(world.session.smartfuel.consumption, nil, "firmware-source consumption")
end)
for _, variant in ipairs({
  { "zero", 0, 0 }, { "ten", 10, 10 }, { "maximum", 60, 60 },
  { "above maximum", 61, 35 }, { "missing", nil, 35 },
}) do
  case("flight-controller reserve: " .. variant[1], function()
    local world = newWorld()
    world.session.modelPreferences.battery.consumption_warning_percentage = nil
    world.battery.consumptionWarningPercentage = variant[2]
    local reserve = loadModule("lib/smartfuel_reserve.lua")
    equal(reserve.resolve(world.session, world.battery), variant[3], "resolved reserve")
  end)
end
case("firmware fuel without reserve follows the raw reading", function()
  local world = newWorld()
  world.session.modelPreferences.battery.consumption_warning_percentage = nil
  world.battery.consumptionWarningPercentage = 0
  world.session.smartfuel_config.smartfuel_mode = 1
  world.sensors.fuel = 66
  world:tick(12)
  near(world.session.smartfuel.fuel, world.sensors.fuel, "firmware fuel without reserve")
  equal(world.session.smartfuel.unavailable, nil, "firmware-source marker without reserve")
  assert(#world.publications > 0, "positive control: firmware fuel was never published")
end)
case("flight record cannot recover stale sensors or held readings", function()
  local world = newWorld():ready()
  world.sensors.smartfuel, world.sensors.fuel = 73, 66
  world.sensors.smartconsumption = 1234
  local record = loadModule("tasks/events/telemetry/flight_record.lua")
  record.open()
  record.wakeup(true, true)
  near(world.session.flight.current.minFuel, 100, "record positive control fuel")
  near(world.session.flight.current.maxConsumedMah, 0, "record positive control consumption")
  world.battery.vbatmaxcellvoltage = 0
  world:tick()
  unavailable(world)
  world.session.telemetryRead = { pass = 1, now = world.now, reads = true,
    values = { smartfuel = 73, fuel = 66, smartconsumption = 1234 } }
  local fuelReads = (world.reads.smartfuel or 0) + (world.reads.fuel or 0)
  local consumptionReads = world.reads.smartconsumption or 0
  record.open()
  record.wakeup(true, true)
  equal(world.session.flight.current.minFuel, nil, "record fuel while unavailable")
  equal(world.session.flight.current.maxConsumedMah, nil, "record consumption while unavailable")
  equal(world.session.telemetryRead.values.smartfuel, nil, "shared smart fuel")
  equal(world.session.telemetryRead.values.fuel, nil, "shared plain fuel")
  equal(world.session.telemetryRead.values.smartconsumption, nil, "shared smart consumption")
  equal((world.reads.smartfuel or 0) + (world.reads.fuel or 0), fuelReads, "stale fuel sensor reads")
  equal(world.reads.smartconsumption or 0, consumptionReads, "stale consumption sensor reads")
end)

-- An explicit handover-contract fixture also tests the reader independently of
-- the producer, so --source-root can prove this consumer seam goes red itself.
case("flight record honors an explicit unavailable handover", function()
  local world = newWorld():ready()
  world.sensors.smartfuel, world.sensors.fuel = 73, 66
  world.sensors.smartconsumption = 1234
  local record = loadModule("tasks/events/telemetry/flight_record.lua")
  record.open()
  record.wakeup(true, true)
  near(world.session.flight.current.minFuel, 100, "reader-contract positive control")
  world.session.smartfuel = { unavailable = true }
  world.session.telemetryRead = { pass = 1, now = world.now + 1, reads = true,
    values = { smartfuel = 73, fuel = 66, smartconsumption = 1234 } }
  world.now = world.now + 1
  record.open()
  record.wakeup(true, true)
  equal(world.session.flight.current.minFuel, nil, "explicit unavailable record fuel")
  equal(world.session.flight.current.maxConsumedMah, nil, "explicit unavailable record consumption")
  equal(world.session.telemetryRead.values.smartfuel, nil, "explicit unavailable shared smart fuel")
  equal(world.session.telemetryRead.values.fuel, nil, "explicit unavailable shared plain fuel")
  equal(world.session.telemetryRead.values.smartconsumption, nil, "explicit unavailable shared consumption")
end)

local failures = 0
for _, item in ipairs(cases) do
  local ok, err = pcall(item.run)
  if not ok then failures = failures + 1 end
  if verbose or not ok then
    print((ok and "PASS" or "FAIL") .. ": " .. item.name .. (ok and "" or (": " .. tostring(err))))
  end
end
print(string.format("%d cases, %d failures", #cases, failures))
os.exit(failures == 0 and 0 or 1)
