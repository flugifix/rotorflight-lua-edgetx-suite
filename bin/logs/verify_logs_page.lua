-- Host checks for the Logs page (app/pages/logs/page.lua), driven the way the tool opened from
-- the dashboard drives it: the page's own wakeup steps under a 20 000-instruction ceiling.
-- Run from the repository root: lua5.3 bin/logs/verify_logs_page.lua
local checks, failures = 0, 0
local function check(ok, label, detail)
  checks = checks + 1
  if not ok then
    failures = failures + 1
    print("FAIL " .. label .. (detail and (": " .. tostring(detail)) or ""))
  end
end

local PAGE = "src/rfsuite/app/pages/logs/page.lua"
local GRAPH = "src/rfsuite/app/pages/logs/graph.lua"
local CEILING = 20000

-- EdgeTX surface the page touches while it lists, reads and builds.
LCD_W, LCD_H, SMLSIZE, MIDSIZE, CENTER = 800, 480, 0, 0, 0
lcd = { sizeText = function(s) return #tostring(s) * 7, 16 end, RGB = function(r, g, b) return r * 65536 + g * 256 + b end }
lvgl = { isFullScreen = function() return true end }
getTime = function() return 0 end

local hosted = true
local modules = {
  ["app/pages/settings/common.lua"] = { pageT = function() return function(_, key) return key end end },
  ["ui/controls.lua"] = {},
  ["ui/loading_overlay.lua"] = { append = function(children, opts) children[#children + 1] = opts end },
  ["lib/env.lua"] = { isWidget = function() return hosted end },
  ["ui/palette.lua"] = {}
}
loadScript = function(path)
  local key = string.gsub(path, "^/SCRIPTS/TOOLS/rfsuite%-core/", "")
  if key == "app/pages/logs/graph.lua" then return assert(loadfile(GRAPH)) end
  if modules[key] then return function() return modules[key] end end
  error("unexpected module " .. path)
end

-- A local of the page, reached through the upvalues of its exported functions.
local function find(fn, name, seen)
  seen = seen or {}
  if seen[fn] then return nil end
  seen[fn] = true
  local children = {}
  for i = 1, 255 do
    local n, v = debug.getupvalue(fn, i)
    if not n then break end
    if n == name then return v end
    if type(v) == "function" then children[#children + 1] = v end
  end
  for _, child in ipairs(children) do
    local v = find(child, name, seen)
    if v ~= nil then return v end
  end
  return nil
end

-- One call as the widget makes it: stopped once it has spent the ceiling. Answers whether it
-- finished and how many instructions it spent.
local function ceilingCall(fn, ...)
  local used = 0
  debug.sethook(function()
    used = used + 100
    if used >= CEILING then error("instruction ceiling", 0) end
  end, "", 100)
  local res = table.pack(pcall(fn, ...))
  debug.sethook()
  if not res[1] and res[2] ~= "instruction ceiling" then error(res[2], 0) end
  return res[1], used, res[2]
end

-- An in-memory card for the files a log view reads, through EdgeTX's call forms.
local files = {}
local reads = { bytes = 0 }
io = {
  open = function(path) if files[path] then return { path = path, pos = 0 } end return nil end,
  read = function(h, n)
    local s = string.sub(files[h.path], h.pos + 1, h.pos + n)
    h.pos = h.pos + #s
    reads.bytes = reads.bytes + #s
    if s == "" then return nil end
    return s
  end,
  seek = function(h, off) h.pos = off; return off end,
  close = function() end
}
fstat = function(path) if files[path] then return { size = #files[path] } end return nil end

-- A telemetry log as EdgeTX writes it: ten rows a second, every column moving.
local function makeLog(rows, startSec)
  local out = { "Date,Time,Vbat(V),Curr(A),Hspd(rpm),EscT(C),1RSS(dB),RQly(%),Capa(mAh)" }
  for i = 0, rows - 1 do
    local t = startSec + i / 10
    out[#out + 1] = string.format("2026-10-01,%02d:%02d:%02d.%03d,%.2f,%.2f,%d,%d,%d,%d,%d",
      math.floor(t / 3600), math.floor(t / 60) % 60, math.floor(t) % 60, (i % 10) * 100,
      24 - (i % 100) / 100, 10 + (i % 37) / 10, 1800 + i % 101, 30 + i % 11, -70 + i % 13, 90 + i % 11, i)
  end
  return table.concat(out, string.char(10)) .. string.char(10)
end

local LOG = "/LOGS/Heli-2026-10-01-120000.csv"
files[LOG] = makeLog(3000, 12 * 3600)

-- A page with LOG chosen for its summary, built once as the list's View button leaves it.
local function openSummary(page, isHosted)
  hosted = isHosted
  local st = find(page.wakeup, "state")
  st.selectedFile = "Heli-2026-10-01-120000.csv"
  st.selectedFilePath = LOG
  st.selectedModel = "Heli"
  st.summary = nil
  st.loading = true
  st.reading = false
  local ctx = { children = {}, x = 0, y = 0, w = 800, h = 430, requestRebuild = function() end }
  page.build(ctx)
  return st, ctx
end

local function loadPage()
  return assert(loadfile(PAGE))()
end

-- The list scan: N dated logs directly in /LOGS, names in no particular order, and one more in a
-- model folder with the file name of a log in /LOGS, so two records share a sort key. The names
-- are made before the scan, so building them is not billed to the page.
local function listingStub(count)
  local listings = { ["/LOGS"] = {}, ["/LOGS/Heli"] = { string.format("Model-%04d-10-01-120000.csv", 2000 + 7919 % math.max(count, 1)) } }
  for n = 1, count do
    listings["/LOGS"][n] = string.format("Model-%04d-10-01-120000.csv", 2000 + (n * 7919) % count)
  end
  listings["/LOGS"][count + 1] = "Heli"
  dir = function(path)
    local names, i = listings[path] or {}, 0
    return function() i = i + 1; return names[i] end
  end
end

do
  local page = loadPage()
  local newScan = find(page.build, "newScan")
  local scanForAWhile = find(page.wakeup, "scanForAWhile")
  check(newScan ~= nil and scanForAWhile ~= nil, "sort: page locals found")
  for _, count in ipairs({ 0, 25, 600, 5000 }) do
    listingStub(count)
    local scan = newScan()
    local wakeups, stopped, maxUsed, done = 0, 0, 0, false
    while not done and wakeups < 5000 do
      local ok, used, res = ceilingCall(scanForAWhile, scan, 3)
      wakeups = wakeups + 1
      if used > maxUsed then maxUsed = used end
      if ok then done = res else stopped = stopped + 1 end
    end
    local label = "sort " .. count .. " logs"
    check(done, label .. ": scan finished under the ceiling", wakeups .. " wakeups, " .. stopped .. " stopped")
    check(stopped == 0, label .. ": no wakeup stopped", stopped)
    check(#scan.found == count + 1, label .. ": every log listed once", #scan.found)
    local ordered = true
    for i = 2, #scan.found do
      if scan.found[i - 1].sortKey < scan.found[i].sortKey then ordered = false end
    end
    check(ordered, label .. ": newest first")
    local paths, unique = {}, true
    for i = 1, #scan.found do
      if paths[scan.found[i].path] then unique = false end
      paths[scan.found[i].path] = true
    end
    check(unique, label .. ": no log twice")
    check(scan.keys == nil and scan.sorted == nil, label .. ": sort tables released")
  end

-- The sort's phases stopped once at every instruction they execute, each in a scan of its own:
-- the next calls finish it, and the list is complete, unique and in order.
do
  local scanStep = find(page.wakeup, "scanStep")
  local function walked()
    local scan = newScan()
    while scan.phase ~= "keys" do scanStep(scan, 10) end
    return scan
  end
  local function finish(scan)
    local n = 0
    while not scanStep(scan, 10) do n = n + 1; if n > 100000 then error("scan does not finish") end end
  end
  listingStub(40)
  local total = 0
  local probe = walked()
  debug.sethook(function() total = total + 1 end, "", 1)
  finish(probe)
  debug.sethook()
  local bad, firstBad = 0, nil
  for stopAt = 1, total do
    local scan = walked()
    local n = 0
    local ok, err = pcall(function()
      debug.sethook(function()
        n = n + 1
        if n == stopAt then debug.sethook(); error("stop", 0) end
      end, "", 1)
      finish(scan)
      debug.sethook()
    end)
    debug.sethook()
    local ok2, err2 = pcall(finish, scan)
    local fine = (ok or err == "stop") and ok2 and #scan.found == 41
    if fine then
      local paths = {}
      for i = 1, #scan.found do
        if paths[scan.found[i].path] then fine = false end
        paths[scan.found[i].path] = true
        if i > 1 and scan.found[i - 1].sortKey < scan.found[i].sortKey then fine = false end
      end
    end
    if not fine then
      bad = bad + 1
      firstBad = firstBad or (stopAt .. ": " .. tostring(err2 or err))
    end
  end
  check(total > 100 and bad == 0, "sort stopped at each of its " .. total .. " instructions: resumes complete", firstBad)
end

  -- A wakeup stopped anywhere in the sort's phases resumes and still lists every log once, in
  -- order: a ceiling of a few hundred instructions stops nearly every call.
  listingStub(300)
  local scan = newScan()
  local calls, done = 0, false
  CEILING = 700
  while not done and calls < 100000 do
    local ok, _, res = ceilingCall(scanForAWhile, scan, 3)
    calls = calls + 1
    if ok then done = res end
  end
  CEILING = 20000
  local paths, unique = {}, true
  for i = 1, #scan.found do
    if paths[scan.found[i].path] then unique = false end
    paths[scan.found[i].path] = true
  end
  local ordered = true
  for i = 2, #scan.found do
    if scan.found[i - 1].sortKey < scan.found[i].sortKey then ordered = false end
  end
  check(done and #scan.found == 301 and unique and ordered, "sort stopped at a low ceiling: complete, unique, ordered",
    tostring(done) .. " " .. #scan.found)
end

-- #962: the summary's loading bar follows the walk. The notice is built before the walk starts
-- and not rebuilt until it ends, so the bar moves only if it reads the engine on every refresh.
for _, isHosted in ipairs({ true, false }) do
  local page = loadPage()
  local st, ctx = openSummary(page, isHosted)
  local notice = ctx.children[1]
  local label = "summary bar " .. (isHosted and "hosted" or "tool")
  check(notice ~= nil and type(notice.progress) == "function", label .. ": the bar reads a function", notice and type(notice.progress))
  for _ = 1, 3 do page.wakeup(ctx) end
  local g = find(page.wakeup, "Graph")
  local shown = notice and type(notice.progress) == "function" and notice.progress() or (notice and notice.progress)
  check(g ~= nil and g.getProgress() > 0, label .. ": the walk has moved")
  check(g ~= nil and shown == g.getProgress() and shown > 0, label .. ": the bar shows the walk's position", shown)
  local n = 0
  while st.loading and n < 10000 do page.wakeup(ctx); n = n + 1 end
  check(st.summary ~= nil, label .. ": summary read")
  page.onClose()
end

-- The engine on LOG, indexed and sized for a plot, the way the graph view leaves it.
local function indexedGraph(path)
  local G = assert(loadfile(GRAPH))()
  check(G.open(path or LOG, { stats = false }), "engine opens " .. tostring(path or LOG))
  local n = 0
  while G.isBusy() and n < 100000 do G.tick(); n = n + 1 end
  G.setGeometry(0, 0, 760, 200)
  return G
end

local function plot(G, cols)
  local ok = G.applyColumns(cols)
  local n = 0
  while G.isBusy() and n < 100000 do G.tick(); n = n + 1 end
  return ok
end

-- #963: a column chosen in two slots. Columns 3 and 4 are Vbat and Curr.
do
  local C = indexedGraph()
  check(plot(C, { 3, 4 }), "duplicate control {3,4}: applied")
  check(#C.getCurves() == 2 and not C.isCurveEmpty(1) and not C.isCurveEmpty(2), "duplicate control {3,4}: both curves drawn")
  C.close()
  -- On an engine of its own, so the choice is extracted rather than taken as the plot shown.
  local G = indexedGraph()
  check(plot(G, { 3, 3, 4 }), "duplicate {3,3,4}: applied")
  local curves = G.getCurves()
  check(#curves == 2, "duplicate {3,3,4}: the repeat is plotted once", #curves)
  local drawn = true
  for k = 1, #curves do if G.isCurveEmpty(k) then drawn = false end end
  check(drawn and curves[1].col == 3 and curves[#curves].col == 4, "duplicate {3,3,4}: Vbat and Curr both drawn")
  G.close()
end

-- #961: back from the plot to the summary keeps the index, and Show with the curves already
-- plotted reads nothing. Controls: the first plot and a changed choice do read.
for _, isHosted in ipairs({ true, false }) do
  local page = loadPage()
  local st, ctx = openSummary(page, isHosted)
  local n = 0
  while st.loading and n < 100000 do page.wakeup(ctx); n = n + 1 end
  local label = "reentry " .. (isHosted and "hosted" or "tool")
  local openGraph = find(page.build, "openGraph")
  check(openGraph ~= nil and openGraph(), label .. ": graph opens")
  local G = find(page.wakeup, "Graph")
  check(G ~= nil and not G.isBusy(), label .. ": the summary's index serves the first graph")
  G.setGeometry(0, 0, 760, 200)
  local before = reads.bytes
  check(plot(G, { 3, 4 }), label .. ": plot applied")
  check(reads.bytes > before, label .. ": the first plot reads (control)")
  before = reads.bytes
  check(plot(G, { 3, 4 }) and reads.bytes == before, label .. ": Show unchanged reads nothing", reads.bytes - before)
  G.zoom(1)
  local n = 0
  while G.isBusy() and n < 100000 do G.tick(); n = n + 1 end
  local w0, w1 = G.getWindow()
  before = reads.bytes
  check(plot(G, { 3, 4 }) and reads.bytes == before, label .. ": Show unchanged after a zoom reads nothing")
  local z0, z1 = G.getWindow()
  check(z0 == w0 and z1 == w1, label .. ": and keeps the zoomed window")
  check(not G.isCurveEmpty(1) and not G.isCurveEmpty(2), label .. ": the plot stays drawn")
  check(plot(G, { 3, 5 }) and reads.bytes > before, label .. ": a changed choice reads (control)")
  page.onBack(ctx)
  check(st.view == nil and find(page.wakeup, "Graph") == G, label .. ": back to the summary keeps the engine")
  check(#G.getCurves() == 0, label .. ": the plot's curves are released")
  before = reads.bytes
  check(openGraph() and find(page.wakeup, "Graph") == G and not G.isBusy() and reads.bytes == before,
    label .. ": graph again reads nothing", reads.bytes - before)
  check(plot(G, { 3, 4 }) and not G.isCurveEmpty(1), label .. ": a plot after re-entry is drawn")
  page.onBack(ctx)
  page.onBack(ctx)
  check(st.selectedFile == nil and find(page.wakeup, "Graph") == nil, label .. ": leaving the file releases the engine")
  page.onClose()
end

-- #961: a change of flight stopped at any of its instructions, then Show with the same curves:
-- the plot shown afterwards is of the flight selected, never the other one's left in place.
do
  local TWO = "/LOGS/Two-2026-10-01-120000.csv"
  local second = makeLog(300, 12 * 3600 + 600)
  files[TWO] = makeLog(300, 12 * 3600) .. string.sub(second, string.find(second, string.char(10), 1, true) + 1)
  local G = indexedGraph(TWO)
  local S = find(G.tick, "S")
  check(#G.getSessions() == 2, "flight change: two flights", #G.getSessions())
  local function settle() local n = 0; while G.isBusy() and n < 100000 do G.tick(); n = n + 1 end end
  local bad, total = 0, 0
  for stopAt = 1, 60 do
    G.selectSession(1); settle()
    plot(G, { 3, 4 })
    local n = 0
    local stopped = not pcall(function()
      debug.sethook(function()
        n = n + 1
        if n == stopAt then debug.sethook(); error("stop", 0) end
      end, "", 1)
      G.selectSession(2)
      debug.sethook()
    end)
    debug.sethook()
    if stopped then total = total + 1 end
    plot(G, { 3, 4 })
    local s = G.getSessions()[G.getSessionIndex()]
    local w0, w1 = G.getWindow()
    if G.isCurveEmpty(1) or w0 < s.t0 or w1 > s.t1 then bad = bad + 1 end
  end
  check(total > 5 and bad == 0, "flight change stopped at each instruction: Show plots the selected flight", bad .. " of " .. total)
  G.close()
  files[TWO] = nil
end

-- #967: a pan copies the buckets the old window shares with the new one and reads only the
-- edge. An oracle computes every bucket of the shown window from LOG's rows directly: bucket i
-- of an entry holds the rows whose (t - o) * (nb - 1) / span floors to off + i - 1, the last
-- bucket only a row at exactly t1, as a read that stops past t1 leaves it.
local function rowsOf(path, cols)
  local rows = {}
  for line in string.gmatch(files[path], "[^" .. string.char(10) .. "]+") do
    local f = {}
    for v in string.gmatch(line, "[^,]+") do f[#f + 1] = v end
    local h, mi, se, ms = string.match(f[2] or "", "^(%d%d):(%d%d):(%d%d)%.(%d%d%d)$")
    if h then
      local r = { t = ((tonumber(h) * 60 + tonumber(mi)) * 60 + tonumber(se)) * 100 + tonumber(ms) // 10 }
      for k = 1, #cols do r[k] = tonumber(f[cols[k]]) end
      rows[#rows + 1] = r
    end
  end
  return rows
end

local function oracleMismatch(e, rows, ncurves, day)
  local nb, bad = e.nb, 0
  local mn, mx = {}, {}
  for k = 1, ncurves do mn[k], mx[k] = {}, {} end
  for _, r in ipairs(rows) do
    local t = r.t + day * 8640000            -- one date: the day the index gives it
    if t >= e.t0 and t <= e.t1 then
      local i = math.floor((t - (e.o or e.t0)) * (nb - 1) / e.span) - (e.off or 0) + 1
      if i >= 1 and i <= nb then
        for k = 1, ncurves do
          local v = r[k]
          if mn[k][i] == nil or v < mn[k][i] then mn[k][i] = v end
          if mx[k][i] == nil or v > mx[k][i] then mx[k][i] = v end
        end
      end
    end
  end
  for k = 1, ncurves do
    for i = 1, nb do
      local a, b = e.min[k][i], e.max[k][i]
      if a == math.huge then a = nil end
      if b == -math.huge then b = nil end
      if a ~= mn[k][i] or b ~= mx[k][i] then bad = bad + 1 end
    end
  end
  return bad
end

-- A longer flight, so a zoomed window spans many index entries: 2 000 s, 20 000 rows.
local LONG = "/LOGS/Heli-2026-10-01-130000.csv"
files[LONG] = makeLog(20000, 13 * 3600)

do
  local G = indexedGraph(LONG)
  local S = find(G.tick, "S")
  -- A second engine on the same log reads each window the pan arrives at afresh, for the
  -- byte comparison.
  local F = indexedGraph(LONG)
  local FS = find(F.tick, "S")
  local freshRead = find(F.pan, "beginExtract")
  check(plot(F, { 3, 4 }), "pan: fresh engine plotted")
  local rows = rowsOf(LONG, { 3, 4 })
  check(plot(G, { 3, 4 }), "pan: plot applied")
  local function settle() local n = 0; while G.isBusy() and n < 100000 do G.tick(); n = n + 1 end end
  local day = S.index[1].day
  for _ = 1, 3 do G.zoom(1); settle() end
  local e = S.rbSrc
  check(e ~= nil and e.nb == S.nbuckets and e.t0 == S.winT0, "pan: zoom 3 read a window at the display's resolution")
  check(e ~= nil and oracleMismatch(e, rows, 2, day) == 0, "pan: the fresh window matches the oracle (control)", e and oracleMismatch(e, rows, 2, day))
  for _, dir in ipairs({ 1, 1, -1, -1, -1 }) do
    local before = reads.bytes
    local w0 = S.winT0
    G.pan(dir)
    settle()
    local spent = reads.bytes - before
    FS.cache = { FS.cache[1] }                -- the session copy only, too coarse to serve it
    before = reads.bytes
    freshRead(S.winT0, S.winT1)
    local n = 0
    while F.isBusy() and n < 100000 do F.tick(); n = n + 1 end
    local fresh = reads.bytes - before
    e = S.rbSrc
    local label = "pan " .. (dir > 0 and "right" or "left") .. " from " .. string.format("%.1f", w0)
    check(e ~= nil and (S.winT0 - w0) * dir > 0, label .. ": the window moved")
    check(e ~= nil and e.t0 == S.winT0 and e.t1 == S.winT1, label .. ": the window shown is the entry read")
    check(e ~= nil and oracleMismatch(e, rows, 2, day) == 0, label .. ": every bucket matches the oracle", e and oracleMismatch(e, rows, 2, day))
    check(not G.isCurveEmpty(1) and not G.isCurveEmpty(2), label .. ": both curves drawn")
    check(fresh > 0 and spent <= 0.75 * fresh, label .. ": reads at most three quarters of a fresh read",
      spent .. " of " .. fresh .. " bytes")
  end

  -- Pans whose calls are stopped at a low ceiling every other call, at points that move from
  -- round to round: no error but the ceiling's, and a plot that counts as finished matches the
  -- oracle; one that does not is read afresh by the next pan.
  for _, low in ipairs({ 150, 400, 1200, 3500 }) do
    local errors, stops, call = 0, 0, 0
    local function nextCall(fn, ...)
      call = call + 1
      CEILING = (call % 2 == 1) and (low + (call * 37) % low) or 20000
      local ok = ceilingCall(fn, ...)
      CEILING = 20000
      if not ok then stops = stops + 1 end
    end
    for _, dir in ipairs({ 1, -1, 1, 1 }) do
      nextCall(G.pan, dir)
      local n = 0
      while G.isBusy() and n < 200000 do nextCall(G.tick); n = n + 1 end
      if G.isBusy() then errors = errors + 1 end
    end
    local e = S.rbSrc
    local label = "pan stopped at " .. low
    check(errors == 0, label .. ": every pan finished")
    check(stops > 0, label .. ": the ceiling stopped calls", stops)
    check(not S.plotted or (e ~= nil and oracleMismatch(e, rows, 2, day) == 0), label .. ": a finished plot matches the oracle")
    local cachedBad = 0
    for _, c in ipairs(S.cache) do
      if c.nb == S.nbuckets and oracleMismatch(c, rows, 2, day) > 0 then cachedBad = cachedBad + 1 end
    end
    check(cachedBad == 0, label .. ": no window in the cache misses rows", cachedBad)
    G.pan(-1); settle(); G.pan(1); settle()
    e = S.rbSrc
    check(S.plotted and e ~= nil and oracleMismatch(e, rows, 2, day) == 0, label .. ": the next pans match the oracle")
  end
  G.close()
  F.close()
end

-- #966: a name is collected as it is read, so a log costs one unit of the scan, not two.
-- Wakeups as the dashboard drives the scan, three units each, until the sort.
do
  local page = loadPage()
  local newScan = find(page.build, "newScan")
  local scanForAWhile = find(page.wakeup, "scanForAWhile")
  for _, count in ipairs({ 300, 600 }) do
    listingStub(count)
    local scan = newScan()
    local wakeups = 0
    while scan.phase ~= "keys" and scan.phase ~= "sort" and wakeups < 5000 do
      scanForAWhile(scan, 3)
      wakeups = wakeups + 1
    end
    local bound = math.ceil(count / 30) + 4
    check(wakeups <= bound, "scan " .. count .. " logs: one unit per name, " .. bound .. " wakeups at most", wakeups)
  end
end

-- The same logs as before, by the same routes: every search path, a model folder in each, a
-- file reached by two paths, logs without a date in their name, files that are not logs.
local function cardStub()
  local listings = {
    ["/LOGS"] = { ".", "..", "Heli-2026-10-01-120000.csv", "Plane", "rfsuite", "notes.txt", "Old.csv", "Sheet.csv" },
    ["/LOGS/Plane"] = { "Plane-2026-10-02-090000.csv", "x.txt", "flight.csv" },
    ["/LOGS/rfsuite"] = { "telemetry", "Goblin" },
    ["/LOGS/rfsuite/telemetry"] = { "Top-2026-10-03-100000.csv" },
    ["/LOGS/rfsuite/Goblin"] = { "Goblin-2026-10-04-110000.csv", "Goblin-2026-10-05-110000.csv" }
  }
  files["/LOGS/Old.csv"] = "Date,Time,Vbat(V)" .. string.char(10) .. "2026-09-30,08:00:00.000,24.0" .. string.char(10)
  files["/LOGS/Sheet.csv"] = "Name,Value" .. string.char(10) .. "a,1" .. string.char(10)
  -- No date in its name: listed by its header, its model from the folder.
  files["/LOGS/Plane/flight.csv"] = "Date,Time,Vbat(V)" .. string.char(10) .. "2026-10-02,10:00:00.000,24.0" .. string.char(10)
  dir = function(path)
    local names, i = listings[path] or {}, 0
    return function() i = i + 1; return names[i] end
  end
end

local CARD = {
  ["/LOGS/rfsuite/telemetry/Top-2026-10-03-100000.csv"] = "Top",
  ["/LOGS/rfsuite/Goblin/Goblin-2026-10-04-110000.csv"] = "Goblin",
  ["/LOGS/rfsuite/Goblin/Goblin-2026-10-05-110000.csv"] = "Goblin",
  ["/LOGS/Heli-2026-10-01-120000.csv"] = "Heli",
  ["/LOGS/Plane/Plane-2026-10-02-090000.csv"] = "Plane",
  ["/LOGS/Old.csv"] = false,
  ["/LOGS/Plane/flight.csv"] = "Plane"
}

local function cardResult(scan, label)
  local seen, n, ok = {}, 0, true
  for _, info in ipairs(scan.found) do
    local want = CARD[info.path]
    if want == nil or seen[info.path] or (want or nil) ~= info.model then
      ok = false
      print("  unexpected " .. tostring(info.path) .. " model " .. tostring(info.model))
    end
    seen[info.path] = true
    n = n + 1
  end
  check(ok and n == 7, label .. ": the seven logs, each once, with their models", n)
  local ordered = true
  for i = 2, #scan.found do
    if scan.found[i - 1].sortKey < scan.found[i].sortKey then ordered = false end
  end
  check(ordered, label .. ": newest first")
end

do
  local page = loadPage()
  local newScan = find(page.build, "newScan")
  local scanForAWhile = find(page.wakeup, "scanForAWhile")
  cardStub()
  local scan = newScan()
  local n = 0
  while not scanForAWhile(scan, 3) and n < 1000 do n = n + 1 end
  cardResult(scan, "card scan")
  check(scan.read == 17, "card scan: every name counted as read once", scan.read)
  for _, low in ipairs({ 150, 300, 700 }) do
    cardStub()
    scan = newScan()
    local calls, done, stops = 0, false, 0
    while not done and calls < 100000 do
      calls = calls + 1
      CEILING = (calls % 2 == 1) and (low + (calls * 37) % low) or 20000
      local ok, _, res = ceilingCall(scanForAWhile, scan, 3)
      CEILING = 20000
      if ok then done = res else stops = stops + 1 end
    end
    check(done and stops > 0, "card scan stopped at " .. low .. ": finished after stops", stops)
    cardResult(scan, "card scan stopped at " .. low)
  end
end

-- The whole card scan stopped once at every instruction it executes, each in a scan of its own:
-- the next calls finish it, and every log is listed once with its model. A stop between the
-- directory iterator's read and the name being held is among them.
do
  local page = loadPage()
  local newScan = find(page.build, "newScan")
  local scanStep = find(page.wakeup, "scanStep")
  local function finish(scan)
    local n = 0
    while not scanStep(scan, 10) do n = n + 1; if n > 100000 then error("scan does not finish") end end
  end
  cardStub()
  local total = 0
  local probe = newScan()
  debug.sethook(function() total = total + 1 end, "", 1)
  finish(probe)
  debug.sethook()
  local bad, firstBad = 0, nil
  for stopAt = 1, total do
    cardStub()
    local scan = newScan()
    local n = 0
    local ok, err = pcall(function()
      debug.sethook(function()
        n = n + 1
        if n == stopAt then debug.sethook(); error("stop", 0) end
      end, "", 1)
      finish(scan)
      debug.sethook()
    end)
    debug.sethook()
    local ok2, err2 = pcall(finish, scan)
    local fine = (ok or err == "stop") and ok2 and #scan.found == 7
    if fine then
      local seen = {}
      for _, info in ipairs(scan.found) do
        local want = CARD[info.path]
        if want == nil or seen[info.path] or (want or nil) ~= info.model then fine = false end
        seen[info.path] = true
      end
    end
    if not fine then
      bad = bad + 1
      firstBad = firstBad or (stopAt .. ": " .. tostring(err2 or err) .. " found " .. #scan.found)
    end
  end
  check(total > 500 and bad == 0, "card scan stopped at each of its " .. total .. " instructions: every log once", firstBad)
end

-- #970: the log's clock. Rows as EdgeTX writes them, from (date, seconds) pairs.
local function rowsLog(rows)
  local out = { "Date,Time,Vbat(V),Curr(A)" }
  for i, r in ipairs(rows) do
    local t = r[2]
    out[#out + 1] = string.format("%s,%02d:%02d:%02d.%03d,%.2f,%.2f", r[1],
      math.floor(t / 3600), math.floor(t / 60) % 60, math.floor(t) % 60, math.floor(t * 1000 + 0.5) % 1000,
      (r[3] or 20) + i % 7, 5 + i % 3)
  end
  return table.concat(out, string.char(10)) .. string.char(10)
end

-- 512 rows from `firstStart` and then 512 rows from `secondStart`, ten a second, one date; the
-- first block's voltage is 30 to 36, the second's 10 to 16.
local function twoBlocks(firstStart, secondStart)
  local rows = {}
  for i = 0, 511 do rows[#rows + 1] = { "2026-10-01", firstStart + i / 10, 30 } end
  for i = 0, 511 do rows[#rows + 1] = { "2026-10-01", secondStart + i / 10, 10 } end
  return rowsLog(rows)
end

for _, case in ipairs({ { "clock set back", 12 * 3600 + 600, 12 * 3600 }, { "control: forward", 12 * 3600, 12 * 3600 + 1200 } }) do
  local path = "/LOGS/Clock-2026-10-01-120000.csv"
  files[path] = twoBlocks(case[2], case[3])
  local G = indexedGraph(path)
  check(#G.getSessions() == 2, case[1] .. ": two sessions", #G.getSessions())
  for i = 1, 2 do
    G.selectSession(i)
    plot(G, { 3, 4 })
    check(not G.isCurveEmpty(1) and not G.isCurveEmpty(2), case[1] .. ": session " .. i .. " plotted")
    local lo, hi = G.getCurveRange(1)
    local own
    if i == 1 then own = lo ~= nil and lo > 25 else own = hi ~= nil and hi < 20 end
    check(own, case[1] .. ": session " .. i .. " reads only its own rows",
      tostring(lo) .. ".." .. tostring(hi))
  end
  G.close()
  files[path] = nil
end

-- Across midnight: the summary counts on into the next day. Control: the same ten seconds on one
-- day.
for _, case in ipairs({
  { "midnight", { { "2026-10-01", 86395 }, { "2026-10-02", 5 } } },
  { "control: one day", { { "2026-10-01", 3600 }, { "2026-10-01", 3610 } } }
}) do
  local path = "/LOGS/Night-2026-10-01-235955.csv"
  files[path] = rowsLog(case[2])
  local G = assert(loadfile(GRAPH))()
  check(G.open(path, { stats = true }), case[1] .. ": opens")
  local n = 0
  while G.isBusy() and n < 1000 do G.tick(); n = n + 1 end
  local summary = G.getSummary()
  check(summary ~= nil and summary.durationStr == "00:10 min", case[1] .. ": ten seconds", summary and summary.durationStr)
  G.close()
  files[path] = nil
end

-- #970: a row the chosen columns do not match still ends its session. The session 1 rows read
-- 24, a short row with no voltage sets the clock back, and the session 2 row after it reads 48.
do
  local path = "/LOGS/Short-2026-10-01-120000.csv"
  local nl = string.char(10)
  files[path] = "Date,Time,Vbat(V)" .. nl
    .. "2026-10-01,12:00:00.000,24" .. nl .. "2026-10-01,12:00:10.000,24" .. nl
    .. "2026-10-01,12:00:05.000" .. nl .. "2026-10-01,12:00:10.000,48" .. nl
  local G = indexedGraph(path)
  check(#G.getSessions() == 2, "short rollback row: two sessions", #G.getSessions())
  G.selectSession(1)
  plot(G, { 3 })
  local lo, hi = G.getCurveRange(1)
  check(hi ~= nil and hi < 30, "short rollback row: session 1 reads only its own rows", tostring(lo) .. ".." .. tostring(hi))
  G.close()
  files[path] = nil
end

-- #970: a stop at the change of date counts no day twice: midnight, stopped at every
-- instruction the summary walk runs inside scanLine, never more than the ten seconds. (A stop in
-- the line pump can hand a chunk's rows on twice; that is the pump's, and not judged here.)
do
  local path = "/LOGS/Night-2026-10-01-235955.csv"
  files[path] = rowsLog({ { "2026-10-01", 86395 }, { "2026-10-02", 0 }, { "2026-10-02", 5 } })
  local function walk(G)
    local n = 0
    while G.isBusy() and n < 1000 do G.tick(); n = n + 1 end
  end
  local total = 0
  do
    local G = assert(loadfile(GRAPH))()
    G.open(path, { stats = true })
    debug.sethook(function() total = total + 1 end, "", 1)
    walk(G)
    debug.sethook()
    G.close()
  end
  local bad, firstBad, inside = 0, nil, 0
  for stopAt = 1, total do
    local G = assert(loadfile(GRAPH))()
    G.open(path, { stats = true })
    local scanLine = debug.getinfo(find(G.tick, "scanLine"), "S")
    local n, inScanLine = 0, false
    pcall(function()
      debug.sethook(function()
        n = n + 1
        if n == stopAt then
          local f = debug.getinfo(2, "Sl")
          inScanLine = f.source == scanLine.source and f.currentline >= scanLine.linedefined
            and f.currentline <= scanLine.lastlinedefined
          debug.sethook()
          error("stop", 0)
        end
      end, "", 1)
      walk(G)
      debug.sethook()
    end)
    debug.sethook()
    walk(G)
    local summary = G.getSummary()
    local text = summary and summary.durationStr
    -- A stop inside the line pump can drop a row, so a shorter duration is possible; a longer
    -- one means a day was counted twice.
    if inScanLine then inside = inside + 1 end
    if inScanLine and text ~= nil and text ~= "00:10 min" and text ~= "00:05 min" and text ~= "00:00 min" then
      bad = bad + 1
      firstBad = firstBad or (stopAt .. ": " .. tostring(text))
    end
    G.close()
  end
  check(inside > 50 and bad == 0, "midnight walk stopped at each of its " .. inside .. " instructions in scanLine: no day counted twice", firstBad)
  files[path] = nil
end

print(string.format("Logs page: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
