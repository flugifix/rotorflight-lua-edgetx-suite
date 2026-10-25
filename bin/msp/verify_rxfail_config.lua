-- Offline byte-vector checks. No simulator or flight controller is used.
local root = arg[1] or "src/rfsuite/tasks/msp/api/"
local Api = assert(loadfile(root .. "rxfail_config.lua"))()
local checks = 0
local function equal(actual, expected, label)
  checks = checks + 1
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end

local function reply(length)
  local buf = {}
  for i = 1, 19 do
    local value = 1000 + i * 25
    buf[#buf + 1] = i % 3
    buf[#buf + 1] = value % 256
    buf[#buf + 1] = math.floor(value / 256)
  end
  while #buf > length do table.remove(buf) end
  return buf
end

for _, case in ipairs({ { 48, 16 }, { 54, 18 }, { 47, 15 }, { 57, 18 }, { 3, 1 } }) do
  local length, count = case[1], case[2]
  local parsed = assert(Api.parse(reply(length)))
  equal(parsed.channel_count, count, "channel count")
  for i = 1, count do
    equal(parsed["channel_" .. i .. "_mode"], i % 3, "channel mode " .. i)
    equal(parsed["channel_" .. i .. "_value"], 1000 + i * 25, "channel value " .. i)
  end
  for i = count + 1, 19 do
    equal(parsed["channel_" .. i .. "_mode"], nil, "absent channel mode " .. i)
    equal(parsed["channel_" .. i .. "_value"], nil, "absent channel value " .. i)
  end
  print(string.format("%d bytes: channel_count=%d, channel_%d_mode=nil, channel_%d_value=nil", length, count, count + 1, count + 1))
end
for length = 0, 2 do equal(Api.parse(reply(length)), nil, "no complete record") end
equal(Api.parse(nil), nil, "missing reply")
equal(Api.parse(""), nil, "invalid reply")
print(string.format("RXFAIL_CONFIG: %d checks passed", checks))
