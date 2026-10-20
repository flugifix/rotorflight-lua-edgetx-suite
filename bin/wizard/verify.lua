-- Offline protocol, lifecycle and per-call budget regression checks. No simulator.
local ROOT = "src/rfsuite/"
local BASE = "/SCRIPTS/TOOLS/rfsuite-core/"
local PATH = "app/pages/helicopter_setup/"
local ticks, assertions, failures, worst = 100, 0, 0, {}
local function check(ok, name)
  assertions = assertions + 1
  if not ok then failures = failures + 1; print("FAIL " .. name) end
end
local function eq(a,b,name) check(a == b, name .. " (" .. tostring(a) .. "/" .. tostring(b) .. ")") end
local function load(path) return assert(loadfile(ROOT .. path))() end
function getTime() return ticks end
COLOR_THEME_PRIMARY1, COLOR_THEME_PRIMARY3, COLOR_THEME_SECONDARY1 = 1, 3, 4
SMLSIZE, MIDSIZE = 0, 1
LCD_W, LCD_H = 480, 272
local armed = false
_G.rfsuite = { session = { fblConnected = true, mcu_id = "test-board", apiVersion = "12.10" } }
local q = { messages = {}, sent = {}, pending = nil }
function q:add(m) self.messages[#self.messages + 1] = m end
function q:clear(client)
  local keep = {}
  for _, m in ipairs(self.messages) do
    if m.client ~= client then keep[#keep + 1] = m elseif m.errorHandler then m.errorHandler(m, "cleared") end
  end
  self.messages = keep
end
local runtime = { getState = function() return { queue = q } end, armedReading = function() return armed, true end }
local originalLoadScript
function loadScript(path)
  local relative = string.sub(path, #BASE + 1)
  if relative == "tasks/msp/runtime.lua" then return function() return runtime end end
  if relative == "lib/armed.lua" then return function() return { changeCount = function() return 0 end } end end
  return loadfile(ROOT .. relative)
end
local function u16(p,v) p[#p+1],p[#p+2] = v & 255,(v >> 8) & 255 end
local modules = {}
local function api(name) if not modules[name] then modules[name] = load("tasks/msp/api/" .. name .. ".lua") end; return modules[name] end
local lockDisabled = true
local function status()
  local values = { sensor_status = 3, pid_profile_count = 3, control_rate_profile_count = 3,
    motor_count = 2, servo_count = 4, current_pid_profile_index = 1, current_control_rate_profile_index = 2,
    arming_disable_flags = lockDisabled and (1 << 16) or 0 }
  local p = {}
  for _, f in ipairs(api("status").fields) do
    local n = f[2] == "U32" and 4 or f[2] == "U16" and 2 or 1
    local v = values[f[1]] or 0
    for _ = 1,n do p[#p+1] = v & 255; v = v >> 8 end
  end
  return p
end
local fixtures = {
  [101] = status(), [103] = {240,5,240,5,240,5,240,5}, [104] = {232,3,232,3,0,0,0,0,0,0,0,0,0,0,0,0},
  [113] = {0,0,0,0,0,0,0,0,0,0}, [114] = {220,5,220,5,220,5,220,5,232,3,232,3,220,5,208,7},
  [108] = {0,0,0,0,0,0}, [139] = {0}, [0x5F14] = {0,0}
}
fixtures[52] = {}; for _ = 1,42*14 do fixtures[52][#fixtures[52]+1] = 0 end
fixtures[170] = {}; for _ = 0,28 do u16(fixtures[170],1000);u16(fixtures[170],-1000);u16(fixtures[170],1000) end
local byCommand = {}
for _, name in ipairs({ "status","boxnames","boxids","mode_ranges","mode_ranges_extra","adjustment_ranges",
  "feature_config","board_alignment_config","serial_config","rx_map","rx_config","rc_config","motor_config",
  "esc_sensor_config","governor_config","mixer_config","mixer_input","servo_configurations","servo","rc_tuning",
  "tail_motor_output","governor_profile","rc","attitude","motor","motor_telemetry","rx_channels","rc_command" }) do
  local a = api(name); byCommand[a.command] = a
end
local failCommand, legacy = nil, false
local function pump()
  local m = table.remove(q.messages,1); if not m then return end
  q.sent[#q.sent+1] = m
  if m.command==99 then lockDisabled=m.payload[1]==1;fixtures[101]=status() end
  if m.command == failCommand or (legacy and m.command == 196 and #m.payload == 4) then
    if m.errorHandler then m.errorHandler(m,"error") end; return
  end
  local b = fixtures[m.command] or (byCommand[m.command] and byCommand[m.command].simulatorResponse) or {}
  if m.processReply then m.processReply(m,b) end
end
local function measure(name, fn)
  local count = 0
  debug.sethook(function() count = count + 1 end, "", 1)
  fn()
  debug.sethook()
  worst[name] = math.max(worst[name] or 0, count)
  if count > 14000 then check(false, name .. " exceeds 14000: " .. count) end
end
local H = load(PATH .. "math.lua")
for i=1,#arg do
  if arg[i]=="--mixer-api" then modules.mixer_override=assert(loadfile(arg[i+1]))() end
end
eq(H.calibrated(-1000,18),-500,"pitch scale preserves sign")
eq(H.calibrated(1000,4.5),2000,"pitch scale clamp")
eq(H.calibrated(1000,0),nil,"zero measurement refused")
local lo,hi = H.switchRange(1000,2000); eq(lo,1500,"switch lower band");eq(hi,2100,"switch upper band")
eq(H.moved({301,200}),nil,"ambiguous movement refused");eq(H.moved({500,100}),1,"clear movement accepted")
local p = api("mixer_override").buildWritePayload({index=3,value=-1000})
eq(#p,3,"mixer write is one record");eq(p[1],3,"mixer index");eq(p[2],24,"signed mixer low")
eq(#api("mixer_override").buildWritePayload({index=4,value=0,timeout=3000}),5,"timed mixer length")
eq(#api("servo_override").buildWritePayload({servo_id=2,action=2001}),3,"release has no timeout")
eq(#api("servo_override_all").buildWritePayload({value=2001,timeout=500}),4,"safe timeout probe")
check(api("rc_command").parse({255,255,0,0,0,0,0,0,0,0}).commands[1] == -1,"signed RC command")
check(api("rx_channels").parse({1}) == nil,"truncated raw channel reply refused")
check(api("servo").parse({1}) == nil,"truncated servo reply refused")
check(api("motor_telemetry").parse({1}) == nil,"truncated telemetry reply refused")
local telem = {1}; for _=1,16 do telem[#telem+1]=0 end
telem[14],telem[15] = 156,255
eq(api("motor_telemetry").parse(telem).motors[1].temperature,-100,"signed ESC temperature")
local bad = {}; for i=1,#telem-1 do bad[i]=telem[i] end
check(api("motor_telemetry").parse(bad) == nil,"telemetry positive/negative length control")

local L = load(PATH .. "labels.lua")
-- Resolve labels from the real English bundle for layout exports.
local en = load("i18n/en.lua")
for k in pairs(L) do if en.helicopter[k] then L[k] = en.helicopter[k] end end
L.steps = { L.sensors,L.receiver,L.modeSwitches,L.profiles,L.rates,L.swash,L.servoType,L.governor,L.motor,L.connect,
  L.spinTest,L.escTelemetry,L.servoDirectionCentre,L.controlDirections,L.level,L.bladePitch,L.tail,L.gyroCheck,L.finish }
local function world()
  q.messages,q.sent = {},{}
  local w = load(PATH .. "controller.lua").new(runtime,load(PATH .. "transport.lua"),H,L)
  load(PATH .. "forms.lua").attach(w);load(PATH .. "workflow.lua").attach(w)
  w.requestRebuild = function() w.rebuilds = (w.rebuilds or 0)+1 end
  w:load()
  for _=1,1000 do measure("wakeup",function() w:tick() end);pump(); ticks=ticks+1; if w.ready or w.error then break end end
  check(w.ready and not w.error,"initial configuration read")
  w:tick(); pump(); ticks=ticks+1
  return w
end
local w = world()
check(w.timed,"timeout capability proved by 196")
eq(q.sent[1].command,99,"arming disabled before configuration writes")
eq(q.sent[1].payload[1],1,"arming disabled payload")
local steps = { "sensors","receiver","modes","profiles","rates","swash","servoType","governor","motor","connect",
  "throttle","escTelemetry","servos","direction","level","pitch","tail","gyro","finish" }
local view = load(PATH .. "view.lua")
local exported = {}
local function resolve(t)
  local out = {}
  for k,v in pairs(t) do
    if type(v) == "function" then
      if k=="text" or k=="get" or k=="active" then out[k] = v()
      elseif k=="display" and t.get then out[k] = v(t.get()) end
    elseif type(v)=="table" then out[k] = resolve(v)
    else out[k] = v end
  end
  return out
end
for _, size in ipairs({ {320,240},{480,272},{480,320},{800,480} }) do
  for n,name in ipairs(steps) do
    w.step, w.stepKey, w.rebootPending, w.transition = n,name,nil,nil
    measure("definition",function() w.cards = load(PATH .. "steps/" .. name .. ".lua")(w) end)
    check(type(w.cards)=="table" and #w.cards>0,name.." has cards")
    for c, card in ipairs(w.cards) do
      w.card = c
      local job
      measure("view",function() job = view.new(w,{ w=size[1],h=size[2] }) end)
      while not job.done do measure("view slice",function() job:step() end) end
      measure("reactive",function() resolve(job.children) end)
      for _,item in ipairs(job.children) do
        if item.y and item.h then check(item.y+item.h<=size[2],name.." fits height") end
      end
      if c==1 then exported[#exported+1] = {step=n,name=name,width=size[1],height=size[2],children=resolve(job.children)} end
    end
  end
end
eq(#steps,19,"exact step count")
-- Live replies update cached values, never the scene.
w.step,w.error,w.transition,w.rebuilds = 14,nil,nil,0
w.data.rc_command = {commands={0,0,0,0,0}}
for _=1,300 do w:tick();pump();ticks=ticks+2 end
eq(w.rebuilds,0,"live replies do not rebuild")
-- Release queued/in-flight hold writes as well as the locally held state.
w.holds = {}; w:hold("servo",0,400); w:hold("mixer",1,2502)
w.bus:add({api="servo_override",write=true,override=true,data={servo_id=0,action=400,timeout=3000}})
w:release()
check(next(w.holds)==nil,"leaving releases held state")
for _,j in ipairs(w.bus.jobs) do check(not j.override,"leaving drops unsent override job") end
local releases = {};for _,m in ipairs(q.messages) do releases[m.command] = true end
check(releases[193] and releases[191],"servo and mixer OFF queued on leave")
-- An API version of 12.10 without #541 must use persistent three-byte writes.
legacy=true
local old=world();check(not old.timed,"12.10 without timeouts is detected")
old:hold("servo",0,400)
for _=1,20 do old:tick();pump();ticks=ticks+1 end
for _,m in ipairs(q.sent) do if m.command==193 and m.payload[2]==144 then eq(#m.payload,3,"legacy hold has no timeout") end end
legacy=false
local sent=#q.sent;armed=true
for _=1,20 do old:tick();pump();ticks=ticks+1 end
eq(#q.sent,sent,"armed dispatch stops")
check(old.motorHold==nil and next(old.holds)==nil,"armed transition clears desired holds")
armed=false
-- A write error must not save or advance the wizard.
w=world();w.step=9;w.data.motor_config.motor_pole_count_0=14;w:touch("motor_config");failCommand=222
w:save(function() w.advanced=true end)
for _=1,500 do w:tick();pump();ticks=ticks+1;if w.error then break end end
check(w.error and not w.advanced,"failed write blocks advance")
local eeprom=false;for _,m in ipairs(q.sent) do if m.command==250 then eeprom=true end end
check(not eeprom,"failed write never reaches EEPROM")
failCommand=nil
-- Whole-table work is generated one record per pass, with EEPROM last.
w=world()
q.sent = {}
for _,name in ipairs({"mode_ranges","adjustment_ranges","servo_configurations","mixer_input","serial_config"}) do w:touch(name) end
measure("save callback",function() w:save(function() w.completedSave=true end) end)
for _=1,1800 do
  measure("bulk save",function() w:tick() end);pump();ticks=ticks+1
  if w.completedSave or w.error then break end
end
check(w.completedSave and not w.error,"full-table save completes")
local lastWrite
for _,m in ipairs(q.sent) do if m.isWrite then lastWrite=m.command end end
eq(lastWrite,250,"EEPROM follows every indexed write")
local count=0;for _,m in ipairs(q.sent) do if m.command==53 then count=count+1 end end
eq(count,42,"all adjustment slots written exactly once")
-- Per-profile read/write order and restoration.
w=world();q.sent={}
w:profileLoop("rates",3,function(d,i) H.style(d,i+1) end)
for _=1,500 do w:tick();pump();ticks=ticks+1;if w.bus:idle() then break end end
local selected={};local tunes=0
for _,m in ipairs(q.sent) do
  if m.command==210 then selected[#selected+1]=m.payload[1] end
  if m.command==204 then tunes=tunes+1 end
end
eq(table.concat(selected,","),"128,129,130,130","original rate profile restored")
eq(tunes,3,"three rate profiles written")
-- Maximum packed servo table, including bus channels, is still bounded.
local full={26};local fixture=api("servo_configurations").simulatorResponse
for _=1,26 do for i=2,17 do full[#full+1]=fixture[i] end end
local packed
measure("servo decode",function() packed=api("servo_configurations").parse(full) end)
eq(packed.servo_count,26,"maximum servo table parsed")
w.data.servo_configurations=packed;w.data.status.servo_count=22
w.data.serial_config.port_1_function_mask=524288
eq(#w:servos(),4,"bus channels excluded from wizard PWM servos")
w.data.mixer_config.swash_type=5
eq(#w:servos(),3,"90L has two cyclic servos and a tail")
w.data.mixer_config.tail_rotor_mode=1
eq(#w:servos(),2,"motor tail excludes servo 4")
local motorCards=load(PATH.."steps/tail.lua")(w)
eq(#motorCards,2,"motor tail variant stays within Tail step")
-- Actual page bootstrap and scene slices, including every reactive callback.
local page=load(PATH.."page.lua")
local ctx={children={},x=0,y=0,w=480,h=272,requestRebuild=function() end,requestClose=function() end}
page.build(ctx)
for _=1,500 do
  measure("page wakeup",function() page.wakeup(ctx) end);pump();ticks=ticks+1
  ctx.children={};measure("page build",function() page.build(ctx) end)
  measure("page sweep",function() resolve(ctx.children) end)
end
page.onClose()
-- Follow all 19 steps with explicit positive physical answers. No simulator or
-- radio events are synthesized; these are calls into the actual page controller.
w=world();q.sent={};w.requestClose=function() w.closed=true end
w.checks=setmetatable({},{__index=function() return true end})
w.data.mode_ranges.mode_ranges[1]={id=0,auxChannelIndex=0,range={start=1800,["end"]=2100}}
local visited={}
for _=1,3000 do
  w:tick();pump();ticks=ticks+5
  if w.ready and w.cards and not w.transition and not w.error then
    visited[w.step]=true;w:next()
  end
  if w.closed or w.error then break end
end
check(w.closed and not w.error,"complete 19-step walk exits")
local visitedCount=0;for _ in pairs(visited) do visitedCount=visitedCount+1 end
eq(visitedCount,19,"all nineteen steps visited in order")
eq(q.sent[#q.sent].command,99,"exit finishes with arming command")
eq(q.sent[#q.sent].payload[1],0,"arming availability restored only on exit")
-- ACK alone is insufficient: disappearance of the status flag blocks edits.
w=world();w.holds={};w:hold("mixer",1,0)
local unlocked=api("status").parse(status());unlocked.arming_disable_flags=0
w:acceptStatus(unlocked)
check(w.error and not w.locked and next(w.holds)==nil,"arming-lock readback failure stops bench work")
w=world();w.checks.gyro1=true;w.step=17;w:navigate(18,1)
check(w.checks.gyro1==nil,"returning to a physical check requires a fresh answer")
for name,count in pairs(worst) do print(string.format("BUDGET %-12s %d / 14000",name,count)) end
if arg[1]=="--export" then
  local function json(v)
    if type(v)=="string" then return '"'..string.gsub(string.gsub(string.gsub(v,'\\','\\\\'),'"','\\"'),'\n','\\n')..'"' end
    if type(v)=="number" or type(v)=="boolean" then return tostring(v) end
    if type(v)~="table" then return "null" end
    local parts={};local array=#v>0
    for k,x in pairs(v) do parts[#parts+1]=(array and "" or json(tostring(k))..":")..json(x) end
    return (array and "[" or "{")..table.concat(parts,",")..(array and "]" or "}")
  end
  local file=assert(io.open(arg[2],"w"));file:write(json(exported));file:close()
end
print(string.format("Wizard: %d assertions, %d failures",assertions,failures))
if failures>0 then os.exit(1) end
