-- Run the real SmartFuel module with voltage sag and rising consumption in all local source modes.
local checks, failures = 0, 0
local function equal(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    failures = failures + 1
    print("FAIL " .. label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local ROOT = "src/rfsuite/"
local SMART = ROOT .. "tasks/events/telemetry_bg/smart.lua"

-- Supply the radio clock, telemetry and armed state; load the real calculation helpers.
bit32 = { band = function(a, b) return a & b end }
UNIT_PERCENT, UNIT_MAH = 13, 4
function setTelemetryValue() end
function loadScript(path)
  return loadfile(ROOT .. string.gsub(path, "^/SCRIPTS/TOOLS/rfsuite%-core/", ""))
end
local clock = 0
function getTime() return clock end
local tele = {}
local SensorsStub = { getValue = function(name) return tele[name] end }
local mods = {}
rfsuite = {
  session = {},
  require = function(path)
    if path == "lib/sensors.lua" then return SensorsStub end
    if path == "tasks/msp/runtime.lua" then
      return { getState = function() return { lastArmed = true } end }
    end
    if path == "lib/log.lua" then return {} end
    if mods[path] == nil then mods[path] = assert(loadfile(ROOT .. path))() end
    return mods[path]
  end,
}

local scenarios = {
  {
    name = "voltage sags, consumption 0",
    feed = function(t)
      if t <= 30 then return { voltage = 24.6, consumption = 0 } end
      return { voltage = 21.6, consumption = 0 }
    end,
  },
  {
    name = "voltage high, consumption rising",
    feed = function(t)
      return { voltage = 24.6, consumption = (t <= 30) and 0 or (t - 30) * 50 }
    end,
  },
}

for _, scenario in ipairs(scenarios) do
  -- A module error is a counted failure, including when testing an older implementation.
  local ok, err = pcall(function()
    local results = {}
    for _, source in ipairs({ 0, 1, 2 }) do
      local Smart = assert(loadfile(SMART))()
      rfsuite.session = {
        isConnected = true,
        apiVersion = "12.08",
        battery_config = {
          batteryCellCount = 6,
          vbatmaxcellvoltage = 430,
          vbatmincellvoltage = 330,
          vbatfullcellvoltage = 410,
          batteryCapacity = 5000,
        },
        modelPreferences = { battery = { smartfuel_source = source } },
      }
      clock = 0
      local samples = {}
      for t = 1, 120 do
        clock = clock + 100
        tele = scenario.feed(t)
        Smart.wakeup()
        if t % 30 == 0 then
          local sf = rfsuite.session.smartfuel
          -- Fixed indices preserve missing samples instead of shortening the assertion loop.
          samples[t / 30] = sf and sf.fuel
        end
      end
      results[source] = samples
    end

    for i = 1, 4 do
      local current, voltage, combined = results[0][i], results[1][i], results[2][i]
      local expected = (current and voltage) and math.min(current, voltage) or (current or voltage)
      local matches = combined ~= nil and expected ~= nil and math.abs(combined - expected) <= 0.05
      equal(matches, true, string.format(
        "%s sample %d (t=%ds): combined=%s, min(current=%s, voltage=%s)=%s within 0.05",
        scenario.name, i, i * 30, tostring(combined), tostring(current), tostring(voltage), tostring(expected)))
    end
  end)
  equal(ok and true or tostring(err), true, scenario.name .. " completes without error")
end

print(string.format("SmartFuel combined source: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
