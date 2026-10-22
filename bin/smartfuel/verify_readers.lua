-- Exercises the real dashboard reader, exported Home.run and built diagnostic labels:
--   lua5.3 bin/smartfuel/verify_readers.lua
--   lua5.3 bin/smartfuel/verify_readers.lua --source-root <pre-fix-checkout>
-- Accounting stubs supply EdgeTX/FC surfaces. The home fixture keeps the connection up
-- and parks the event producer, whose wakeup has its own test, so its handover is controlled.
-- Upvalue inspection reaches the dashboard read function and host state without modifying
-- production source. Diagnostic text is read from the same label definitions handed to LVGL.
-- No screen pixels, hardware or timing are measured. Exit 0 green, 1 failed cases, 2 bad CLI.

local ROOT = "."
do
  local this = arg and arg[0]
  local dir = type(this) == "string" and string.match(this, "^(.*)[/\\][^/\\]*$") or nil
  if dir then ROOT = string.match(dir, "^(.*)[/\\]bin[/\\]smartfuel$") or (dir .. "/../..") end
end
local root = ROOT
if #arg == 2 and arg[1] == "--source-root" then
  root = arg[2]
elseif #arg > 0 then
  io.stderr:write("usage: lua5.3 bin/smartfuel/verify_readers.lua [--source-root <checkout>]\n")
  os.exit(2)
end
local Stubs=assert(loadfile(root..'/bin/accounting/stubs/edgetx.lua'))()
local FC=assert(loadfile(root..'/bin/accounting/stubs/fc.lua'))()
local function find(fn, wanted, seen)
  seen=seen or {}
  if seen[fn] then return nil end
  seen[fn]=true
  for i=1,100 do
    local name,value=debug.getupvalue(fn,i)
    if not name then break end
    if name==wanted then return value end
    if type(value)=='function' then
      local found=find(value,wanted,seen)
      if found~=nil then return found end
    end
  end
end
local function world(tool)
  Stubs.clearCard()
  Stubs.install(root); FC.install(Stubs); Stubs.reset(); FC.reset()
  if tool then Stubs.installTool() end
  Stubs.sensors.Vbat=25.8
  Stubs.sensors.RQly=100
  Stubs.sensors.SmFt=73
  Stubs.sensors.SmCp=1234
  Stubs.sensors['Bat%']=66
end

