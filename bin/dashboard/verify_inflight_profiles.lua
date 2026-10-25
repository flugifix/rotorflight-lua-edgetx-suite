-- EdgeTX exposes string functions without a string-method metatable.
debug.getmetatable("").__index = nil
-- Real transaction/drive/store modules, deterministic FC and EdgeTX filesystem seams.
local checked, tick, peak = 0, 1000, 0
local function check(value, message) checked = checked + 1; assert(value, message) end
local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}; for k, v in pairs(t) do out[k] = copy(v) end; return out
end
local files, pending, sent, cache, apis = {}, {}, {}, {}, {}
local fc = {pid = 2, rate = 3, identity = "FC-A", uid = "UID-A", counts = {pid = 6, rate = 4}, data = {}}
local widget = {state = {armed = false, armedSeen = true, rpm = 0, governor = 0, fblConnected = true, tasksDone = true}}
local msp, queue = {}, {}
local adjF, adjV = 0, 0
local sounds, numbers = {}, {}
getTime = function() return tick end
getDateTime = function() return {year=2026, mon=10, day=24, hour=17, min=30, sec=0} end
loadScript = function(path)
  path = string.gsub(path, "%.[^./]+$", "") .. ".lua"
  if files[path] then return load(files[path], path, "t", {}) end
  local relative = string.gsub(path, "^/SCRIPTS/TOOLS/rfsuite%-core/", "src/rfsuite/")
  return loadfile(relative)
end
local originalIo = io
io = {
  open = function(path, mode)
    if mode == "r" and not files[path] then return nil end
    local f = {path = path, pos = 1}
    if mode == "w" then files[path] = "" end
    return f
  end,
  write = function(f, text) files[f.path] = files[f.path] .. text end,
  read = function(f, n)
    local text = string.sub(files[f.path], f.pos, f.pos + n - 1); f.pos = f.pos + #text
    return text ~= "" and text or nil
  end,
  close = function() end
}
del = function(path) files[path] = nil; return 0 end
rename = function(a, b) if files[b] or not files[a] then return 1 end; files[b], files[a] = files[a], nil; return 0 end
mkdir = function() return 0 end

_G.rfsuite = {session = {apiVersion = {12,0,10}, signature = fc.identity, mcu_id = fc.uid},
  preferences = {audio_events = {adjustment_events = true}}}
