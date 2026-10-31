-- Tune Advisor flight history: what the flight controller's tune advisor measured, one record
-- per flight and axis, kept per flight controller so the page can combine several flights.
--
--   /SCRIPTS/TOOLS/rfsuite.user/tune/<mcuId>.lua
--
-- The file is Lua the suite never runs as a script: read() loads it with an environment of its
-- own, in which the only names are the two collectors below. The first line is the format
-- version, every other line one flight on one axis:
--
--   v(1)
--   f(time, seconds, "roll", pidProfile, rateProfile, cyclicPolarity, cyclicRing, relaxType,
--     <FIELDS below, in order>)
--
-- time is the radio's clock in seconds (0 without one) and seconds the flight's usable time as
-- the flight controller counted it. The five values after the axis are the context the advice
-- depends on and the reply does not carry; any of them may be nil, which means unknown.
--
-- Only the newest MAX_FLIGHTS flights are kept, since the page never looks further back. Every
-- write replaces the whole file through lib/flight_log.lua's atomic replace, so a write that is
-- cut short leaves the previous file in place rather than a torn one. A line that does not read
-- is skipped and the rest of the file still counts.
--
-- aggregate() combines the newest flights flown on the newest flight's tune, for one axis:
-- counts add up, ratios are averaged weighted by the count they came from. The flight
-- controller's own gains are setpoint-squared weighted, so this is an approximation across
-- flights, close when flights are alike; the stop figures combine exactly. The field set,
-- precision and arithmetic are those of the Ethos suite's lib/tune_history.lua.

local M = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require) or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local mode = (_G.rfsuite and _G.rfsuite.loadMode) or "bt"
  local chunk = loadScript(fullPath, mode)
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local USER_ROOT = "/SCRIPTS/TOOLS/rfsuite.user"
local DATA_DIR = USER_ROOT .. "/tune"
local FORMAT_VERSION = 1
local MAX_FLIGHTS = 5
local AXIS_COUNT = 3
local AXIS_NAMES = { "roll", "pitch", "yaw" }
local BAND_COUNT = 3
local READ_CAP, READ_CHUNK = 16384, 4096

