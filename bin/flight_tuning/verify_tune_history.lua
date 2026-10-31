-- The Tune Advisor flight history and the change journal it is read beside.
--
-- Run from the repository root:
--     lua5.3 bin/flight_tuning/verify_tune_history.lua
--
-- Drives the real src/rfsuite/lib/tune_history.lua, lib/change_journal.lua, lib/flight_log.lua
-- (its atomic replace) and tasks/msp/api/tune_advisor.lua (the simulator replies the flights are
-- made of) against an in-memory card that answers io.open/io.read/io.write/io.close, fstat,
-- mkdir, rename and del the way the radio's filesystem library does.
--
-- The cases under "Ethos suite" are the Ethos suite's bin/tune_history/verify_tune_history.lua
-- at commit 098da94426 that test the history itself -- the aggregate and the Apply record -- and
-- the pilotValue cases of its bin/tune_advisor_apply/verify_tune_advisor_apply.lua, with the
-- same names, inputs and expected results. Two things differ by design and are named there:
-- a flight is saved by calling save() with three decoded replies (the Ethos cases save through
-- the disarm task, which this file does not cover), and each such flight is saved with one
-- known context (profiles, cyclic polarity, cyclic ring, relax type), since a flight of unknown
-- context is never combined with another. The Apply record is this suite's change journal.
-- The disarm capture, its pacing and its request gate are not here.
--
-- Against a tree without lib/tune_history.lua this script stops at the first load: red.

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    print("  ok    " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
    if detail then print("        " .. tostring(detail)) end
  end
end

-- ---------------------------------------------------------------------------
-- The card: paths under /SCRIPTS/TOOLS/rfsuite.user live in `files`.
-- ---------------------------------------------------------------------------
-- luacheck: globals io
local files = {}
local renameFails = {}         -- source path -> true: that rename answers an error
local renames = {}

io.open = function(path, mode)
  mode = mode or "r"
  if string.sub(mode, 1, 1) == "r" then
    if files[path] == nil then return nil end
    return { path = path, pos = 1, mode = "r" }
  end
  if string.sub(mode, 1, 1) == "w" then files[path] = "" end
  if string.sub(mode, 1, 1) == "a" and files[path] == nil then files[path] = "" end
  return { path = path, mode = "w" }
end
io.read = function(f, n)
  local data = files[f.path] or ""
  if f.pos > #data then return "" end
  local chunk = string.sub(data, f.pos, f.pos + n - 1)
  f.pos = f.pos + #chunk
  return chunk
end
io.write = function(f, ...)
  for i = 1, select("#", ...) do files[f.path] = files[f.path] .. tostring((select(i, ...))) end
  return f
end
io.close = function() return true end
io.seek = function(f, at) f.pos = at + 1 end
function fstat(path)
  if files[path] == nil then return nil end
  return { size = #files[path] }
end
function mkdir() return 0 end
function del(path) files[path] = nil; return 0 end
function rename(from, to)
  renames[#renames + 1] = from .. " -> " .. to
  if renameFails[from] then return 1 end
  if files[from] == nil or files[to] ~= nil then return 8 end
  files[to], files[from] = files[from], nil
  return 0
end
function loadScript(path)
  local relative = string.match(path, "^/SCRIPTS/TOOLS/rfsuite%-core/(.+)$")
  assert(relative == "lib/flight_log.lua", "unexpected module: " .. tostring(path))
  return assert(loadfile("src/rfsuite/" .. relative))
end
_G.rfsuite = nil

local Api = assert(loadfile("src/rfsuite/tasks/msp/api/tune_advisor.lua"))()
local tuneHistory = assert(loadfile("src/rfsuite/lib/tune_history.lua"))()
local journal = assert(loadfile("src/rfsuite/lib/change_journal.lua"))()

local MCU = "abc123"
local HISTORY = "/SCRIPTS/TOOLS/rfsuite.user/tune/" .. MCU .. ".lua"
local JOURNAL = "/SCRIPTS/TOOLS/rfsuite.user/journal/" .. MCU .. ".lua"
local CONTEXT = { pidProfile = 1, rateProfile = 1, cyclicPolarity = 0, cyclicRing = 0, relaxType = 2 }

local function reset()
  for k in pairs(files) do files[k] = nil end
  for k in pairs(renameFails) do renameFails[k] = nil end
  for i = #renames, 1, -1 do renames[i] = nil end
end

-- Three decoded simulator replies with these overrides on every axis
local function replies(seconds, fields)
  local out = {}
  for axis = 1, 3 do
    local d = assert(Api.parse(Api.simulatorResponseFor(axis)))
    d.seconds = seconds
    for k, v in pairs(fields or {}) do d.a[k] = v end
    out[axis] = d
  end
  return out
end

local clock = 1000
local function fly(seconds, f, context, extra)
  clock = clock + 60
  local fields = { F = f or 100 }
  for k, v in pairs(extra or {}) do fields[k] = v end
  return tuneHistory.save(MCU, replies(seconds, fields), context or CONTEXT, clock)
end

local function lines()
  local out = {}
  for l in string.gmatch(files[HISTORY] or "", "[^\n]+") do out[#out + 1] = l end
  return out
end

local function entriesText(rows)
  local out = {}
  for i = 1, #rows do out[i] = rows[i] end
  return table.concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------------------
print("Ethos suite: the history file")
-- ---------------------------------------------------------------------------
do
  reset()
  fly(147)
  for n = 1, 6 do fly(100 + n) end
  local r = lines()
  check("only the last 5 flights are kept", #r == 16 and string.find(r[2], ',102,"roll",', 1, true) ~= nil
    and string.find(r[14], ',106,"roll",', 1, true) ~= nil, #r .. " lines; first " .. tostring(r[2]))
end

print("Ethos suite: the page's aggregate")
do
  reset()
  fly(60, 100)
  fly(70, 80)
  fly(80, 80)
  local flights = tuneHistory.read(MCU)
  check("the history reads back as flights", #flights == 3 and flights[3].seconds == 80
    and flights[3].axes[1].F == 80 and flights[3].axes[3].P == 100, #flights .. " flights")

  local a, used, seconds = tuneHistory.aggregate(flights, 1)
  local one = flights[3].axes[1]
  check("only flights on the newest tune are combined", used == 2 and seconds == 150 and a.F == 80,
    used .. " flights, " .. seconds .. " s")
  check("counts add up", a.ffCount == 2 * one.ffCount and a.releases == 2 * one.releases
    and a.spBands[1].count == 2 * one.spBands[1].count, a.ffCount)
  check("ratios are weighted means", math.abs(a.ffGain - one.ffGain) < 1e-9
    and math.abs(a.meanRebound - one.meanRebound) < 1e-9, a.ffGain)

  for n = 1, 6 do fly(90 + n, 80) end
  local _, usedMax = tuneHistory.aggregate(tuneHistory.read(MCU), 1)
  check("at most 5 flights are combined", usedMax == 5, usedMax)

  local empty, none = tuneHistory.aggregate({}, 2)
  check("no flights aggregate to zeros", none == 0 and empty.ffCount == 0 and empty.collBands[3].count == 0)

  files[HISTORY] = "some,other,columns\n1,2,3\n"
  check("a file with other columns reads as no flights", #tuneHistory.read(MCU) == 0)
end

print("Ethos suite: the Apply record reads back (this suite's change journal)")
do
  reset()
  files[JOURNAL] = entriesText({
    'e(1759312800,"tune_advisor",1,"pid_0_P",50,60)',
    'e(1759312800,"tune_advisor",1,"iterm_relax_cutoff_1",10,8)',
    "not,a,row",
  })
  local rows = journal.read(MCU) or {}
  check("each row reads as axis, setting, from, to", #rows == 2 and rows[1].field == "pid_0_P"
    and rows[1].old == 50 and rows[1].new == 60 and rows[2].field == "iterm_relax_cutoff_1" and rows[2].new == 8,
    #rows)
  files[JOURNAL] = nil
  rows = journal.read(MCU)
  check("no file reads as no changes", type(rows) == "table" and #rows == 0)
  files[JOURNAL] = "other,header\n1,2\n"
  rows = journal.read(MCU)
  check("a foreign file reads as no changes", type(rows) == "table" and #rows == 0, tostring(rows))
  files[JOURNAL] = 'date;axis;setting\ne(1759312800,"tune_advisor",1,"pid_0_P",50,60)\n'
  rows = journal.read(MCU)
  check("rows under another header are still read", type(rows) == "table" and #rows == 1, tostring(rows))
  files[JOURNAL] = nil
end

print("Ethos suite: pilotValue follows only an unbroken chain of Apply changes")
do
  local log = {
    { source = "tune_advisor", profile = 1, field = "pid_0_P", old = 40, new = 48 },
    { source = "tune_advisor", profile = 1, field = "pid_0_F", old = 100, new = 80 },
    { source = "tune_advisor", profile = 1, field = "pid_0_P", old = 48, new = 58 },
  }
  check("follows the chain back", tuneHistory.pilotValue(log, 1, "pid_0_P", 58) == 40)
  check("a different current value is the pilot's", tuneHistory.pilotValue(log, 1, "pid_0_P", 65) == 65)
  check("another axis is not followed", tuneHistory.pilotValue(log, 1, "pid_1_P", 58) == 58)
  check("no record: the current value", tuneHistory.pilotValue({}, 1, "pid_0_P", 58) == 58)
end

-- ---------------------------------------------------------------------------
print("Differences from the Ethos suite: the file (#979)")
-- ---------------------------------------------------------------------------
do
  reset()
  fly(147)
  local r = lines()
  check("a version line and one line per axis are written", #r == 4 and r[1] == "v(1)"
    and string.find(r[2], '^f%(%d+,147,"roll",1,1,0,0,2,70,100,0,10,4,18,24,') ~= nil
    and string.find(r[3], ',"pitch",', 1, true) ~= nil and string.find(r[4], ',"yaw",', 1, true) ~= nil,
    table.concat(r, "\n"))
  local _, commas2 = string.gsub(r[2], ",", "")
  local _, commas4 = string.gsub(r[4], ",", "")
  check("every line carries the same values", commas2 == commas4 and commas2 == 8 + #tuneHistory.FIELDS - 1,
    commas2 .. " vs " .. commas4)
  check("values keep their precision", string.find(r[2], ",1.531,", 1, true) ~= nil
    and string.find(r[2], ",3.0)", 1, true) ~= nil, r[2])
  check("the file lives per flight controller under the user directory",
    tuneHistory.path("ab c/1") == "/SCRIPTS/TOOLS/rfsuite.user/tune/ab_c_1.lua"
    and string.match(journal.path("ab c/1"), "[^/]+$") == string.match(tuneHistory.path("ab c/1"), "[^/]+$"))

  fly(150)
  local before = files[HISTORY]
  files[HISTORY] = string.sub(before, 1, #before - 30)
  local flights = tuneHistory.read(MCU)
  check("a torn last line loses that line only", #flights == 2 and flights[2].axes[1] ~= nil
    and flights[2].axes[2] ~= nil and flights[2].axes[3] == nil and flights[1].axes[3] ~= nil, #flights .. " flights")

  r = lines()
  r[3] = "f(1,2,3"
  files[HISTORY] = table.concat(r, "\n") .. "\n"
  flights = tuneHistory.read(MCU)
  check("a broken line in the middle is skipped, the rest still read", #flights == 2
    and flights[1].axes[2] == nil and flights[1].axes[1] ~= nil and flights[2].axes[1] ~= nil, #flights .. " flights")

  r[3] = 'f(1,2,"roll",1,1,0,0,2,"x")'
  files[HISTORY] = table.concat(r, "\n") .. "\n"
  check("a line with a value that is not a number is skipped", #tuneHistory.read(MCU) == 2)

  r[1] = "v(2)"
  files[HISTORY] = table.concat(r, "\n") .. "\n"
  local none, why = tuneHistory.read(MCU)
  check("the version line is read on the line-by-line path too", #none == 0 and why == "version", tostring(why))
  check("a file of another version is started again", fly(160) and #lines() == 4 and lines()[1] == "v(1)",
    #lines() .. " lines")

  reset()
  fly(147)
  check("a save writes beside the file and renames it into place",
    renames[#renames] == HISTORY .. ".new -> " .. HISTORY and files[HISTORY .. ".new"] == nil, renames[#renames])
  local kept = files[HISTORY]
  renameFails[HISTORY .. ".new"] = true
  check("a save whose rename fails reports it", fly(150) == false)
  check("a failed rename leaves the previous file whole", files[HISTORY] == kept, tostring(files[HISTORY]))
  renameFails[HISTORY .. ".new"] = nil

  check("erase removes the file", tuneHistory.erase(MCU) == true and files[HISTORY] == nil)
end

print("Differences from the Ethos suite: profiles, polarity, ring and relax type (#979)")
do
  reset()
  fly(147, 100, { pidProfile = 2, rateProfile = 3 })
  local a = tuneHistory.read(MCU)[1].axes[1]
  check("profiles read back, what was not known reads as unknown", a.pidProfile == 2 and a.rateProfile == 3
    and a.cyclicPolarity == nil and a.cyclicRing == nil and a.relaxType == nil)
  check("a line of unknown context writes nil", string.find(lines()[2], ',"roll",2,3,nil,nil,nil,', 1, true) ~= nil,
    lines()[2])
  fly(150, 100, { pidProfile = 2, rateProfile = 3 })
  check("context read after the save fills in the newest flight",
    tuneHistory.setContext(MCU, { cyclicPolarity = 1, cyclicRing = 80, relaxType = 1 }) == true)
  local flights = tuneHistory.read(MCU)
  local newest, older = flights[2].axes[3], flights[1].axes[3]
  check("the newest flight carries it on every axis, the older one does not", #flights == 2
    and newest.cyclicPolarity == 1 and newest.cyclicRing == 80 and newest.relaxType == 1 and newest.pidProfile == 2
    and older.cyclicPolarity == nil)

  local agg, used = tuneHistory.aggregate(flights, 1)
  check("unknown context is never combined: the newest flight counts alone", used == 1
    and agg.cyclicPolarity == 1 and agg.cyclicRing == 80 and agg.relaxType == 1 and agg.pidProfile == 2, used)

  reset()
  fly(60, 100, { pidProfile = 1, rateProfile = 1 })
  fly(60, 100, { pidProfile = 1, rateProfile = 1 })
  local _, unknownUsed = tuneHistory.aggregate(tuneHistory.read(MCU), 1)
  check("two flights of unknown context on the same tune are not combined", unknownUsed == 1, unknownUsed)

  local function pairUsed(ctxA, ctxB)
    reset()
    fly(60, 100, ctxA)
    fly(60, 100, ctxB)
    local _, n = tuneHistory.aggregate(tuneHistory.read(MCU), 1)
    return n
  end
  local base = { pidProfile = 1, rateProfile = 1, cyclicPolarity = 0, cyclicRing = 100, relaxType = 2 }
  local function with(k, v) local c = {} for kk, vv in pairs(base) do c[kk] = vv end c[k] = v return c end
  check("the same context on the same tune is combined", pairUsed(base, base) == 2)
  check("another cyclic polarity is not combined", pairUsed(base, with("cyclicPolarity", 1)) == 1)
  check("another cyclic ring is not combined", pairUsed(base, with("cyclicRing", 80)) == 1)
  check("another relax type is not combined", pairUsed(base, with("relaxType", 1)) == 1)
end

print("Differences from the Ethos suite: the change journal reads past a broken line (#979)")
do
  reset()
  files[JOURNAL] = 'e(1,"tune_advisor",1,"pid_0_P",40,48)\ne(2,"tune_advisor",1,"pid_0_P",48,'
  local rows = journal.read(MCU)
  check("a torn last journal line loses that line only", type(rows) == "table" and #rows == 1
    and rows[1].new == 48, tostring(rows))
  files[JOURNAL] = 'e(1,"tune_advisor",1,"pid_0_P",40,48)\ne(2,"tune_advisor",0,"pid_0_P",48,58)\n'
    .. 'e(3,"tune_advisor",1,"pid_0_P",48,58)\n'
  rows = journal.read(MCU)
  check("a journal entry that does not validate is skipped", type(rows) == "table" and #rows == 2
    and rows[2].time == 3, tostring(rows))
  files[JOURNAL] = nil
end

print("Differences from the Ethos suite: pilotValue follows the Tune Advisor's own entries only (#980)")
do
  local handFirst = {
    { source = "pids", profile = 1, field = "pid_0_P", old = 30, new = 40 },
    { source = "tune_advisor", profile = 1, field = "pid_0_P", old = 40, new = 48 },
    { source = "tune_advisor", profile = 1, field = "pid_0_P", old = 48, new = 58 },
  }
  check("an entry of another source ends the walk at the value it set",
    tuneHistory.pilotValue(handFirst, 1, "pid_0_P", 58) == 40)
  local handLast = {
    { source = "tune_advisor", profile = 1, field = "pid_0_P", old = 40, new = 48 },
    { source = "pids", profile = 1, field = "pid_0_P", old = 48, new = 55 },
  }
  check("a hand edit after the advice is the pilot's value", tuneHistory.pilotValue(handLast, 1, "pid_0_P", 55) == 55)
  local otherProfile = {
    { source = "tune_advisor", profile = 2, field = "pid_0_P", old = 40, new = 58 },
  }
  check("another PID profile is not followed", tuneHistory.pilotValue(otherProfile, 1, "pid_0_P", 58) == 58)
  check("no journal at all: the current value", tuneHistory.pilotValue(nil, 1, "pid_0_P", 58) == 58)
end

-- ---------------------------------------------------------------------------
print("From the review")
-- ---------------------------------------------------------------------------
do
  reset()
  fly(60, 100, CONTEXT, { P = 50 })
  fly(60, 90, CONTEXT, { P = 60 })
  local _, used = tuneHistory.aggregate(tuneHistory.read(MCU), 1)
  check("P 50 -> 60 with F 100 -> 90 is another tune: not combined", used == 1, used)
  fly(60, 90, CONTEXT, { P = 60 })
  _, used = tuneHistory.aggregate(tuneHistory.read(MCU), 1)
  check("identical tunes are combined", used == 2, used)

  reset()
  for _ = 1, 5 do fly(120, 100, CONTEXT, { fullCount = 14000 }) end
  local a, n = tuneHistory.aggregate(tuneHistory.read(MCU), 1)
  check("5 x 14000 full-stick samples sum to 70000, not capped at 16 bits", n == 5 and a.fullCount == 70000,
    tostring(a.fullCount))
end

print(string.format("\n%d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
