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

print(string.format("Logs page: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
