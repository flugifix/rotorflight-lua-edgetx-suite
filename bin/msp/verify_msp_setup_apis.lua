-- Offline byte-vector checks. No simulator or flight controller is used.
local root = arg[1] or "src/rfsuite/tasks/msp/api/"
local count = 0
local function api(name) return assert(loadfile(root .. name .. ".lua"))() end
local function eq(a,b,label)
  count=count+1
  assert(a==b,label .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function bytes(a,b,label)
  eq(#a,#b,label .. " length")
  for i,v in ipairs(b) do eq(a[i],v,label .. " byte " .. i) end
end
local function u16(p,v) p[#p+1],p[#p+2]=v & 255,(v >> 8) & 255 end
for _,entry in ipairs({{"servo",103},{"attitude",108},{"rc_command",113},{"rx_channels",114},
  {"motor_telemetry",139},{"rx_serial_trial",0x5F12},{"tail_motor_output",0x5F14}}) do
  local m=api(entry[1]);eq(m.command,entry[2],entry[1] .. " command")
  eq(m.parse(nil),nil,entry[1] .. " rejects missing buffer")
  eq(type(m.parse(m.simulatorResponse)),"table",entry[1] .. " parses its simulator response")
end
local servo=api("servo")
local p={};for i=1,32 do u16(p,1000+i) end
local d=servo.parse(p);eq(d.servo_count,32,"all live servo outputs")
for i=1,32 do eq(d.servos[i],1000+i,"servo order") end
table.remove(p);eq(servo.parse(p),nil,"odd servo buffer refused")
eq(servo.parse({}),nil,"empty servo buffer refused")
local rx=api("rx_channels");p={};for i=1,18 do u16(p,980+i*31) end
d=rx.parse(p);eq(d.channel_count,18,"18 raw receiver channels")
for i=1,18 do eq(d.channels[i],980+i*31,"raw channel order") end
u16(p,1500);eq(rx.parse(p),nil,"too many receiver channels refused")
eq(rx.parse({1}),nil,"short receiver channel refused")
eq(rx.parse({}).channel_count,0,"no active receiver channel is a valid reply")
local rc=api("rc_command");p={};for _,v in ipairs({-500,500,-1,0,1000}) do u16(p,v) end
d=rc.parse(p)
for i,v in ipairs({-500,500,-1,0,1000}) do eq(d.commands[i],v,"signed function order") end
eq(rc.parse({0,0}),nil,"short command buffer refused")
local at=api("attitude").parse({6,255,250,0,166,255})
eq(at.roll,-25,"signed roll tenths");eq(at.pitch,25,"pitch tenths");eq(at.yaw,-90,"yaw degrees")
eq(api("attitude").parse({0,0}),nil,"short attitude refused")
local motor=api("motor_telemetry");p={1}
for _,v in ipairs({0x5678,0x1234,10,2500,350,71,-125,880}) do u16(p,v) end
d=motor.parse(p);eq(d.motor_count,1,"motor count")
for k,v in pairs({rpm=0x12345678,invalid_percent=10,voltage=2500,current=350,consumption=71,temperature=-125,temperature2=880}) do
  eq(d.motors[1][k],v,"motor " .. k)
end
table.remove(p);eq(motor.parse(p),nil,"short telemetry refused")
eq(motor.parse({5}),nil,"unsupported motor count refused")
eq(motor.parse({0}).motor_count,0,"no motors is a valid reply")
local lock=api("arming_disable");eq(lock.writeCommand,99,"arming command")
bytes(lock.buildWritePayload({disabled=true}),{1},"disable arming")
bytes(lock.buildWritePayload({disabled=false}),{0},"release arming inhibit")
local calibration=api("acc_calibration");eq(calibration.writeCommand,205,"accelerometer command")
bytes(calibration.buildWritePayload(),{},"accelerometer payload")
local trial=api("rx_serial_trial");eq(trial.writeCommand,0x5F12,"trial write command")
bytes(trial.buildWritePayload({action=1}),{1},"receiver trial start")
bytes(trial.buildWritePayload({action=2}),{2},"receiver trial stop")
eq(trial.buildWritePayload({action=0}),nil,"trial poll is a read, not a write")
eq(trial.parse({1,2,1,0,1,232,3}).elapsed_ms,1000,"receiver trial elapsed")
eq(trial.parse({1,2,1,0,1,232,3}).combo_index,2,"receiver trial combination")
eq(trial.parse({1,2}),nil,"short trial reply refused")
local tail=api("tail_motor_output");eq(tail.writeCommand,0x5F14,"tail write command")
for i=1,2 do bytes(tail.buildWritePayload({action=i}),{i},"tail action") end
eq(tail.buildWritePayload({action=0}),nil,"tail read is a read, not a write")
eq(tail.buildWritePayload({action=3}),nil,"invalid tail action refused")
eq(tail.parse({3,6}).result,6,"tail result retained")
eq(tail.parse({4,0}),nil,"unknown tail output refused")
local config=api("rc_config")
eq(config.parse({0,0,0,0,0,0,0}),nil,"truncated RC configuration refused")
eq(config.parse(config.simulatorResponse).rc_center,1500,"complete RC configuration")
local mixer=api("mixer_input");p={}
for i=0,28 do u16(p,i==0 and -1000 or 1000);u16(p,-1250);u16(p,1500) end
d=mixer.parse(p);eq(d.inputs[0].rate,-1000,"signed indexed mixer rate")
eq(d.inputs[28].min,-1250,"last indexed mixer limit")
eq(d.inputs[28].max,1500,"last indexed mixer maximum")
eq(d.rate_aileron,64536,"legacy unsigned flat rate preserved")
table.remove(p);eq(mixer.parse(p),nil,"partial indexed mixer record refused")
local configs=api("servo_configurations");d=configs.parse(configs.simulatorResponse)
eq(configs.writeCommand,212,"servo configuration write command")
local partial={};for k,v in pairs(d.servos[0]) do partial[k]=v end;partial.rpos=nil
eq(configs.buildWritePayload({index=0,servo=partial}),nil,"incomplete servo record refused")
eq(configs.buildWritePayload({servo=d.servos[0]}),nil,"servo write without index refused")
for i=0,d.servo_count-1 do
  local s=d.servos[i];local out=configs.buildWritePayload({index=i,servo=s})
  eq(out[1],i,"servo write index");eq(#out,17,"complete servo write")
  local reply={1};for j=2,#out do reply[#reply+1]=out[j] end
  local round=configs.parse(reply).servos[0]
  for _,field in ipairs(configs.fields or {{"mid"},{"min"},{"max"},{"rneg"},{"rpos"},{"rate"},{"speed"},{"flags"}}) do
    eq(round[field[1]],s[field[1]],"servo configuration roundtrip " .. field[1])
  end
end
print("MSP setup APIs: " .. count .. " assertions passed")