rfsuite.require = function(path)
  if path == "lib/log.lua" then return {wanted = function() return false end} end
  if path == "lib/audio.lua" then return {adjustmentAllowed = function() return true end,
    playEventFile = function(f) sounds[#sounds+1] = f end,
    playNumber = function(n) numbers[#numbers+1] = n end} end
  if path == "tasks/msp/runtime.lua" then return {getState = function() return msp end} end
  if path == "tasks/msp/cache.lua" then return {clear = function() end} end
  if string.find(path, "tasks/msp/api/", 1, true) and apis[path] then return apis[path] end
  if not cache[path] then cache[path] = assert(loadfile("src/rfsuite/" .. path))() end
  return cache[path]
end
local Functions = rfsuite.require("widgets/dashboard/inflight/functions.lua")
local Drive = rfsuite.require("widgets/dashboard/inflight/drive.lua")
local Profiles = rfsuite.require("widgets/dashboard/inflight/profiles.lua")
local Store = rfsuite.require("widgets/dashboard/inflight/baseline.lua")
local Prime = rfsuite.require("widgets/dashboard/inflight/prime.lua")
-- The overlay offers cells only after the ground read; every drive here starts from a read board.
local readBoard = dofile("bin/dashboard/inflight_board_fixture.lua")(rfsuite.require)
do
  local newDrive = Drive.newDrive
  Drive.newDrive = function(...) return readBoard(newDrive(...)) end
end
local radio = {now = function() return tick end, clock = function() return "17:30" end,
  sensor = function(name)
    if name == "PID#" then return fc.pid elseif name == "RTE#" then return fc.rate
    elseif name == "AdjF" then return adjF elseif name == "AdjV" then return adjV end
  end,
  switchValue = function() return true end, flightMode = function() return 0 end,
  channelUs = function() return 998 end, setGlobalVariable = function() return true end}
local function makeDrive(records)
  local d = Drive.newDrive(radio, Drive.settings({inflight={enabled=true,switch=1}}, {inflight={enabled=true}}))
  d.prime = {records = records or {}, phase = "done", pending={}, pendingHead=1, pendingTail=0}
  d.board, d.phase, d.live = fc.identity, "ground", true
  d:watchProfiles(); return d
end
local function status()
  return {current_pid_profile_index = fc.pid-1, current_control_rate_profile_index = fc.rate-1,
    pid_profile_count=fc.counts.pid, control_rate_profile_count=fc.counts.rate}
end
apis["tasks/msp/api/status.lua"] = {parse = function(buf) return buf[1] end, simulatorResponse={}}
local setters = {}
for _, kind in ipairs({"pid","rate","global"}) do
  for _, command in ipairs(Profiles.COMMANDS[kind]) do
    local name, fields = Functions.fieldsForCommand(command)
    local module = {command = command, writeCommand=command+1000, simulatorResponse={},
      parse=function(buf) return copy(buf[1]) end, buildWritePayload=function(data) return {copy(data)} end}
    apis["tasks/msp/api/"..name..".lua"], setters[module.writeCommand] = module, command
    for index = 1, kind == "global" and 1 or 6 do
      local data = {untouched = 900 + index}
      for _, fn in ipairs(fields) do if Profiles.tracked(fn) then data[fn.field] = math.max(fn.min, math.min(fn.max, 50+index)) end end
      fc.data[kind..index] = fc.data[kind..index] or {}
      fc.data[kind..index][command] = data
    end
  end
end
function queue:add(request)
  check(not widget.state.armed and widget.state.armedSeen and widget.state.rpm < 500 and widget.state.governor < 4
    and not msp.lastArmed, "no MSP may be queued while armed/rotating/unknown")
  if request.client=="inflight-profiles" and request.command==210 then
    check(rfsuite.inflightProfileJob~=nil, "every temporary and cleanup selection holds shared announcement suppression")
  end
  pending[#pending+1] = request
end
function queue:clear(client)
  for i=#pending,1,-1 do
    if pending[i].client == client then local r=table.remove(pending,i); r.errorHandler(nil,"cleared") end
  end
end
msp = {lastArmed=false, values={mcuId=fc.uid}, signatureMcuId=fc.uid, queue=queue}
local replyMutation, slotsForPrime, idsForPrime
local function reply(failure)
  local r=table.remove(pending,1); if not r then return end
  sent[#sent+1] = {command=r.command, payload=copy(r.payload), pid=fc.pid, rate=fc.rate}
  if failure then r.errorHandler(nil,failure); return r end
  if replyMutation then replyMutation(r) end
  if r.command == 210 then
    check(r.isWrite and #r.payload == 1, "select is a one-byte mutation")
    if (r.payload[1] & 0x80) ~= 0 then fc.rate=(r.payload[1]&0x7f)+1 else fc.pid=r.payload[1]+1 end
    r.processReply(nil,{})
  elseif r.command == 64 then r.processReply(nil,{{}})
  elseif r.command == 167 then r.processReply(nil,{{adjustment_function_ids=idsForPrime or {2,2,1}}})
  elseif r.command == 156 then r.processReply(nil,{{adjustment_range=copy(slotsForPrime[r.payload[1]+1])}})
  elseif r.command == 101 then r.processReply(nil,{status()})
  elseif r.command == 250 then
    check(r.isWrite, "EEPROM is explicitly a write")
    fc.persisted={pid=fc.pid,rate=fc.rate,data=copy(fc.data)}
    if fc.channel then fc.pid,fc.rate=fc.channel.pid,fc.channel.rate end
    r.processReply(nil,{})
  else
    local command=setters[r.command] or r.command
    local _, fields=Functions.fieldsForCommand(command)
    local kind=Functions.scopeOf(fields[1].id) or "global"
    local index=kind=="pid" and fc.pid or kind=="rate" and fc.rate or 1
    if setters[r.command] then fc.data[kind..index][command]=copy(r.payload[1]); r.processReply(nil,{})
    else r.processReply(nil,{copy(fc.data[kind..index][command])}) end
  end
  return r
end
local function pass(d, failure)
  reply(failure)
  tick=tick+10
  local before=d.prime.done or 0
  local instructions = 0
  debug.sethook(function() instructions = instructions + 1 end, "", 1)
  Prime.tick(widget,d)
  debug.sethook()
  peak = math.max(peak, instructions)
  check((d.prime.done or 0)-before <= 1, "at most one reply parsed per pass")
end
local function finish(d)
  for _=1,2000 do
    pass(d)
    if not Profiles.busy(d) then
      check(rfsuite.inflightProfileJob==nil, "completed and failed jobs clear the shared announcement flag")
      return
    end
  end
  error("transaction did not terminate")
end
local slots = {{adjFunction=2,adjMin=1,adjMax=3,adjStep=0},{adjFunction=2,adjMin=5,adjMax=9,adjStep=0},
  {adjFunction=1,adjMin=-4,adjMax=2,adjStep=0}}
local reachable=assert(Profiles.reachable(slots,status()))
check(reachable.pid[1] and reachable.pid[3] and reachable.pid[5] and reachable.pid[6] and not reachable.pid[4], "union of two PID slots")
check(reachable.rate[1] and reachable.rate[2] and reachable.rate[3] and not reachable.rate[4], "clamps plus current rate")
local only=assert(Profiles.reachable({},status()))
check(only.pid[2] and not only.pid[1] and only.rate[3] and not only.rate[2], "no selectors means active pair only")
check(Profiles.selection("pid",3)==2 and Profiles.selection("rate",4)==0x83, "firmware bit-7 encoding")
check(not Profiles.reachable({}, {pid_profile_count=0}), "unknown counts fail closed")

local d=makeDrive(slots)
check(Prime.refreshValues(widget,d), "full profile read starts")
local old=d.values
for _=1,20 do pass(d); check(d.values==old, "partial read remains private") end
finish(d)
check(d.prime.phase=="done" and fc.pid==2 and fc.rate==3, "success restores original pair before publication")
check(d.sessionProfiles.pid[6] and d.profileValues.pid[6][14] and d.profileValues.rate[1][5], "every reachable profile cached")
local globalReads=0
for _,r in ipairs(sent) do if r.command==142 then globalReads=globalReads+1 end end
check(globalReads==1, "global values read exactly once")
local data=assert(Store.load(fc.uid,fc.identity))
check(Profiles.complete(data) and data.meta.timestamp=="2026-10-24 17:30:00", "SD round trip and timestamp")
local _,why=Store.load(fc.uid,"FC-B"); check(why=="baseline_identity", "FC identity refuses wrong baseline")
local savedFile=files[Store.path(fc.uid)]
files[Store.path(fc.uid)]=nil
local tempPath=string.gsub(Store.path(fc.uid), "%.lua$", ".tmp.lua")
files[tempPath]=savedFile
check(Store.load(fc.uid,fc.identity)~=nil, "interrupted promotion loads the Lua-suffixed temporary file")
files[tempPath]=nil
files[Store.path(fc.uid)..".tmp"]=savedFile
check(loadScript(Store.path(fc.uid)..".tmp")==nil, "EdgeTX stem rule rejects the old lua.tmp name")
files[Store.path(fc.uid)..".tmp"]=nil
files[Store.path(fc.uid)]=savedFile
local function aborted(reason, armed)
  local instance=makeDrive(slots)
  check(Prime.refreshValues(widget,instance), "interrupted read starts")
  while fc.pid==2 do pass(instance) end
  if armed then
    widget.state.armed=true
    local count=#sent
    Prime.tick(widget,instance)
    check(instance.restorePending and instance.profileBusy, "arming defers original pair return")
    for _=1,3 do Prime.tick(widget,instance) end
    check(#sent==count, "armed deferred job sends no MSP")
    widget.state.armed=false
  elseif reason=="no_link" then
    widget.state.fblConnected=false; Prime.tick(widget,instance)
    check(instance.restorePending, "link loss retains return pair")
    widget.state.fblConnected=true
  elseif reason=="cancelled" then
    instance:endSession()
    check(rfsuite.inflightProfileJob==nil, "ground close clears shared suppression before deferred cleanup")
  else
    while #pending == 0 do pass(instance) end
    pass(instance,reason)
  end
  finish(instance)
  check(fc.pid==2 and fc.rate==3 and not instance.sessionProfiles, "abort restores original pair without publishing")
  check(files[Store.path(fc.uid)]==savedFile, "aborted session preserves SD baseline")
end
aborted("timeout",false); aborted("MSP error",false); aborted(nil,true); aborted("no_link",false)
aborted("cancelled",false)

-- The same arm guard includes both independent rotor witnesses and missing ARM telemetry.
for _,witness in ipairs({"armedSeen","rpm","governor"}) do
  local prior=widget.state[witness]
  if witness=="armedSeen" then widget.state[witness]=false
  elseif witness=="rpm" then widget.state[witness]=600 else widget.state[witness]=4 end
  local instance=makeDrive(slots)
  check(not Prime.refreshValues(widget,instance), "ground read refuses unsafe witness: "..witness)
  widget.state[witness]=prior
end

msp.lastArmed=true
check(not Prime.refreshValues(widget,makeDrive(slots)), "MSP runtime arm witness independently refuses reads")
msp.lastArmed=false
local legacy=Drive.settings({inflight={enabled=true,switch=1}}, {inflight={enabled=true,backup_profile=6}})
check(legacy.backup_profile==nil and legacy.active,"legacy spare-slot setting is ignored harmlessly")

-- Attribution changes ownership, never the baseline or layout epoch. A held report is fenced.
d.phase="live"; d.live=true; d.reportFence=nil
adjF,adjV=14,101; tick=tick+1; d:fastTick(tick)
check(d.profileValues.pid[2][14]==101, "PID report attributed to current PID")
local epoch=d.valueEpoch
fc.pid=3; tick=tick+1; d:fastTick(tick)
check(d.profileValues.pid[3][14]~=101 and d.reportFence and d.written==0, "held report cannot cross profiles")
local ok,reason=d:dispatch("step",1,"touch"); check(not ok and reason=="report_sync", "held report also refuses a new step")
adjF=0; tick=tick+1; d:fastTick(tick)
adjF,adjV=14,102; tick=tick+1; d:fastTick(tick)
check(d.profileValues.pid[3][14]==102 and d.valueEpoch==epoch, "new-profile report updates without scene epoch")
fc.rate=1; adjF=0; tick=tick+1; d:fastTick(tick)
adjF,adjV=5,99; tick=tick+1; d:fastTick(tick)
check(d.profileValues.rate[1][5]==99 and d.profileValues.rate[3][5]~=99, "rate report attributed separately")
adjF,adjV=64,-12; tick=tick+1; d:fastTick(tick)
check(d.profileValues.global[64]==-12, "global report has one owner")
fc.pid=4; tick=tick+1; d:fastTick(tick)
ok,reason=d:dispatch("step",1,"touch"); check(not ok and reason=="pid_unread" and sounds[#sounds]=="inflight/paused.wav", "unread profile refuses with paused cue")
fc.pid=3; adjF=0; tick=tick+1; d:fastTick(tick)
check(not d.profilePaused and d:tuning() and sounds[#sounds]=="inflight/resumed.wav", "return resumes without an interlock cycle")
check(#numbers>0, "profile cue uses number teller")
local list=Prime.delta(d)
check(#list==4 and list[1].profile==2 and list[2].profile==3 and list[3].scope=="rate" and list[4].scope=="global", "delta grouped by profile then group")
check(list[1].difference==101-data.pid2["14"] and Prime.delta(d)==list, "signed delta and cached list")

-- Restore reads full records, changes tracked fields only, commits, verifies, returns pair.
d.phase="post"; fc.pid,fc.rate=2,3; adjF=0; d:watchProfiles()
fc.data.pid3[112].pid_1_P=123
fc.data.pid3[112].untouched=777
sent={}
fc.channel={pid=2,rate=3}
check(Prime.restore(widget,d,{kind="pid",index=3}), "single profile restore starts")
finish(d)
check(d.transfer.state=="ok" and d.transfer.results.pid3=="ok", "per-profile verified result")
check(d.transfer.verification.pid3.ram and d.transfer.verification.pid3.saved
  and d.transfer.verification.pid3.readBack, "single target reports both RAM and saved read-back witnesses")
check(fc.data.pid3[112].pid_1_P==data.pid3["14"] and fc.data.pid3[112].untouched==777, "only tracked fields restored")
check(fc.pid==2 and fc.rate==3, "restore returns active pair")
local writes,eeprom=0,0
for _,r in ipairs(sent) do
  if setters[r.command] then writes=writes+1; check(r.pid==3, "single-profile writes only its target") end
  if r.command==250 then eeprom=eeprom+1 end
end
check(writes==4 and eeprom==1 and fc.persisted.pid==2 and fc.persisted.rate==3, "matching set commands, one EEPROM and persisted return pair")
sent={}
check(Prime.restore(widget,d), "restore all starts"); finish(d)
local saves, savedAt = 0, 0
for i,r in ipairs(sent) do
  if r.command==250 then saves=saves+1; savedAt=i end
end
check(saves==1, "all profiles share exactly one EEPROM write despite channel snap-back")
for i,r in ipairs(sent) do
  if setters[r.command] then check(i<savedAt, "all parameter writes precede the single save") end
end
for name,records in pairs(fc.persisted.data) do
  for command,record in pairs(records) do
    check(record.untouched==fc.data[name][command].untouched, "persistence witness preserves untracked fields")
    local baseline=data[name=="global1" and "global" or name]
    local _,fields=Functions.fieldsForCommand(command)
    for _,fn in ipairs(fields) do
      if baseline and Profiles.tracked(fn) and baseline[tostring(fn.id)]~=nil then
        check(record[fn.field]==baseline[tostring(fn.id)], "single save contains each restored baseline field")
      end
    end
  end
end
check(d.transfer.state=="ok" and d.transfer.results.pid6=="ok" and d.transfer.results.rate1=="ok"
  and d.transfer.results.global=="ok" and fc.pid==2 and fc.rate==3 and #Prime.delta(d)==0, "restore all scopes verified, delta cleared and original pair returned")
for name,result in pairs(d.transfer.results) do
  local witness=d.transfer.verification[name]
  check(result=="ok" and witness.ram and witness.saved and witness.readBack,
    "every restored target retains separate RAM/save/read-back evidence")
end
local broken=copy(data); broken.pid3=nil
files[Store.path(fc.uid)]="return ".."{}"
local count=#sent
check(not Prime.restore(widget,d) and #sent==count, "incomplete baseline refuses before MSP")
files[Store.path(fc.uid)]=string.gsub(savedFile, "FC%-A","FC-B")
check(not Prime.restore(widget,d) and d.transfer.reason=="baseline_identity" and #sent==count, "foreign baseline restore refuses before MSP")
files[Store.path(fc.uid)]=savedFile

-- A capability change without an API bump requires a new complete session baseline.
files[Store.path(fc.uid)]=string.gsub(savedFile, '%["masterGains"%]=true', '["masterGains"]=false')
sent={}
check(Prime.restore(widget,d,{kind="pid",index=3}), "legacy-capability baseline reaches ground capability check")
finish(d)
local parameterWrites=0
for _,r in ipairs(sent) do if setters[r.command] then parameterWrites=parameterWrites+1 end end
check(d.transfer.reason=="baseline_incomplete" and parameterWrites==0 and fc.pid==2 and fc.rate==3,
  "new optional fields refuse before any target record is overwritten")
files[Store.path(fc.uid)]=savedFile

-- A truncated baseline with valid identity must finish refusal before its first MSP.
files[Store.path(fc.uid)]=string.gsub(savedFile, '%["14"%]=%d+,\n', '')
count=#sent
check(Prime.restore(widget,d), "identity-valid incomplete baseline enters sliced validation")
finish(d)
check(d.transfer.reason=="baseline_incomplete" and #sent==count, "missing fields refuse before select/read/write")
files[Store.path(fc.uid)]=savedFile

-- Read-back disagreement records a failure and still returns the originally active pair.
local committed=false
replyMutation=function(r)
  if r.command==250 then committed=true end
  if committed and r.command==112 then fc.data.pid3[112].untouched=778 end
end
check(Prime.restore(widget,d,{kind="pid",index=3}), "verification-failure restore starts")
finish(d); replyMutation=nil
check(d.transfer.reason=="verify_failed" and d.transfer.results.pid3=="verify_failed"
  and fc.pid==2 and fc.rate==3 and d.prime.phase=="done", "read-back failure is per-target, returns pair and cannot trigger an automatic prime retry")
check(d.transfer.verification.pid3.ram and d.transfer.verification.pid3.saved
  and not d.transfer.verification.pid3.readBack, "failed saved read-back retains the earlier RAM and save witnesses")

-- An uncertain save must never be repeated automatically during return recovery.
sent={}
check(Prime.restore(widget,d,{kind="pid",index=3}), "uncertain-save restore starts")
while not (pending[1] and pending[1].command==250) do pass(d) end
pass(d,"timeout")
check(d.profileJob.returnBlocked and d.profileJob.results.pid3=="ram_ok",
  "save timeout reports RAM verification without claiming persistence")
check(Prime.retryReturn(d), "uncertain-save return requires an explicit recovery")
finish(d)
local uncertainSaves=0
for _,r in ipairs(sent) do if r.command==250 then uncertainSaves=uncertainSaves+1 end end
check(uncertainSaves==1 and not d.transfer.verification.pid3.saved
  and not d.transfer.verification.pid3.readBack, "return recovery issues no second save and retains the uncertainty")

-- Arming interrupts a restore without letting a pending read continue into its writes.
check(Prime.restore(widget,d,{kind="pid",index=3}), "armed-abort restore starts")
while fc.pid==2 do pass(d) end
widget.state.armed=true; count=#sent; Prime.tick(widget,d)
check(d.restorePending and #sent==count, "restore arming retains original pair and sends nothing")
check(rfsuite.inflightProfileJob==nil, "armed suspension clears the announcement flag")
widget.state.armed=false; finish(d)
check(d.transfer.reason=="armed" and fc.pid==2 and fc.rate==3, "restore abort returns pair on disarm")

-- A failed return cannot be replaced. Its explicit retry is a state transition, not a sleep.
check(Prime.restore(widget,d,{kind="pid",index=3}), "return-failure restore starts")
while not (d.profileJob.returning and #pending>0) do pass(d) end
pass(d,"timeout")
check(d.restorePending and d.profileJob.returnBlocked, "return timeout remains visibly pending")
check(not Prime.start(widget,d) and not Prime.restore(widget,d), "new operations cannot replace pending return")
count=#sent; for _=1,3 do Prime.tick(widget,d) end
check(#sent==count, "no repeated timeout attempts without an explicit retry or reconnect")
check(Prime.retryReturn(d), "explicit read-again requests pending return")
finish(d)
check(fc.pid==2 and fc.rate==3 and not d.restorePending, "explicit return retry restores original pair")

-- The full slot-table prime reuses a matching SD baseline after reconnect.
for _, name in ipairs({"rx_map","get_adjustment_function_ids","get_adjustment_range"}) do
  apis["tasks/msp/api/"..name..".lua"]={parse=function(buf) return copy(buf[1]) end, simulatorResponse={}}
end
-- The board carries the three profile selectors and, after them, the standard set: what the
-- overlay may tune is derived from these slots.
slotsForPrime, idsForPrime = {}, {2,2,1}
for i, slot in ipairs(slots) do slotsForPrime[i] = slot end
do
  local probe = makeDrive()
  local ena = Functions.wireToAuxField(probe.settings.bank_ch, {})
  local adj = Functions.wireToAuxField(probe.settings.value_ch, {})
  for _, slot in ipairs(Functions.standardSlots(ena, adj, {step = 5, step_headspeed = 50})) do
    slotsForPrime[#slotsForPrime + 1] = slot.record
    idsForPrime[#idsForPrime + 1] = slot.record.adjFunction
  end
end
local reconnected=makeDrive()
check(Prime.start(widget,reconnected,true), "automatic full prime starts after restart")
for _=1,3000 do
  pass(reconnected)
  if not Prime.isRunning(reconnected) then break end
end
check(reconnected.prime.phase=="done" and reconnected.sessionProfiles.pid[6]
  and files[Store.path(fc.uid)]==savedFile, "full prime resumes persisted membership without replacing start values")
check(fc.pid==2 and fc.rate==3, "reconnect prime returns initial pair")

-- Disk-write failure is detected by read-back; the previous complete baseline is untouched.
local realWrite=io.write
local work=assert(Store.begin(fc.uid,data))
io.write=function() end
local done,why
for _=1,1000 do done,why=Store.step(work); if done then break end end
io.write=realWrite
check(done and why=="baseline_io" and files[Store.path(fc.uid)]==savedFile, "incomplete temp cannot replace baseline")

-- The model-preferences directory listing excludes the dotted snapshot suffix.
local Preferences=rfsuite.require("lib/model_preferences.lua")
dir=function() local entries={"UID-A.lua","UID-A.inflight.lua","UID-A.inflight.tmp.lua"}; local i=0
  return function() i=i+1; return entries[i] end end
local models=Preferences.listKnownModelIds()
check(#models==1 and models[1].mcuId=="UID-A", "SD baseline is not enumerated as a model preference store")

-- Actual API serializers preserve the untracked fields in current command records.
for _,kind in ipairs({"pid","rate","global"}) do
  for _,command in ipairs(Profiles.COMMANDS[kind]) do
    local name,fields=Functions.fieldsForCommand(command)
    local module=assert(loadfile("src/rfsuite/tasks/msp/api/"..name..".lua"))()
    local parsed=assert(module.parse(module.simulatorResponse))
    local expected=copy(parsed)
    for _,fn in ipairs(fields) do if Profiles.tracked(fn) and parsed[fn.field]~=nil then expected[fn.field]=fn.min end end
    local payload=module.buildWritePayload(expected)
    local actual=assert(module.parse(payload))
    for field,value in pairs(expected) do check(actual[field]==value, "real API field roundtrip: "..name.."."..field) end
    if command==94 then
      local extended=copy(module.simulatorResponse)
      if parsed.error_decay_gain_cyclic==nil then extended[#extended+1]=0 end
      extended[#extended+1],extended[#extended+2]=100,101
      local modern=assert(module.parse(extended))
      check(modern.cyclic_master_gain==100 and modern.yaw_master_gain==101,"reply length declares optional master gains")
      modern.cyclic_master_gain,modern.yaw_master_gain=125,126
      local actualModern=assert(module.parse(module.buildWritePayload(modern)))
      check(actualModern.cyclic_master_gain==125 and actualModern.yaw_master_gain==126,"modern optional tracked fields survive real write API")
    end
  end
end
-- Restore confirmation names targets and sends nothing until the second, explicit press.
SMLSIZE,MIDSIZE,DBLSIZE,XXLSIZE=1,2,3,4
BLACK,WHITE,BLUE,RED,GREEN,YELLOW=0,1,2,3,4,5
LEFT,RIGHT,CENTER=0,1,2
lvgl={}
local Screen=rfsuite.require("widgets/dashboard/inflight/screen.lua")
for _,size in ipairs({{480,272},{480,320},{800,480}}) do
  local view={_inflight=reconnected,zone={w=size[1],h=size[2]},state=widget.state}
  local nodes={}
  reconnected.restoreConfirm={all=true}; reconnected.restoreResultOpen=nil
  view.state.inflight={phase="ground",live=true,profile=2,rateProfile=3,profileText="TUNING PID 2 / RTE 3"}
  Screen.buildFullscreen(nodes,view)
  local names,confirmButton={}
  for _,node in ipairs(nodes) do
    if node.type=="label" and type(node.text)=="string" then names[#names+1]=node.text end
    if node.type=="button" and node.press and not confirmButton then confirmButton=node end
    check((node.y or 0)+(node.h or 0)<=size[2], "restore confirmation fits height")
  end
  check(string.find(table.concat(names," "), "PID 6",1,true) and string.find(table.concat(names," "), "RTE 3",1,true), "confirmation names baseline profiles")
  check(not reconnected.profileJob and #pending==0, "opening confirmation sends no MSP")
  check(confirmButton~=nil,"confirmation has an explicit restore control")
  confirmButton.press()
  check(reconnected.profileJob and reconnected.profileJob.target==nil,"confirmed restore-all targets every profile")
  finish(reconnected)
  reconnected.restoreResultOpen=1; nodes={}; Screen.buildFullscreen(nodes,view)
  local resultRows=0
  for _,node in ipairs(nodes) do
    if type(node.text)=="string" and string.find(node.text, "Restored and verified",1,true) then resultRows=resultRows+1 end
    check((node.y or 0)+(node.h or 0)<=size[2], "paged restore results fit height")
  end
  check(resultRows>0,"per-profile results appear on the result surface")
end
reconnected.restoreConfirm=nil; reconnected.restoreResultOpen=nil
local deferredView={_inflight=reconnected,zone={w=480,h=320},state={inflight={phase="live",live=true,
  profileRefusal="profile_reading",restorePending=true,groupRows={},groups={}}}}
local deferredNodes={}; Screen.buildFullscreen(deferredNodes,deferredView)
local saysDisarm=false
for _,node in ipairs(deferredNodes) do
  if node.text=="Disarm to return to original profiles" then saysDisarm=true end
end
check(saysDisarm,"armed read-abort surface explicitly says original-profile return awaits disarm")

-- Comparison follows the active scope's SD baseline, including a zero start value.
fc.pid,fc.rate,adjF=2,3,0
reconnected.live,reconnected.phase=true,"live"
reconnected:watchProfiles()
local base2,base3=reconnected.baseline.pid2["14"],reconnected.baseline.pid3["14"]
reconnected.profileValues.pid[2][14]=base2+2
reconnected.profileValues.pid[3][14]=base3-1
reconnected:activateProfiles()
local comparisonView={_inflight=reconnected,state={armed=true},zone={w=480,h=272}}
tick=tick+1; Drive.sample(comparisonView)
reconnected.bank,reconnected.row=1,1
-- Select the actual cell rather than relying on a standard-set address.
for bank,rows in pairs(reconnected.set) do for row,id in pairs(rows) do
  if id==14 then reconnected.bank,reconnected.row=bank,row end
end end
reconnected.valueEpoch=reconnected.valueEpoch+1
tick=tick+1; Drive.sample(comparisonView)
check(comparisonView.state.inflight.activeComparison=="Start "..base2.." / +2","PID 2 comparison uses its baseline")
fc.pid=3; tick=tick+1; Drive.sample(comparisonView)
check(comparisonView.state.inflight.activeComparison=="Start "..base3.." / -1","PID switch changes baseline and current together")
reconnected.primedValues[14]=0; reconnected.values[14]=2
reconnected.reportEpoch=reconnected.reportEpoch+1
tick=tick+1; Drive.sample(comparisonView)
check(comparisonView.state.inflight.activeComparison=="Start 0 / +2","zero baseline is known")

-- Every changed parameter remains reachable, and each page repeats its profile/group context.
reconnected.phase="post"
reconnected.changes={pid={[2]={[14]=true,[15]=true,[18]=true},[3]={[14]=true}},rate={[3]={[5]=true}},global={}}
for _,id in ipairs({14,15,18}) do reconnected.profileValues.pid[2][id]=reconnected.baseline.pid2[tostring(id)]+2 end
reconnected.profileValues.rate[3][5]=reconnected.baseline.rate3["5"]+1
reconnected.valueEpoch=reconnected.valueEpoch+1
local expectedChanges=Prime.delta(reconnected)
for _,size in ipairs({{480,272},{480,320},{800,480}}) do
  local view={_inflight=reconnected,zone={w=size[1],h=size[2]},state={inflight={phase="post",live=true}}}
  local seen,rateNotice={},false
  reconnected.deltaPage=1
  local page,pages=1,1
  repeat
    reconnected.deltaPage=page
    local nodes={}; Screen.buildFullscreen(nodes,view); pages=reconnected.deltaPages
    local heading,entryButton
    for _,node in ipairs(nodes) do
      check((node.y or 0)+(node.h or 0)<=size[2],"post-flight top-level geometry fits")
      if node.type=="label" and type(node.text)=="string" then
        if string.find(node.text, " / ",1,true) and (string.find(node.text, "PID ",1,true)==1 or string.find(node.text, "Rate ",1,true)==1) then heading=node.text end
        if node.text=="PID restore does not cover rate profiles" then rateNotice=true end
        if string.find(node.text, " -> ",1,true) then check(heading~=nil,"delta row has a repeated profile/group heading"); seen[#seen+1]=node.text end
      end
      if node.type=="button" and not entryButton then entryButton=node end
    end
    check(entryButton~=nil,"post-flight has an action entry")
    local sentBefore=#sent
    entryButton.press()
    check(#sent==sentBefore and reconnected.postActionsOpen,"opening restore menu sends no MSP")
    local menu={}; Screen.buildFullscreen(menu,view)
    local buttons={}
    for _,node in ipairs(menu) do
      check((node.y or 0)+(node.h or 0)<=size[2],"restore-menu geometry fits")
      if node.type=="button" then buttons[#buttons+1]=node end
    end
    check(#buttons>=4,"restore menu retains all/read/profile/back actions")
    buttons[4].press()
    check(not reconnected.postActionsOpen and #sent==sentBefore,"back preserves the list without MSP")
    page=page+1
  until page>pages
  check(#seen==#expectedChanges and rateNotice,"paging covers every change and explains rate restore scope: "..#seen.."/"..#expectedChanges.." rate="..tostring(rateNotice))
end
for _,size in ipairs({{480,272},{480,320},{800,480}}) do
  for _,mode in ipairs({"read","restore"}) do
    local job={at=1,plan={{op="read",kind="pid",index=2}}}
    reconnected.profileJob=job
    reconnected.transfer=mode=="restore" and {state="busy",kind="restore"} or nil
    local view={_inflight=reconnected,state={inflight={phase="post"}},zone={w=size[1],h=size[2]}}
    local nodes={}; Screen.buildFullscreen(nodes,view)
    local visible,progress=0
    for _,node in ipairs(nodes) do
      local shown = node.visible == nil or (type(node.visible)=="function" and node.visible())
      if node.type=="button" and shown then visible=visible+1 end
      if node.type=="label" and type(node.text)=="function" and string.find(node.text(),"PID profile 2",1,true) then progress=node.text end
      check((node.y or 0)+(node.h or 0)<=size[2],"busy surface fits height")
    end
    -- Close always; Cancel only while a read is reading.
    check(visible==(mode=="read" and 2 or 1) and progress,"busy read/restore shows the current target, close and the cancel a read allows")
    job.plan[1].index=3
    check(string.find(progress(),"PID profile 3",1,true),"job target updates without rebuilding the busy scene")
    job.returnBlocked,job.error=true,"timeout"
    nodes={}; Screen.buildFullscreen(nodes,view)
    local retry
    for _,node in ipairs(nodes) do if node.type=="button" and node.active and node.active() then retry=node end end
    check(retry and retry.active(),"blocked return retains an explicit recovery action on the busy surface")
    local sentBefore=#sent
    retry.press()
    check(not job.returnBlocked and not retry.active() and #sent==sentBefore,
      "explicit recovery changes only return state and disables itself without sending MSP")
    reconnected.profileJob=nil
  end
end
reconnected.postActionsOpen={kind="pid",index=2}
reconnected:setPhase("live")
check(not reconnected.postActionsOpen,"arming cannot retain a post-flight restore menu")
reconnected.postActionsOpen={kind="pid",index=2}
reconnected:endSession()
check(not reconnected.postActionsOpen,"ending a session dismisses its post-flight actions")
print("sliced profile-job peak: "..peak.." VM instructions (transaction fixture, not a native full pass)")
io=originalIo
print(checked.." profile transaction, SD, attribution, restoration and API checks passed")