local cases = {
  { name = "dashboard reader", run = function()
    world()
    local Runtime=assert(loadfile(root..'/src/rfsuite/widgets/dashboard/runtime.lua'))()
    local widget=Runtime.new({x=0,y=0,w=800,h=480},{})
    local read=assert(find(widget.refresh,'readTelemetry'),'real dashboard readTelemetry missing')
    _G.rfsuite.session.smartfuel={fuel=88,consumption=12}
    read(widget.state,{})
    assert(widget.state.fuel==88 and widget.state.consumedMah==12 and widget.state.fuelTelemetrySeen)
    _G.rfsuite.session.smartfuel={unavailable=true}
    read(widget.state,{})
    assert(widget.state.fuel==nil and widget.state.consumedMah==nil and widget.state.fuelTelemetrySeen==false,
     'dashboard retained fuel/consumption or stale sensor fallback')
    _G.rfsuite.session.smartfuel={fuel=42,consumption=234}
    read(widget.state,{})
    assert(widget.state.fuel==42 and widget.state.consumedMah==234 and widget.state.fuelTelemetrySeen)
    print('PASS: actual dashboard reader clears stale values and recovers')
  end },
  { name = "tool home reader", run = function()
    world(true)
    local Home=assert(loadfile(root..'/src/rfsuite/ui/home.lua'))()
    Home.init({})
    for n=1,40 do Stubs.tick(); Home.run(0) end
    local state=assert(find(Home.run,'state'),'home state missing')
    local msp=assert(find(Home.run,'MspRuntime'),'home MSP runtime missing')
    local ms=msp.getState()
    ms.lastConnected=true
    ms.lastArmed=false
    msp.isFblConnected=function() return true end
    -- This fixture owns the handover; the producer has a separate exported-wakeup test.
    local events=assert(find(Home.run,'Events'),'home event runtime missing')
    events.wakeup=function() end
    _G.rfsuite.session.isConnected=true
    state.initialLoad=false
    _G.rfsuite.session.smartfuel={fuel=88,consumption=12}
    for n=1,20 do Stubs.tick(); Home.run(0) end
    assert(state.telemetryState.fuel==88 and state.telemetryState.consumedMah==12
     and state.telemetryState.fuelTelemetrySeen==true,'home positive control not reached')
    _G.rfsuite.session.smartfuel={unavailable=true}
    for n=1,4 do Stubs.tick(); Home.run(0) end
    assert(state.telemetryState.fuel==nil and state.telemetryState.consumedMah==nil
     and state.telemetryState.fuelTelemetrySeen==false,'home retained stale values')
    print('PASS: actual Home.run clears stale values')
    _G.rfsuite.session.smartfuel={fuel=42,consumption=234}
    for n=1,4 do Stubs.tick(); Home.run(0) end
    assert(state.telemetryState.fuel==42 and state.telemetryState.consumedMah==234
     and state.telemetryState.fuelTelemetrySeen==true,'home recovery not reached')
    print('PASS: actual Home.run restores fresh values')
  end },
  { name = "already-built diagnostics", run = function()
    world()
    _G.rfsuite.session.smartfuel={fuel=73,consumption=1234}
    -- The diagnostics fixture supplies named sensor answers directly. It tests the
    -- already-built labels, independent of sensor discovery or simulator-file lookup.
    local load = _G.loadScript
    _G.loadScript = function(path, mode)
      if string.sub(path, -16) == "/lib/sensors.lua" then
        return function() return { getValue = function(name)
          if name == "smartfuel" then return 73 end
          if name == "smartconsumption" then return 1234 end
          return nil
        end } end
      end
      return load(path, mode)
    end
    local Page=assert(loadfile(root..'/src/rfsuite/app/pages/tools/diagnostics/smartfuel/page.lua'))()
    local rebuilds=0
    local ctx={children={},x=0,y=0,w=800,h=480,i18n={t=function(k) return k end},
     requestRebuild=function() rebuilds=rebuilds+1 end}
    Page.build(ctx)
    local function smartTexts()
      local out={}
      for _,node in ipairs(ctx.children) do
        if node.type=='label' then
          local text=type(node.text)=='function' and node.text() or node.text
          if type(text)=='string' and (string.sub(text,1,5)=='SmFt:' or string.sub(text,1,5)=='SmCp:') then
            out[#out+1]=text
          end
        end
      end
      return out
    end
    local initial=smartTexts()
    assert(#initial==2 and initial[1]=='SmFt: 73 %' and initial[2]=='SmCp: 1234 mAh','diagnostic positive control')
    local before=rebuilds
    _G.rfsuite.session.smartfuel={unavailable=true}
    Page.wakeup()
    local missing=smartTexts()
    assert(missing[1]=='SmFt: -' and missing[2]=='SmCp: -','already-built diagnostic labels stayed stale')
    _G.rfsuite.session.smartfuel={fuel=42,consumption=234}
    Page.wakeup()
    local recovered=smartTexts()
    assert(recovered[1]=='SmFt: 42 %' and recovered[2]=='SmCp: 234 mAh','diagnostics recovery stale')
    assert(rebuilds==before,'diagnostics reset scrolling with rebuild')
    print('PASS: already-built diagnostic labels clear and recover without rebuilding')
  end },
}
local failures = 0
for _, item in ipairs(cases) do
  local ok, err = pcall(item.run)
  if not ok then failures = failures + 1; print("FAIL: " .. item.name .. ": " .. tostring(err)) end
end
Stubs.releaseCard()
print(string.format("%d cases, %d failures", #cases, failures))
os.exit(failures == 0 and 0 or 1)
