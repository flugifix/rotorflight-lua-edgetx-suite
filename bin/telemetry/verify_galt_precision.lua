-- Exercises CRSF GPS altitude decoding with desktop Lua 5.3:
--   lua5.3 bin/telemetry/verify_galt_precision.lua
-- Uses the real decoder; only EdgeTX APIs and the session are stubbed.
-- Exit status: 0 green, 1 failed expectations, 2 unreadable source.

local ROOT = "."
do
    local this = arg and arg[0]
    local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
    if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]telemetry$") or (dir .. "/../..") end
end

local function source(path)
    local chunk, err = loadfile(ROOT .. "/src/rfsuite/" .. path)
    if not chunk then io.stderr:write(tostring(err) .. "\n"); os.exit(2) end
    return chunk
end

local decoderChunk = source("lib/rf2tlm_sensors.lua")
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function newWorld(version, requested, due)
    local world = { calls = {} }
    _G.UNIT_METERS = 9
    _G.setTelemetryValue = function(...)
        world.calls[#world.calls + 1] = { ... }
    end
    _G.rfsuite = { session = { apiVersion = version } }
    world.sensors = decoderChunk(requested, due)
    world.sensor = assert(world.sensors[0x1126], "GAlt sensor missing")
    equal(world.sensor.prec, 2, "static discovery precision")
    return world
end

local function decode(world, data, first, value, precision)
    local before = #world.calls
    local result, pos = world.sensor.dec(data, first)
    equal(result, nil, "self-publishing decoder return")
    equal(pos, first + 2, "S16 byte count")
    equal(#world.calls, before + 1, "publication count")
    local call = world.calls[#world.calls]
    local expected = { 0x1126, 0, 0, value, UNIT_METERS, precision, "GAlt" }
    for i = 1, #expected do equal(call[i], expected[i], "publication argument " .. i) end
end

local cases = {}
local function case(name, run) cases[#cases + 1] = { name = name, run = run } end

for _, entry in ipairs({ { "12.09", 2 }, { "12.10", 1 }, { "12.11", 1 },
    { "13.00", 1 }, { "", 2 }, { "garbage", 2 }, { false, 2 } }) do
    local version, precision = entry[1], entry[2]
    case("API " .. (version == "" and '""' or tostring(version or "unknown")), function()
        local world = newWorld(version or nil)
        decode(world, { 0x0B, 0xB8 }, 1, 3000, precision)
        decode(world, { 0x7F, 0xFF }, 1, 32767, precision)
    end)
end

case("API changes in the same decoder", function()
    local world = newWorld("12.09")
    for _, entry in ipairs({ { "12.09", 2 }, { "12.10", 1 }, { "12.11", 1 },
        { false, 2 }, { "12.09", 2 }, { "invalid", 2 }, { "12.0.10", 2 }, { "13.00", 1 } }) do
        _G.rfsuite.session.apiVersion = entry[1] or nil
        decode(world, { 0x0B, 0xB8 }, 1, 3000, entry[2])
    end
end)

case("missing session and missing suite", function()
    local world = newWorld("12.10")
    decode(world, { 0x0B, 0xB8 }, 1, 3000, 1)
    _G.rfsuite.session = nil
    decode(world, { 0x0B, 0xB8 }, 1, 3000, 2)
    _G.rfsuite = nil
    decode(world, { 0x0B, 0xB8 }, 1, 3000, 2)
end)

case("signed S16 and noninitial offset", function()
    local world = newWorld("12.10")
    decode(world, { 0, 0xFF, 0xFF, 0 }, 2, -1, 1)
    decode(world, { 0, 0x80, 0x00, 0 }, 2, -32768, 1)
end)

case("due throttle rejects and accepts the exact S16 span", function()
    local allow = false
    local data = { 0, 0x0B, 0xB8, 0 }
    local checks = 0
    local world = newWorld("12.10", nil, function(sid, bytes, first, last)
        checks = checks + 1
        equal(sid, 0x1126, "throttle sensor")
        equal(bytes, data, "throttle frame")
        equal(first, 2, "throttle first byte")
        equal(last, 4, "throttle end offset")
        return allow
    end)
    local value, pos = world.sensor.dec(data, 2)
    equal(value, nil, "throttled return")
    equal(pos, 4, "throttled byte count")
    equal(#world.calls, 0, "no throttled publication")
    allow = true
    decode(world, data, 2, 3000, 1)
    equal(checks, 2, "throttle calls")
end)

case("discovery registers two decimals on newer firmware", function()
    local world = newWorld("12.10", { 78 })
    equal(#world.calls, 1, "discovery publication count")
    equal(world.calls[1][6], 2, "registered precision")
end)

local failures = 0
for _, item in ipairs(cases) do
    local ok, err = pcall(item.run)
    if not ok then failures = failures + 1 end
    print((ok and "PASS" or "FAIL") .. ": " .. item.name .. (ok and "" or (": " .. tostring(err))))
end
print(string.format("%d cases, %d failures", #cases, failures))
os.exit(failures == 0 and 0 or 1)