-- {name in the file, key in the decoded axis table, format}; band fields carry band (the band
-- table's key) and index.
local FIELDS = {
  { "p", "P", "%d" }, { "f", "F", "%d" }, { "b", "B", "%d" }, { "relax_cutoff", "relaxCutoff", "%d" },
  { "rates_type", "ratesType", "%d" }, { "rc_rate", "rcRate", "%d" }, { "s_rate", "sRate", "%d" },
  { "ff_count", "ffCount", "%d" }, { "ff_gain", "ffGain", "%.3f" }, { "ff_corr", "ffCorr", "%.3f" },
  { "ff_lag_ms", "ffLagMs", "%d" },
}
local function addBands(band, labels)
  for i = 1, BAND_COUNT do
    FIELDS[#FIELDS + 1] = { labels[i] .. "_gain", "gain", "%.3f", band = band, index = i }
    FIELDS[#FIELDS + 1] = { labels[i] .. "_count", "count", "%d", band = band, index = i }
  end
end
addBands("spBands", { "sp40", "sp100", "sp200" })
addBands("collBands", { "coll0", "coll25", "coll50" })
for _, f in ipairs({
  { "full_count", "fullCount", "%d" }, { "full_sat_count", "fullSatCount", "%d" },
  { "full_ratio", "fullRatio", "%.3f" }, { "full_max_rate", "fullMaxRate", "%d" },
  { "releases", "releases", "%d" }, { "big_rebounds", "bigRebounds", "%d" },
  { "mean_rebound", "meanRebound", "%.3f" }, { "mean_overshoot", "meanOvershoot", "%.3f" },
  { "mean_counter", "meanCounter", "%.3f" }, { "mean_iterm", "meanIterm", "%.3f" },
  { "shake_count", "shakeCount", "%d" }, { "shake_rms", "shakeRms", "%.1f" },
}) do FIELDS[#FIELDS + 1] = f end

-- The context a flight was flown in, written after the axis, nil when unknown
local CONTEXT_KEYS = { "pidProfile", "rateProfile", "cyclicPolarity", "cyclicRing", "relaxType" }
-- The tune a flight was measured with: flights are only combined when these match
local TUNE_KEYS = { "P", "F", "B", "relaxCutoff", "ratesType", "rcRate", "sRate" }
-- ...and when these are known and equal on both: they change what the same numbers mean
local MEANING_KEYS = { "cyclicPolarity", "cyclicRing", "relaxType" }

local LEAD = 3 + #CONTEXT_KEYS
local ARG_COUNT = LEAD + #FIELDS

M.MAX_FLIGHTS = MAX_FLIGHTS
M.AXIS_COUNT = AXIS_COUNT
M.TUNE_KEYS = TUNE_KEYS
M.MEANING_KEYS = MEANING_KEYS
M.CONTEXT_KEYS = CONTEXT_KEYS
M.FIELDS = FIELDS

function M.path(mcuId)
  if mcuId == nil then return nil end
  local id = string.match(tostring(mcuId), "^%s*(.-)%s*$")
  if id == "" then return nil end
  id = string.gsub(id, "[^%w_-]", "_")
  return DATA_DIR .. "/" .. id .. ".lua"
end

local function makeDir(path)
  if type(mkdir) ~= "function" then return end
  pcall(mkdir, path)
end

local function fileSize(path)
  if type(fstat) ~= "function" then return nil end
  local ok, st = pcall(fstat, path)
  if not ok or type(st) ~= "table" then return nil end
  return tonumber(st.size)
end

local function newAxis()
  local a = { spBands = {}, collBands = {} }
  for i = 1, BAND_COUNT do
    a.spBands[i] = { gain = 0, count = 0 }
    a.collBands[i] = { gain = 0, count = 0 }
  end
  for _, f in ipairs(FIELDS) do
    if not f.band then a[f[2]] = 0 end
  end
  return a
end

local function integerOrNil(v)
  if v == nil then return "nil" end
  if type(v) ~= "number" then return "nil" end
  return string.format("%d", math.floor(v + 0.5))
end

local function line(time, seconds, axis, a)
  local parts = { integerOrNil(time or 0), integerOrNil(seconds or 0), string.format("%q", AXIS_NAMES[axis]) }
  for _, k in ipairs(CONTEXT_KEYS) do parts[#parts + 1] = integerOrNil(a[k]) end
  for _, f in ipairs(FIELDS) do
    local v = f.band and a[f.band][f.index][f[2]] or a[f[2]]
    v = tonumber(v) or 0
    if f[3] == "%d" then v = math.floor(v + 0.5) end
    parts[#parts + 1] = string.format(f[3], v)
  end
  return "f(" .. table.concat(parts, ",") .. ")"
end

local function readText(path)
  local size = fileSize(path)
  if size and size > READ_CAP then return nil, "too big" end
  local f = io.open(path, "r")
  if not f then return nil, size ~= nil and "open" or "missing" end
  local parts, total = {}, 0
  while true do
    local ok, chunk = pcall(io.read, f, math.min(READ_CHUNK, READ_CAP + 1 - total))
    if not ok then io.close(f); return nil, tostring(chunk) end
    if chunk == nil or chunk == "" then break end
    total = total + #chunk
    if total > READ_CAP then io.close(f); return nil, "too big" end
    parts[#parts + 1] = chunk
  end
  io.close(f)
  if size ~= nil and total ~= size then return nil, "short read" end
  return table.concat(parts)
end

-- Runs the file's text with the two collectors and answers the format version it declared and
-- the flight lines, oldest first. The whole file is loaded in one go; when that fails anywhere
-- -- a torn or hand-broken line, a value that is not a number -- it is read again line by line
-- and every line that does not read is skipped. loadScript is not used: it drops the
-- environment and can leave compiled bytecode beside the file.
local function collect(text)
  local version, rows = nil, {}
  local axisByName = {}
  for i = 1, AXIS_COUNT do axisByName[AXIS_NAMES[i]] = i end

  local env = {}
  function env.v(n)
    if type(n) ~= "number" then error("invalid version") end
    version = n
  end
  function env.f(...)
    local n = select("#", ...)
    if n ~= ARG_COUNT then error("invalid flight line") end
    local args = { ... }
    local axis = axisByName[args[3]]
    if type(args[1]) ~= "number" or type(args[2]) ~= "number" or not axis then error("invalid flight line") end
    local a = newAxis()
    for k = 1, #CONTEXT_KEYS do
      local v = args[3 + k]
      if v ~= nil and type(v) ~= "number" then error("invalid flight line") end
      a[CONTEXT_KEYS[k]] = v
    end
    for k, f in ipairs(FIELDS) do
      local v = args[LEAD + k]
      if type(v) ~= "number" then error("invalid flight line") end
      if f.band then a[f.band][f.index][f[2]] = v else a[f[2]] = v end
    end
    rows[#rows + 1] = { time = args[1], seconds = args[2], axis = axis, a = a }
  end

  local chunk = load(text, "=tune_history", "t", env)
  if chunk and pcall(chunk) then return version, rows end

  version, rows = nil, {}
  for oneLine in string.gmatch(text, "[^\r\n]+") do
    local count = #rows
    local lineChunk = load(oneLine, "=tune_history", "t", env)
    if not lineChunk or not pcall(lineChunk) then
      for i = #rows, count + 1, -1 do rows[i] = nil end
    end
  end
  return version, rows
end

--- The saved flights for one flight controller, oldest first: {time, seconds, axes = {a, a, a}}.
--- Each axis table is shaped like a decoded reply's `a`, plus the context keys. A missing file,
--- or one of another format version, reads as no flights; the second value says why.
function M.read(mcuId)
  local path = M.path(mcuId)
  if not path then return {}, "mcu id" end
  local text, reason = readText(path)
  if not text then return {}, reason end
  local version, rows = collect(text)
  if version ~= FORMAT_VERSION then return {}, "version" end

  local flights, current = {}, nil
  for _, row in ipairs(rows) do
    if not current or current.time ~= row.time or current.axes[row.axis] then
      current = { time = row.time, seconds = row.seconds, axes = {} }
      flights[#flights + 1] = current
    end
    current.axes[row.axis] = row.a
  end
  return flights
end

local function write(mcuId, flights)
  local path = M.path(mcuId)
  if not path then return false end
  -- Loaded only to write: reading the history never needs it
  local FlightLog = requireModule("lib/flight_log.lua")
  if type(FlightLog) ~= "table" or type(FlightLog.atomicReplace) ~= "function" then return false end
  local out = { "v(" .. FORMAT_VERSION .. ")" }
  for _, flight in ipairs(flights) do
    for axis = 1, AXIS_COUNT do
      local a = flight.axes[axis]
      if a then out[#out + 1] = line(flight.time, flight.seconds, axis, a) end
    end
  end
  out[#out + 1] = ""
  makeDir(USER_ROOT)
  makeDir(DATA_DIR)
  return FlightLog.atomicReplace(path, table.concat(out, "\n"), true) == true
end

--- Appends one flight and drops all but the newest MAX_FLIGHTS. replies: the three decoded
--- tasks/msp/api/tune_advisor.lua records, roll, pitch, yaw. context: any of CONTEXT_KEYS known
--- at the time (the rest stay unknown). time: the radio clock in seconds. Returns true when
--- written.
function M.save(mcuId, replies, context, time)
  if not M.path(mcuId) or type(replies) ~= "table" then return false end
  local flights = M.read(mcuId)
  local keep = {}
  for i = math.max(1, #flights - (MAX_FLIGHTS - 1) + 1), #flights do keep[#keep + 1] = flights[i] end
  local flight = { time = time or 0, seconds = replies[1] and replies[1].seconds or 0, axes = {} }
  for axis = 1, AXIS_COUNT do
    local reply = replies[axis]
    if type(reply) ~= "table" or type(reply.a) ~= "table" then return false end
    local a = {}
    for k, v in pairs(reply.a) do a[k] = v end
    if type(context) == "table" then
      for _, k in ipairs(CONTEXT_KEYS) do a[k] = context[k] end
    end
    flight.axes[axis] = a
  end
  keep[#keep + 1] = flight
  return write(mcuId, keep)
end

--- Fills in context keys of the newest saved flight, for values only known after it was saved.
--- Keys absent from `context` keep what the file holds. Returns true when written.
function M.setContext(mcuId, context)
  if type(context) ~= "table" then return false end
  local flights = M.read(mcuId)
  local newest = flights[#flights]
  if not newest then return false end
  for axis = 1, AXIS_COUNT do
    local a = newest.axes[axis]
    if a then
      for _, k in ipairs(CONTEXT_KEYS) do
        if context[k] ~= nil then a[k] = context[k] end
      end
    end
  end
  return write(mcuId, flights)
end

function M.erase(mcuId)
  local path = M.path(mcuId)
  if not path or type(del) ~= "function" then return false end
  pcall(del, path)
  return fileSize(path) == nil
end

local function sameTune(a, b)
  for _, k in ipairs(TUNE_KEYS) do
    if a[k] ~= b[k] then return false end
  end
  for _, k in ipairs(MEANING_KEYS) do
    if a[k] == nil or b[k] == nil or a[k] ~= b[k] then return false end
  end
  return true
end

-- weighted running mean: adds value v with weight w to out[key] over total
local function addMean(out, key, v, w, total)
  if total > 0 then out[key] = out[key] + (v - out[key]) * w / total end
end

local function addBand(bands, src)
  for i = 1, BAND_COUNT do
    local b, s = bands[i], src[i]
    b.count = b.count + s.count
    addMean(b, "gain", s.gain, s.count, b.count)
  end
end

--- One axis (1 roll, 2 pitch, 3 yaw) over the newest flights on the newest flight's tune.
--- Returns the combined axis table (shaped like a decoded reply's `a`, with the newest flight's
--- context keys; all zeros with no flights), the flights used and their total seconds.
function M.aggregate(flights, axis)
  local out = newAxis()
  local newest = flights[#flights] and flights[#flights].axes[axis]
  if not newest then return out, 0, 0 end
  for _, k in ipairs(TUNE_KEYS) do out[k] = newest[k] end
  for _, k in ipairs(CONTEXT_KEYS) do out[k] = newest[k] end

  local used, seconds, shakeSq = 0, 0, 0
  for i = #flights, math.max(1, #flights - MAX_FLIGHTS + 1), -1 do
    local a = flights[i].axes[axis]
    -- The newest flight always counts; an older one only on the same tune, in the same context
    if not a or (i < #flights and not sameTune(a, newest)) then break end
    used = used + 1
    seconds = seconds + flights[i].seconds

    out.ffCount = out.ffCount + a.ffCount
    addMean(out, "ffGain", a.ffGain, a.ffCount, out.ffCount)
    addMean(out, "ffCorr", a.ffCorr, a.ffCount, out.ffCount)
    addMean(out, "ffLagMs", a.ffLagMs, a.ffCount, out.ffCount)
    addBand(out.spBands, a.spBands)
    addBand(out.collBands, a.collBands)

    out.fullCount = out.fullCount + a.fullCount
    out.fullSatCount = out.fullSatCount + a.fullSatCount
    addMean(out, "fullRatio", a.fullRatio, a.fullCount, out.fullCount)
    if a.fullMaxRate > out.fullMaxRate then out.fullMaxRate = a.fullMaxRate end

    out.releases = out.releases + a.releases
    out.bigRebounds = out.bigRebounds + a.bigRebounds
    addMean(out, "meanRebound", a.meanRebound, a.releases, out.releases)
    addMean(out, "meanOvershoot", a.meanOvershoot, a.releases, out.releases)
    addMean(out, "meanCounter", a.meanCounter, a.releases, out.releases)
    addMean(out, "meanIterm", a.meanIterm, a.releases, out.releases)

    -- RMS combines exactly: the mean of the squares, weighted by count
    out.shakeCount = out.shakeCount + a.shakeCount
    shakeSq = shakeSq + (a.shakeRms * a.shakeRms - shakeSq) * (out.shakeCount > 0 and a.shakeCount / out.shakeCount or 0)
  end
  out.shakeRms = math.sqrt(shakeSq)
  out.ffLagMs = math.floor(out.ffLagMs + 0.5)
  return out, used, seconds
end

--- The value the pilot last set by hand for one setting: from the current value, follows the
--- change journal (lib/change_journal.lua entries, oldest first) back while each entry is the
--- Tune Advisor's own, on the same field and profile, and ended at the value the walk stands on.
--- Any other entry on that field and profile -- a hand edit on another page, a different value
--- -- ends the walk, so the value it set counts as the pilot's. No entry: the current value.
function M.pilotValue(entries, profile, field, value)
  if type(entries) ~= "table" then return value end
  for i = #entries, 1, -1 do
    local e = entries[i]
    if e.field == field and e.profile == profile then
      if e.source ~= "tune_advisor" or e.new ~= value then break end
      value = e.old
    end
  end
  return value
end

return M
