local root = (debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\]bin[/\\]tests[/\\]") or ".")
_G.rfsuite = {}
local currentFilename = "model01.yml"
model = {
  getInfo = function() return { filename = currentFilename, name = "Model", bitmap = "m.png" } end,
  getModule = function(i) return { Type = i == 0 and 5 or 0, subType = 0 } end,
}
loadScript = function(path)
  local relative = path:match("/SCRIPTS/TOOLS/rfsuite%-core/(.+)$")
  if not relative then return nil end
  return loadfile(root .. "/src/rfsuite/" .. relative)
end
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
  local q, sent, stats = {}, {}, { pops = 0 }
  local crsf = { popFrame = function(kind)
    stats.pops = stats.pops + 1
    if not q[kind] or #q[kind] == 0 then return nil end
    return table.remove(q[kind], 1)
  end }
  local function push(kind, payload) sent[#sent + 1] = { kind, payload }; return true end
  local function put(kind, value) q[kind] = q[kind] or {}; q[kind][#q[kind] + 1] = value end
  return crsf, push, put, sent, stats
end
local function drain(crsf)
  Config.drain({ crsf = crsf, now = 0 })
  Config.drain({ crsf = crsf, now = 0.6 })
end
local function read(dynamicLabel)
  Config.invalidate(nil)
  local crsf, push, put, sent = transport(); local identity = Config.currentIdentity()
  assert(Config.request(identity, { owner = "test" }))
  Config.step({ owner = "test", identity = identity, crsf = crsf, push = push, now = 0 })
  assert(#sent == 1 and sent[1][1] == 0x28, "ping sends=" .. tostring(#sent) .. " kind=" .. tostring(sent[1] and sent[1][1]))
  put(0x29, info(4)); Config.step({ owner = "test", identity = identity, crsf = crsf, push = push, now = 0.1 })
  local values = {
    field(1, "Packet Rate", { "D250", "500Hz" }, 1),
    field(2, "Telem Ratio", { "Std", "Race", "Off", "1:16" }, 1),
    field(3, "Max Power", { "25", "1000" }, 1, "mW"),
    field(4, "Dynamic", { "Off", "Dyn", "AUX9" }, dynamicLabel == "Off" and 0 or 2),
  }
  for i = 1, #values do
    Config.step({ owner = "test", identity = identity, crsf = crsf, push = push, now = i })
    put(0x2B, values[i]); Config.step({ owner = "test", identity = identity, crsf = crsf, push = push, now = i + 0.1 })
  end
  local got = Config.snapshot(identity)
  assert(got.status == "ready" and got.packetRate == "500Hz" and got.telemetryRatio == "Race")
  assert(got.maxPower == "1000" and got.fields.maxPower.milliwatts == 1000)
  assert(got.dynamic == dynamicLabel and got.fields.dynamic.enabled == (dynamicLabel ~= "Off"))
end
read("AUX9"); read("Off")
do
  local crsf, push, put, sent = transport()
  _G.rfsuite.require = function(path)
    if path == "lib/elrs_config.lua" then return Config end
    if path == "lib/crsf.lua" then return crsf end
    return nil
  end
  crossfireTelemetryPush = push
  local Audio = assert(loadfile(root .. "/src/rfsuite/lib/audio.lua"))()
  local function namedUpvalue(fn, wanted, seen)
    seen = seen or {}
    if seen[fn] then return nil end
    seen[fn] = true
    local index = 1
    while true do
      local name, value = debug.getupvalue(fn, index)
      if not name then return nil end
      if name == wanted then return value end
      if type(value) == "function" then
        local found = namedUpvalue(value, wanted, seen)
        if found then return found end
      end
      index = index + 1
    end
  end
  local audioRead = assert(namedUpvalue(Audio.process, "txPowerModuleRead"))
  local state = {}
  assert(audioRead(state, false, 0) == nil and sent[1][1] == 0x28,
    "audio accepted the previous ready snapshot instead of forcing a connection refresh")
  put(0x29, info(2)); assert(audioRead(state, false, 0.1) == nil)
  assert(audioRead(state, false, 0.2) == nil)
  put(0x2B, field(1, "Max Power", { "100", "1000" }, 1, "mW"))
  assert(audioRead(state, false, 0.3) == nil)
  assert(audioRead(state, false, 0.4) == nil)
  put(0x2B, field(2, "Dynamic", { "Off", "Dyn" }, 0))
  local result = audioRead(state, false, 0.5)
  assert(result and result.done and result.maxMilliwatts == 1000 and result.dynamic == false,
    "audio did not complete the forced refresh with an explicit Off result")
end
do
  local Power = assert(loadfile(root .. "/src/rfsuite/lib/elrs_power.lua"))()
  local crsf, push = transport(); local legacy = {}
  Power.step(legacy, crsf, push, 0)
  assert(legacy.done and legacy.maxMilliwatts == 1000 and legacy.dynamic == false)
  assert(Power.FRAME_BUDGET == Config.limits.sends)
end
do
  local identity = Config.currentIdentity(); local crsf, push, _, sent = transport()
  assert(Config.request(identity, { owner = "test" }))
  Config.step({ owner = "test", identity = identity, crsf = crsf, push = push, now = 0 })
  assert(#sent == 0, "a completed snapshot must be reused without traffic")
  assert(Config.request(identity, { owner = "test", force = true }))
  local refreshing = Config.step({ owner = "test", identity = identity, crsf = crsf, push = push, now = 0 })
  assert(refreshing.status == "reading" and refreshing.previous and refreshing.previous.status == "ready")
  assert(#sent == 1 and sent[1][1] == 0x28, "a connection-entry refresh must start a fresh read")
  local before = #sent
  local foreign = Config.step({ owner = "intruder", identity = identity, crsf = crsf, push = push, now = 1, allow = false })
  assert(foreign.status == "reading" and #sent == before, "a foreign owner changed the active transaction")
  Config.cancel("test", "test")
end
do
  Config.invalidate(nil); local crsf, push, _, sent = transport()
  drain(crsf)
  assert(Config.request("timeout", { owner = "test" })); assert(not Config.acquire("diagnostics"))
  for i = 0, 5 do Config.step({ owner = "test", identity = "timeout", crsf = crsf, push = push, now = i }) end
  assert(#sent == Config.limits.pings and Config.snapshot("timeout").status == "unavailable")
end
do
  Config.invalidate(nil); local crsf, push = transport(); drain(crsf)
  currentFilename = "model01.yml"
  local oldIdentity = Config.currentIdentity()
  assert(Config.request(oldIdentity, { owner = "audio", force = true }))
  Config.step({ owner = "audio", identity = oldIdentity, crsf = crsf, push = push, now = 0 })
  currentFilename = "model02.yml"
  local newIdentity = Config.currentIdentity()
  assert(newIdentity ~= oldIdentity and Config.request(newIdentity, { owner = "audio", force = true }))
  local switched = Config.snapshot(newIdentity)
  assert(switched.status == "reading" and switched.previous == nil, "model switch retained the old snapshot")
  Config.cancel("audio", "test_done")
  currentFilename = "model01.yml"
end
do
  Config.invalidate(nil); local crsf, push, put, sent = transport()
  drain(crsf)
  assert(Config.request("partial", { owner = "test" }))
  Config.step({ owner = "test", identity = "partial", crsf = crsf, push = push, now = 0 })
  put(0x29, info(48)); Config.step({ owner = "test", identity = "partial", crsf = crsf, push = push, now = 0.1 })
  Config.step({ owner = "test", identity = "partial", crsf = crsf, push = push, now = 0.2 })
  put(0x2B, field(1, "Packet Rate", { "250Hz" }, 0))
  Config.step({ owner = "test", identity = "partial", crsf = crsf, push = push, now = 0.3 })
  for i = 1, 60 do Config.step({ owner = "test", identity = "partial", crsf = crsf, push = push, now = i }) end
  local got = Config.snapshot("partial")
  assert(got.status == "ready" and got.reason == "partial_timeout" and got.packetRate == "250Hz")
  assert(#sent == Config.limits.sends)
  for i = 1, #sent do assert(sent[i][1] == 0x28 or sent[i][1] == 0x2C, "read-only provider emitted a write") end
end
do
  Config.invalidate(nil); local crsf, push, put = transport()
  drain(crsf)
  assert(Config.request("old", { owner = "test" })); Config.step({ owner = "test", identity = "old", crsf = crsf, push = push, now = 0 })
  put(0x2B, field(1, "Packet Rate", { "250Hz" }, 0)); Config.cancel("test", "model_change")
  assert(Config.request("new", { owner = "test" })); Config.step({ owner = "test", identity = "new", crsf = crsf, push = push, now = 0.1 })
  Config.step({ owner = "test", identity = "new", crsf = crsf, push = push, now = 0.7 })
  assert(Config.snapshot("new").packetRate == nil)
  Config.cancel("test", "test_done")
end
do
  Config.invalidate(nil); local crsf, _, put, _, stats = transport()
  drain(crsf)
  assert(Config.acquire("diagnostics")); Config.release("diagnostics", true)
  put(0x2B, field(1, "Packet Rate", { "stale" }, 0))
  assert(not Config.acquire("next"), "dirty diagnostic release bypassed quarantine")
  local before = stats.pops
  assert(not Config.drain({ crsf = crsf, now = 0.1 }))
  assert(stats.pops - before == Config.limits.pops, "drain exceeded its shared pop budget")
  assert(not Config.acquire("next"), "diagnostic acquired before the drain deadline")
  assert(Config.drain({ crsf = crsf, now = 0.7 }))
  assert(crsf.popFrame(0x2B) == nil and Config.acquire("next"))
  Config.release("next")
end
do
  Config.invalidate(nil); local crsf, push, put = transport()
  assert(Config.request("chunks", { owner = "test" }))
  Config.step({ owner = "test", identity = "chunks", crsf = crsf, push = push, now = 0 })
  put(0x29, info(1)); Config.step({ owner = "test", identity = "chunks", crsf = crsf, push = push, now = 0.1 })
  Config.step({ owner = "test", identity = "chunks", crsf = crsf, push = push, now = 0.2 })
  local whole = field(1, "Packet Rate", { "250Hz" }, 0)
  local first, second = { 0xEA, 0xEE, 1, 1 }, { 0xEA, 0xEE, 1, 0 }
  for i = 5, 12 do first[#first + 1] = whole[i] end
  for i = 13, #whole do second[#second + 1] = whole[i] end
  put(0x2B, first); Config.step({ owner = "test", identity = "chunks", crsf = crsf, push = push, now = 0.3 })
  put(0x2B, first); put(0x2B, second)
  Config.step({ owner = "test", identity = "chunks", crsf = crsf, push = push, now = 0.4 })
  local got = Config.snapshot("chunks")
  assert(got.status == "ready" and got.packetRate == "250Hz", "duplicate chunk was appended")
end
do
  Config.invalidate(nil); local crsf, push, put = transport()
  assert(Config.request("oversize", { owner = "test" }))
  Config.step({ owner = "test", identity = "oversize", crsf = crsf, push = push, now = 0 })
  put(0x29, info(1)); Config.step({ owner = "test", identity = "oversize", crsf = crsf, push = push, now = 0.1 })
  Config.step({ owner = "test", identity = "oversize", crsf = crsf, push = push, now = 0.2 })
  local huge = { 0xEA, 0xEE, 1, 0 }
  for i = 1, Config.limits.fieldBytes + 1 do huge[#huge + 1] = 65 end
  put(0x2B, huge); Config.step({ owner = "test", identity = "oversize", crsf = crsf, push = push, now = 0.3 })
  assert(Config.snapshot("oversize").status == "unavailable", "oversized field was retained")
end
print("elrs_config_test: ok")
