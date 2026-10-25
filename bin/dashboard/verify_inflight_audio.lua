-- Ground selections must be silent in the general announcer as well as the overlay.
debug.getmetatable("").__index = nil
local tick, checked, files, numbers = 1000, 0, {}, {}
local function check(value, message) checked=checked+1; assert(value, message) end
getTime=function() return tick end
playFile=function(path) files[#files+1]=path end
playNumber=function(value) numbers[#numbers+1]=value end
getValue=function() return 0 end
getGeneralSettings=function() return {language="en"} end
io={open=function() return {} end, close=function() end}
local cache={}
rfsuite={session={}, preferences={audio_events={adjustment_events=true}}}
loadScript=function(path)
  return loadfile(string.gsub(path, "^/SCRIPTS/TOOLS/rfsuite%-core/", "src/rfsuite/"))
end
rfsuite.require=function(path)
  if path=="lib/log.lua" then return {wanted=function() return false end, emit=function() end} end
  if not cache[path] then cache[path]=assert(loadfile("src/rfsuite/"..path))() end
  return cache[path]
end
local Audio=rfsuite.require("lib/audio.lua")
local Teller=rfsuite.require("tasks/events/telemetry_bg/adjustments.lua")
local owner={preferences={audio_events={governor_state=false, arming_flags=false,
  model_announcement=false, voltage_alert=false, pid_profile=true, rate_profile=true}},
  state={profile=1, rateProfile=2}, audioState={initialized=true}}
local function process()
  tick=tick+1000
  Audio.process(owner)
end
process()
files, numbers={}, {}
for _, mode in ipairs({"read", "restore"}) do
  rfsuite.inflightProfileJob={mode=mode, original={pid=1,rate=2}}
  for index=2,6 do
    owner.state.profile, owner.state.rateProfile=index,index
    process(); Teller.profile(owner,index)
  end
  check(#files==0 and #numbers==0, mode.." suppresses both announcers with interlock absent")
  check(owner.audioState.lastValues.pid_profile==1 and owner.audioState.lastValues.rate_profile==2,
    "general announcer remembers the original pair")
  rfsuite.inflightProfileJob=nil
  owner.state.profile, owner.state.rateProfile=1,2
  process()
  check(#files==0 and #numbers==0, "return pair is not announced after job completion")
end
owner.state.profile=3; process()
check(#files==1 and string.find(files[1], "evt/profile.wav",1,true) and numbers[1]==3,
  "ordinary profile change is still spoken")
files,numbers={},{}
Teller.profile(owner,4)
check(#files==1 and string.find(files[1], "evt/profile.wav",1,true) and numbers[1]==4,
  "in-flight overlay profile announcement is unchanged")
print(checked.." shared profile-announcement checks passed; ordinary and overlay speech controls included")
