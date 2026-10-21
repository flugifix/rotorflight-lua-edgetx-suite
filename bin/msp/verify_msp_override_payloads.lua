-- Wire-format checks for one-output overrides and explicit timeout payloads.
local root=arg[1] or "src/rfsuite/tasks/msp/api/"
local count=0
local function api(name) return assert(loadfile(root .. name .. ".lua"))() end
local function eq(a,b,label) count=count+1;assert(a==b,label .. ": " .. tostring(a) .. " / " .. tostring(b)) end
local function bytes(a,b,label)
  eq(#a,#b,label .. " length")
  for i,v in ipairs(b) do eq(a[i],v,label .. " byte " .. i) end
end
local mixer=api("mixer_override")
eq(mixer.command,190,"mixer read command");eq(mixer.writeCommand,191,"mixer write command")
bytes(mixer.buildWritePayload({index=0,value=750}),{0,238,2},"single input")
bytes(mixer.buildWritePayload({index=28,value=-750}),{28,18,253},"signed value bits")
bytes(mixer.buildWritePayload({index=2,value=2501}),{2,197,9},"release")
bytes(mixer.buildWritePayload({index=2,value=750,timeout=1000}),{2,238,2,232,3},"explicit timed input")
bytes(mixer.buildWritePayload({index=0,value=0,timeout=1}),{0,0,0,244,1},"timeout minimum")
bytes(mixer.buildWritePayload({index=0,value=0,timeout=40000}),{0,0,0,48,117},"timeout maximum")
eq(mixer.buildWritePayload({index=-1}),nil,"negative input refused")
eq(mixer.buildWritePayload({index=29}),nil,"out of range input refused")
eq(mixer.buildWritePayload({index=0,value=0,timeout="1000"}),nil,"non-numeric mixer timeout refused")
bytes(mixer.buildWritePayload({index=1,value=0,timeout=1000.7}),{1,0,0,232,3},"fractional timeout floored")
local p={};for i=1,29 do p[#p+1],p[#p+2]=i,0 end
local d=mixer.parse(p);for i=1,29 do eq(d["override_"..i],i,"mixer read order") end
table.remove(p);eq(mixer.parse(p),nil,"short mixer read refused")
local servo=api("servo_override")
eq(servo.command,192,"servo read command");eq(servo.writeCommand,193,"servo write command")
bytes(servo.buildWritePayload({servo_id=3,action=1500}),{3,220,5},"legacy servo payload")
bytes(servo.buildWritePayload({servo_id=3,action=1500,timeout=1000}),{3,220,5,232,3},"explicit timed servo")
bytes(servo.buildWritePayload({servo_id=0,action=2001}),{0,209,7},"servo release")
bytes(servo.buildWritePayload(nil),{0,0,0},"servo payload without data keeps its legacy default")
eq(servo.buildWritePayload({servo_id=0,action=2001,timeout=true}),nil,"non-numeric servo timeout refused")
local all=api("servo_override_all");eq(all.writeCommand,196,"all-servo command")
bytes(all.buildWritePayload({value=2001}),{209,7},"legacy all-servo OFF")
bytes(all.buildWritePayload({value=2001,timeout=1000}),{209,7,232,3},"timed all-servo OFF probe")
bytes(all.buildWritePayload({value=2001,timeout=0}),{209,7,244,1},"all-servo minimum timeout")
bytes(all.buildWritePayload({value=2001,timeout=40000}),{209,7,48,117},"all-servo maximum timeout")
eq(all.buildWritePayload(nil),nil,"all-servo write without data refused")
eq(all.buildWritePayload({}),nil,"all-servo write without value refused")
eq(all.buildWritePayload({value=2001,timeout="x"}),nil,"non-numeric all-servo timeout refused")
print("MSP override payloads: " .. count .. " assertions passed")
