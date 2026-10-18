-- Checks automatic voltage bounds through the real exported dashboard runtime, offline:
--
--   lua5.3 bin/dashboard/verify_voltage_bounds.lua
--   lua5.3 bin/dashboard/verify_voltage_bounds.lua --verbose
--   lua5.3 bin/dashboard/verify_voltage_bounds.lua --runtime <pre-fix-runtime.lua>
--
-- The last form runs the same expectations against another runtime, so a pre-fix source
-- can prove the regression check goes red without changing the working tree.
-- The accounting stubs supply EdgeTX, telemetry, the flight controller and a temporary SD
-- card. Runtime.new(...):reload(false) and its cell-count/bounds calculation are real;
-- these are controlled missing-count states, not a hardware or timing measurement.
-- Exit status: 0 green, 1 failed expectations, 2 invalid arguments.

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]dashboard$") or (dir .. "/../..") end
end

local runtimePath = ROOT .. "/src/rfsuite/widgets/dashboard/runtime.lua"
local verbose = false
local i = 1
while i <= #arg do
  if arg[i] == "--verbose" then
    verbose = true
  elseif arg[i] == "--runtime" and arg[i + 1] then
    i = i + 1
    runtimePath = arg[i]
  else
    io.stderr:write("usage: lua5.3 bin/dashboard/verify_voltage_bounds.lua [--verbose] [--runtime <file>]\n")
    os.exit(2)
  end
  i = i + 1
end

local Stubs = assert(loadfile(ROOT .. "/bin/accounting/stubs/edgetx.lua"))()
local FC = assert(loadfile(ROOT .. "/bin/accounting/stubs/fc.lua"))()

-- name, battery config, pack volts, held count, expected count/min/max, optional alias/custom bounds.
-- Expectations are literal values; no copy of the production count calculation lives here.
local cases = {
  { "centivolts", { vbatmincellvoltage = 330, vbatmaxcellvoltage = 430 }, 25.8, 0, 6, 19.8, 25.8 },
  { "volts", { vbatmincellvoltage = 3.3, vbatmaxcellvoltage = 4.3 }, 25.8, 0, 6, 19.8, 25.8 },
  { "decivolts", { vbatmincellvoltage = 33, vbatmaxcellvoltage = 43 }, 25.8, 0, 6, 19.8, 25.8 },
  { "millivolts", { vbatmincellvoltage = 3300, vbatmaxcellvoltage = 4300 }, 25.8, 0, 6, 19.8, 25.8 },
  { "numeric string", { vbatmincellvoltage = "330", vbatmaxcellvoltage = "430" }, "25.8", 0, 6, 19.8, 25.8 },
  { "held count priority", { batteryCellCount = 12, vbatmaxcellvoltage = 430 }, 51.6, 6, 6, 19.8, 25.8 },
  { "configured count priority", { batteryCellCount = 12, vbatmaxcellvoltage = 430 }, 25.8, 0, 12, 39.6, 51.6 },
  { "missing config", nil, 25.2, 0, 6, 19.8, 25.2 },
  { "missing cell limit", {}, 25.2, 0, 6, 19.8, 25.2 },
  { "zero cell limit", { vbatmaxcellvoltage = 0 }, 25.2, 0, 6, 19.8, 25.2 },
  { "negative cell limit", { vbatmaxcellvoltage = -430 }, 25.2, 0, 6, 19.8, 25.2 },
  { "invalid cell limit", { vbatmaxcellvoltage = "unknown" }, 25.2, 0, 6, 19.8, 25.2 },
  { "zero voltage", { vbatmaxcellvoltage = 430 }, 0, 0, nil, 18, 25.2 },
  { "missing voltage", { vbatmaxcellvoltage = 430 }, nil, 0, nil, 18, 25.2 },
  { "less than half a cell", { vbatmaxcellvoltage = 430 }, 2, 0, nil, 18, 25.2 },
  { "legacy session alias", { vbatmaxcellvoltage = 430 }, 25.8, 0, 6, 19.8, 25.8, "battery_config" },
  { "custom voltage bounds", { vbatmaxcellvoltage = 430 }, 25.8, 0, nil, 10, 30, nil, true },
}

local function near(actual, expected)
  return type(actual) == "number" and math.abs(actual - expected) < 0.000001
end

local failures = 0
for _, case in ipairs(cases) do
  Stubs.install(ROOT)
  FC.install(Stubs)
  Stubs.reset()
  FC.reset()
  local Runtime = assert(loadfile(runtimePath))()
  local widget = Runtime.new({ x = 0, y = 0, w = 800, h = 480 }, {})
  _G.rfsuite.session[case[8] or "batteryConfig"] = case[2]
  widget.state.voltage = case[3]
  widget.state.batteryCellCount = case[4]
  if case[9] then
    widget.dashboardLib.getThemeConfig = function() return { v_min = 10, v_max = 30 } end
  end
  widget:reload(false)
  local config = widget.state.themeConfig
  local correct = config._boundsCells == case[5] and near(config.v_min, case[6]) and near(config.v_max, case[7])
  if not correct then failures = failures + 1 end
  if verbose or not correct then
    print(string.format("%s: %s: cells=%s bounds=%s..%s (expected %s, %.3f..%.3f)",
      correct and "PASS" or "FAIL", case[1], tostring(config._boundsCells), tostring(config.v_min), tostring(config.v_max),
      tostring(case[5]), case[6], case[7]))
  end
end
Stubs.releaseCard()
print(string.format("%d cases, %d failures", #cases, failures))
os.exit(failures == 0 and 0 or 1)
