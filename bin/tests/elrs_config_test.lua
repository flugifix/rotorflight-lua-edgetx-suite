local root = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]bin[/\\]tests[/\\]") or ".")
_G.rfsuite = {}
model = {
  getInfo = function() return { filename = "model01.yml", name = "Model", bitmap = "m.png" } end,
  getModule = function(i) return { Type = i == 0 and 5 or 0, subType = 0 } end,
}
local Config = assert(loadfile(root .. "/src/rfsuite/lib/elrs_config.lua"))()
local function add(out, values) for i = 1, #values do out[#out + 1] = values[i] end end
local function str(value)
  local out = {}
  for i = 1, #value do out[#out + 1] = string.byte(value, i) end
  out[#out + 1] = 0
  return out
end
local function info(count)
  local out = { 0xEA, 0xEE }; add(out, str("ELRS TX"))
  add(out, { 0x45, 0x4C, 0x52, 0x53, 0, 0, 0, 1, 0, 4, 1, 0, count })
  return out
end
local function field(id, name, options, selected, unit)
  local out = { 0xEA, 0xEE, id, 0, 0, 9 }; add(out, str(name)); add(out, str(table.concat(options, ";")))
  add(out, { selected, 0, #options - 1, 0 }); add(out, str(unit or "")); return out
end
local function transport()
  local q, sent = {}, {}
  local crsf = { popFrame = function(kind)
    if not q[kind] or #q[kind] == 0 then return nil end
    return table.remove(q[kind], 1)
  end }
  local function push(kind, payload) sent[#sent + 1] = { kind, payload }; return true end
  local function put(kind, value) q[kind] = q[kind] or {}; q[kind][#q[kind] + 1] = value end
  return crsf, push, put, sent
end
local function read(dynamicLabel)
  Config.invalidate(nil)
  local crsf, push, put, sent = transport(); local identity = Config.currentIdentity()
  assert(Config.request(identity, { owner = "test" }))
  Config.step({ identity = identity, crsf = crsf, push = push, now = 0 })
  assert(#sent == 1 and sent[1][1] == 0x28, "ping sends=" .. tostring(#sent) .. " kind=" .. tostring(sent[1] and sent[1][1]))
  put(0x29, info(4)); Config.step({ identity = identity, crsf = crsf, push = push, now = 0.1 })
  local values = {
    field(1, "Packet Rate", { "D250", "500Hz" }, 1),
    field(2, "Telem Ratio", { "Std", "Race", "Off", "1:16" }, 1),
    field(3, "Max Power", { "25", "1000" }, 1, "mW"),
    field(4, "Dynamic", { "Off", "Dyn", "AUX9" }, dynamicLabel == "Off" and 0 or 2),
  }
  for i = 1, #values do
    Config.step({ identity = identity, crsf = crsf, push = push, now = i })
    put(0x2B, values[i]); Config.step({ identity = identity, crsf = crsf, push = push, now = i + 0.1 })
  end
  local got = Config.snapshot(identity)
  assert(got.status == "ready" and got.packetRate == "500Hz" and got.telemetryRatio == "Race")
  assert(got.maxPower == "1000" and got.fields.maxPower.milliwatts == 1000)
  assert(got.dynamic == dynamicLabel and got.fields.dynamic.enabled == (dynamicLabel ~= "Off"))
end
read("AUX9"); read("Off")
do
  local identity = Config.currentIdentity(); local crsf, push, _, sent = transport()
  assert(Config.request(identity, { owner = "test" }))
  Config.step({ identity = identity, crsf = crsf, push = push, now = 0 })
  assert(#sent == 0, "a completed snapshot must be reused without traffic")
  assert(Config.request(identity, { owner = "test", force = true }))
  Config.step({ identity = identity, crsf = crsf, push = push, now = 0 })
  assert(#sent == 1 and sent[1][1] == 0x28, "a connection-entry refresh must start a fresh read")
  Config.cancel("test", "test")
end
do
  Config.invalidate(nil); local crsf, push, _, sent = transport()
  assert(Config.request("timeout", { owner = "test" })); assert(not Config.acquire("diagnostics"))
  for i = 0, 5 do Config.step({ identity = "timeout", crsf = crsf, push = push, now = i }) end
  assert(#sent == Config.limits.pings and Config.snapshot("timeout").status == "unavailable")
end
do
  Config.invalidate(nil); local crsf, push, put, sent = transport()
  assert(Config.request("partial", { owner = "test" }))
  Config.step({ identity = "partial", crsf = crsf, push = push, now = 0 })
  put(0x29, info(48)); Config.step({ identity = "partial", crsf = crsf, push = push, now = 0.1 })
  Config.step({ identity = "partial", crsf = crsf, push = push, now = 0.2 })
  put(0x2B, field(1, "Packet Rate", { "250Hz" }, 0))
  Config.step({ identity = "partial", crsf = crsf, push = push, now = 0.3 })
  for i = 1, 60 do Config.step({ identity = "partial", crsf = crsf, push = push, now = i }) end
  local got = Config.snapshot("partial")
  assert(got.status == "ready" and got.reason == "partial_timeout" and got.packetRate == "250Hz")
  assert(#sent == Config.limits.sends)
  for i = 1, #sent do assert(sent[i][1] == 0x28 or sent[i][1] == 0x2C, "read-only provider emitted a write") end
end
do
  Config.invalidate(nil); local crsf, push, put = transport()
  assert(Config.request("old", { owner = "test" })); Config.step({ identity = "old", crsf = crsf, push = push, now = 0 })
  put(0x2B, field(1, "Packet Rate", { "250Hz" }, 0)); Config.cancel("test", "model_change")
  assert(Config.request("new", { owner = "test" })); Config.step({ identity = "new", crsf = crsf, push = push, now = 0.1 })
  Config.step({ identity = "new", crsf = crsf, push = push, now = 0.7 })
  assert(Config.snapshot("new").packetRate == nil)
end
print("elrs_config_test: ok")
