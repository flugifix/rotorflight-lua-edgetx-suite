-- Tune Advisor: the record's payload versions and the shake rule.
--
-- Drives the real app/pages/flight_tuning/tune_advisor/page.lua and the real
-- tasks/msp/api/tune_advisor.lua through the page's own poll: a queued MSP2_GET_TUNE_ADVISOR
-- request is answered with a reply built here, byte for byte in the firmware's layout, and the
-- lines the page draws are read back.
--
-- What it checks:
-- - payload version 2 (71 bytes, U16 shakeCount and U16 shakeRms x10 appended) is read, and
--   version 1 (67 bytes) still is; any other version, and a reply shorter than its version's
--   record, still shows "Needs newer firmware";
-- - an axis shaking 15 deg/s or more over 500 centred samples gets P down one step and nothing
--   else, where the stop rule would otherwise raise P;
-- - an axis below either limit keeps the advice it had.
--
-- Against master the version 2 cases fail: the page shows "Needs newer firmware" for them.
--
-- Run from the repository root: lua5.3 bin/flight_tuning/verify_tune_advisor_shake.lua

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("ok   " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
  end
end

SMLSIZE, RIGHT = 1, 2
local ticks = 100
function getTime() return ticks end

local queue = { messages = {} }
function queue:add(message)
  self.messages[#self.messages + 1] = message
  return true
end

local Controls = {
  ROW_H = 40,
  LABEL_H = 21,
  STATIC_SECTION_H = 38,
  labelY = function(y) return y + 10 end,
  appendStaticSectionHeader = function(children, _, _, _, title)
    children[#children + 1] = { type = "label", text = title }
  end,
  appendComboSelect = function(children, _, _, _, label)
    children[#children + 1] = { type = "label", text = label }
    return 40
  end
}
local Common = {
  pageT = function() return function(_, _, fallback) return fallback end end
}
local Profile = {
  getActiveRateProfile = function() return 1 end,
  getActivePidProfile = function() return 1 end
}
local RcTuningApi = { command = 111, parse = function() return nil end }

local actual = {
  ["tasks/msp/api/tune_advisor.lua"] = true
}
local stubs = {
  ["app/pages/settings/common.lua"] = Common,
  ["ui/controls.lua"] = Controls,
  ["tasks/msp/runtime.lua"] = { getState = function() return { queue = queue, lastConnected = true } end },
  ["tasks/msp/api/rc_tuning.lua"] = RcTuningApi,
  ["lib/profile.lua"] = Profile,
  ["ui/confirm_dialog.lua"] = { show = function() return true end }
}

function loadScript(path)
  local relative = string.match(path, "/SCRIPTS/TOOLS/rfsuite%-core/(.+)$")
  if stubs[relative] then return function() return stubs[relative] end end
  if actual[relative] then return assert(loadfile("src/rfsuite/" .. relative)) end
  error("unexpected loadScript path: " .. tostring(path))
end

_G.rfsuite = { session = { mcu_id = "board" }, palette = { text = 0, border = 0 } }

local Page = assert(loadfile("src/rfsuite/app/pages/flight_tuning/tune_advisor/page.lua"))()

-- One record in the firmware's layout (src/main/msp/msp.c, MSP2_GET_TUNE_ADVISOR).
local function record(o)
  local buf = {}
  local function w8(v) buf[#buf + 1] = v & 0xFF end
  local function w16(v) w8(v); w8(v >> 8) end
  local function wRatio(v) w16(math.floor(v * 1000 + 0.5) & 0xFFFF) end
  w8(o.version); w8(0); w16(147); w8(0)
  w16(o.P); w16(o.F); w16(0); w8(10); w8(4); w8(36); w8(72)
  w16(1491); wRatio(o.ffGain); wRatio(0.97); w16(90)
  for _ = 1, 3 do wRatio(o.ffGain); w16(500) end
  for _ = 1, 3 do wRatio(o.ffGain); w16(100) end
  w16(o.fullCount or 0); w16(o.fullSatCount or 0); wRatio(0); w16(o.fullMaxRate or 0)
  w16(35); w16(18); wRatio(o.rebound); wRatio(1.47); wRatio(0.020); wRatio(0.003)
  if o.version == 2 then
    w16(o.shakeCount); w16(math.floor(o.shakeRms * 10 + 0.5))
  end
  return buf
end

-- F matches the stick (gain 1.0) and stops bounce back 15%: on its own, the stop rule raises P.
local function roll(o)
  local base = { version = 2, P = 50, F = 100, ffGain = 1.0, rebound = 0.15, shakeCount = 2000, shakeRms = 49.0 }
  for k, v in pairs(o or {}) do base[k] = v end
  return record(base)
end

local function texts()
  local children = {}
  Page.build({ children = children, x = 0, y = 0, w = 480, requestRebuild = function() end })
  local out = {}
  for _, child in ipairs(children) do
    if child.type == "label" and type(child.text) == "string" then out[#out + 1] = child.text end
  end
  return out
end

local function has(list, needle)
  for _, text in ipairs(list) do
    if string.find(text, needle, 1, true) then return true end
  end
  return false
end

local function count(list, needle)
  local n = 0
  for _, text in ipairs(list) do
    if string.find(text, needle, 1, true) then n = n + 1 end
  end
  return n
end

-- Open the page fresh, answer its first advisor read with buf, and return what it then draws.
local function show(buf)
  Page.onClose()
  queue.messages = {}
  texts()                       -- the first build; the poll waits one pass after it
  Page.wakeup({})
  Page.wakeup({})
  local message
  for _, m in ipairs(queue.messages) do
    if m.command == 0x5F10 then message = m end
  end
  if not message then return nil end
  queue.messages = {}
  message.processReply(message, buf)
  return texts()
end

-- Answer the next poll of the page that is open, 3 s later, and return what it then draws.
local function again(buf)
  ticks = ticks + 300
  queue.messages = {}
  Page.wakeup({})               -- the pass after a build carries no poll
  Page.wakeup({})
  local message
  for _, m in ipairs(queue.messages) do
    if m.command == 0x5F10 then message = m end
  end
  if not message then return nil end
  queue.messages = {}
  message.processReply(message, buf)
  return texts()
end

local UNSUPPORTED = "Needs newer firmware"

print("payload version 1 (67 bytes), no shake: the stop rule as before")
do
  local buf = roll({ version = 1 })
  local lines = show(buf)
  check("the record is 67 bytes", #buf == 67, #buf)
  check("it is read", lines ~= nil and not has(lines, UNSUPPORTED))
  check("Stops shows the bounce-back", lines ~= nil and has(lines, "15% bounce-back"))
  check("P is raised one step", lines ~= nil and has(lines, ":  50 -> 60"))
end

print("payload version 2 (71 bytes), shaking 49 deg/s")
do
  local buf = roll()
  local lines = show(buf)
  check("the record is 71 bytes", #buf == 71, #buf)
  check("it is read, not shown as missing firmware", lines ~= nil and not has(lines, UNSUPPORTED))
  check("Stops shows the shake", lines ~= nil and has(lines, "Shaking 49 deg/s"))
  check("P is lowered one step", lines ~= nil and has(lines, ":  50 -> 42"))
  check("P is not raised", lines ~= nil and not has(lines, ":  50 -> 60"))
  check("the reason names the shake", lines ~= nil and has(lines, "Shakes 49 deg/s at centre stick"))
  check("P is the only change", lines ~= nil and count(lines, " -> ") == 1)
end

print("payload version 2, F off and shaking: no FF or rate advice")
do
  local lines = show(roll({ ffGain = 1.53 }))
  check("Response still shows the mismatch", lines ~= nil and has(lines, "53% faster than asked"))
  check("FF is left alone", lines ~= nil and not has(lines, ":  100 ->"))
  check("P down is the only change", lines ~= nil and has(lines, ":  50 -> 42") and count(lines, " -> ") == 1)
end

-- Full stick asks 720 deg/s (Actual 36/72) and the heli reaches 400 with the cyclic at its limit:
-- on its own, the full-stick rule lowers Max Rate 720 -> 400.
local FULL = { fullCount = 200, fullSatCount = 150, fullMaxRate = 400 }

print("payload version 2, full stick short of the rate asked, calm: the rate advice (control)")
do
  local lines = show(roll({ shakeRms = 3.0, fullCount = FULL.fullCount, fullSatCount = FULL.fullSatCount,
    fullMaxRate = FULL.fullMaxRate }))
  check("the rates are lowered to what the heli reaches", lines ~= nil and has(lines, ":  720 -> 400"))
end

print("payload version 2, full stick short of the rate asked, shaking: no rate advice")
do
  local lines = show(roll({ fullCount = FULL.fullCount, fullSatCount = FULL.fullSatCount,
    fullMaxRate = FULL.fullMaxRate }))
  check("the rates are left alone", lines ~= nil and not has(lines, ":  720 -> 400"))
  check("P down is the only change", lines ~= nil and has(lines, ":  50 -> 42") and count(lines, " -> ") == 1)
end

print("payload version 2, calm (below 15 deg/s): the advice it had")
do
  local lines = show(roll({ shakeRms = 14.9 }))
  check("Stops shows the bounce-back", lines ~= nil and has(lines, "15% bounce-back"))
  check("P is raised one step", lines ~= nil and has(lines, ":  50 -> 60"))
end

print("payload version 2, the shake crosses 15 deg/s with every other figure unchanged")
do
  local lines = show(roll({ shakeRms = 14.9 }))
  check("first reply: P is raised", lines ~= nil and has(lines, ":  50 -> 60"))
  lines = again(roll({ shakeRms = 15.0 }))
  check("next reply: the page follows the shake", lines ~= nil and has(lines, "Shaking 15 deg/s")
    and has(lines, ":  50 -> 42"))
end

print("payload version 2, too little centred stick (499 samples): not judged")
do
  local lines = show(roll({ shakeCount = 499 }))
  check("Stops shows the bounce-back", lines ~= nil and has(lines, "15% bounce-back"))
  check("P is raised one step", lines ~= nil and has(lines, ":  50 -> 60"))
end

print("payload version 2, shaking with P at 1: nothing to lower")
do
  local lines = show(roll({ P = 1 }))
  check("Stops shows the shake", lines ~= nil and has(lines, "Shaking 49 deg/s"))
  check("no P change", lines ~= nil and not has(lines, ":  1 ->"))
end

print("refused replies still read as missing firmware")
do
  local v3 = roll()
  v3[1] = 3
  local lines = show(v3)
  check("payload version 3", lines ~= nil and has(lines, UNSUPPORTED))
  local short = roll()
  short[#short] = nil
  lines = show(short)
  check("a version 2 reply of 70 bytes", lines ~= nil and has(lines, UNSUPPORTED))
  lines = show({ 1 })
  check("the one-byte MSP error reply", lines ~= nil and has(lines, UNSUPPORTED))
end

print()
print(string.format("%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
