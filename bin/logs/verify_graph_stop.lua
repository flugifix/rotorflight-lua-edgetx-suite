-- Host regression checks for interrupted Logs graph choices and extraction completion.
local checks, failures = 0, 0
local function equal(actual, expected, label)
  checks = checks + 1
  if actual ~= expected then
    failures = failures + 1
    print(string.format("FAIL %s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local gpath = "src/rfsuite/app/pages/logs/graph.lua"
local source = "@" .. gpath
local rows, passes, maxTicks = 1024, 60, 256
local rio, originalFstat = io, fstat
local csvpath, fixture
local handles = {}

-- graph.lua uses EdgeTX's file functions, not desktop file methods. Keep the
-- desktop library for fixture creation and stdout; all graph reads use real files.
io = {
  open = function(path)
    local fh = rio.open(path, "rb")
    if fh then handles[fh] = true end
    return fh
  end,
  read = function(fh, n) return fh:read(n) end,
  close = function(fh)
    local ok, err = fh:close()
    handles[fh] = nil
    return ok, err
  end,
  seek = function(fh, off) return fh:seek("set", off) end
}
fstat = function(path)
  local fh = rio.open(path, "rb")
  if not fh then return nil end
  local size = fh:seek("end")
  fh:close()
  return { size = size }
end

local function makeFixture()
  csvpath = os.tmpname()
  fixture = assert(rio.open(csvpath, "wb"))
  assert(fixture:write("Date,Time,Vbat(V),Curr(A),Hspd(rpm),EscT(C),1RSS(dB),2RSS(dB),RQly(%)\n"))
  -- Ten samples per second, one session, and more than ten 80-line extraction
  -- ticks. Every selected column varies, so an empty placeholder cannot pass.
  for i = 0, rows - 1 do
    assert(fixture:write(string.format(
      "2026-01-01,12:%02d:%02d.%03d,%.2f,%.2f,%d,%d,%d,%d,%d\n",
      math.floor(i / 600), math.floor(i / 10) % 60, (i % 10) * 100,
      24 - (i % 100) / 100, 10 + (i % 37) / 10, 1800 + i % 101,
      30 + i % 11, -70 + i % 13, -80 + i % 17, 90 + i % 11)))
  end
  assert(fixture:close())
  fixture = nil
end

local function armedCall(state, fn, ...)
  local seen = {}
  debug.sethook(function(_, line)
    if debug.getinfo(2, "S").source ~= source then return end
    if not seen[line] then
      seen[line] = true
      state.lines[#state.lines + 1] = line
    end
    if not state.injected and line == state.stopLine then
      state.injected = true
      -- One stop, before this line's first execution. An inner pcall may catch
      -- it; the remainder then runs freely, just as in the desktop probe.
      debug.sethook()
      error("CPU limit", 0)
    end
  end, "l")
  local result = table.pack(pcall(fn, ...))
  debug.sethook()
  return result
end

-- Fingerprint columns, ranges, all points and the window, as in the probe.
local function fnv(s)
  local h = 2166136261
  for i = 1, #s do h = ((h ~ string.byte(s, i)) * 16777619) & 0xffffffff end
  return string.format("%08x", h)
end

local function fingerprint(G)
  local parts, drawn, points = {}, 0, 0
  local curves = G.getCurves()
  for k = 1, #curves do
    local pts, empty = G.getPoints(k), G.isCurveEmpty(k)
    if not empty then drawn = drawn + 1 end
    points = points + #pts
    local lo, hi = G.getCurveRange(k)
    parts[#parts + 1] = string.format("c%d col=%s empty=%s n=%d lo=%s hi=%s", k,
      tostring(curves[k].col), tostring(empty), #pts, tostring(lo), tostring(hi))
    for i = 1, #pts do parts[#parts + 1] = pts[i][1] .. "," .. pts[i][2] end
  end
  local w0, w1 = G.getWindow()
  parts[#parts + 1] = "win " .. tostring(w0) .. " " .. tostring(w1)
  return fnv(table.concat(parts, ";")), #curves, drawn, points
end

local function colsByName(G, names)
  local out, byName = {}, {}
  for _, c in ipairs(G.getColumns()) do byName[c.name] = c.col end
  for _, name in ipairs(names) do
    out[#out + 1] = assert(byName[name], "CSV needs column " .. name)
  end
  return out
end

local function untilPhase(G, phase)
  local ticks = 0
  while G.getPhase() ~= phase and ticks < maxTicks do
    G.tick()
    ticks = ticks + 1
  end
  assert(G.getPhase() == phase, "setup did not reach phase " .. tostring(phase))
end

local function setup(G, shape)
  assert(G.open(csvpath, { stats = true }), "open failed")
  untilPhase(G, nil)
  assert(G.getError() == nil, "summary failed: " .. tostring(G.getError()))
  assert(#G.getSessions() > 0, "no session")
  assert(G.getSummary().sampleCount == rows, "summary did not read all synthetic rows")
  G.setGeometry(2, 40, 476, 180) -- 119 display buckets, 476 in the session copy.
  local four = colsByName(G, { "Vbat", "Curr", "Hspd", "EscT" })
  local two = colsByName(G, { "1RSS", "2RSS" })
  local one = colsByName(G, { "RQly" })
  local pre, post, phase
  if shape == "R1" then pre, post, phase = four, two, "extract"
  elseif shape == "R2" then pre, post, phase = one, four, "rebkt"
  elseif shape == "S3" then pre, post, phase = four, four, "extract"
  else error("unknown shape: " .. shape) end
  assert(G.applyColumns(pre), "initial choice refused")
  untilPhase(G, phase)
  if shape == "R1" then
    for _ = 1, 10 do G.tick() end
    assert(G.getPhase() == "extract", "CSV needs a session longer than 10 extract ticks")
  end
  return post
end

local function scenario(G, shape, state, baseline)
  local post = setup(G, shape)
  if shape == "S3" then
    -- Find the ending tick without a hook, then replay from a clean open. Even
    -- a stop on the phase branch must land in the extraction-ending tick.
    local endTick = 0
    repeat
      G.tick()
      endTick = endTick + 1
      assert(endTick < maxTicks, "extraction did not end")
    until G.getPhase() ~= "extract"
    assert(G.getPhase() == "rebkt", "control extraction did not reach rebkt")
    G.close()
    post = setup(G, shape)
    for _ = 1, endTick - 1 do G.tick() end
    assert(G.getPhase() == "extract", "ending tick replay drifted")
    local result = armedCall(state, G.tick)
    assert(result[1] or (state.injected and result[2] == "CPU limit"),
      "unexpected ending-tick error: " .. tostring(result[2]))
  else
    local press = armedCall(state, G.applyColumns, post)
    assert((press[1] and press[2] == true) or (state.injected and press[2] == "CPU limit"),
      "unexpected press error or refusal: " .. tostring(press[2]))
  end
  assert(state.injected == (state.stopLine > 0), "requested stop was not injected")
  assert(#state.lines > 0, "hook observed no graph lines")

  -- Keep ticking after every failure and attempt recovery even when following
  -- ticks failed. Aggregate diagnostics into one FAIL line for this stop.
  local problems = {}
  local function expect(condition, message)
    if not condition then problems[#problems + 1] = message end
  end
  local errors, firstError = 0, nil
  for _ = 1, passes do
    local ok, err = pcall(G.tick)
    if not ok then errors = errors + 1; firstError = firstError or err end
  end
  expect(errors == 0, "follow ticks raised " .. errors .. " errors: " .. tostring(firstError))
  local follow = table.pack(pcall(fingerprint, G))
  expect(follow[1], "follow fingerprint failed: " .. tostring(follow[2]))
  if state.stopLine == 0 then
    expect(not G.isBusy() and follow[1] and follow[3] == #post and follow[4] == #post,
      "uninterrupted control did not draw every selected curve")
  end

  local press = table.pack(pcall(G.applyColumns, post))
  expect(press[1] and press[2] == true, "recovery choice failed: " .. tostring(press[2]))
  local recoveryPasses, recoveryErrors, recoveryError = 0, 0, nil
  while G.isBusy() and recoveryPasses < maxTicks do
    recoveryPasses = recoveryPasses + 1
    local ok, err = pcall(G.tick)
    if not ok then recoveryErrors = recoveryErrors + 1; recoveryError = recoveryError or err end
  end
  expect(recoveryErrors == 0,
    "recovery ticks raised " .. recoveryErrors .. " errors: " .. tostring(recoveryError))
  expect(not G.isBusy(), "recovery did not finish within " .. maxTicks .. " ticks")
  expect(G.getPhase() == nil, "recovery phase is " .. tostring(G.getPhase()))
  expect(G.getError() == nil, "recovery engine error: " .. tostring(G.getError()))
  local recovered = table.pack(pcall(fingerprint, G))
  expect(recovered[1], "recovery fingerprint failed: " .. tostring(recovered[2]))
  if recovered[1] then
    local fp, curves, drawn, points = table.unpack(recovered, 2, 5)
    expect(curves == #post, "recovery curve count is " .. curves)
    expect(drawn == #post, "recovery drawn curve count is " .. drawn)
    expect(points > 2 * #post, "recovery has only placeholder points")
    if baseline then expect(fp == baseline, "recovery fingerprint differs from control: " .. fp) end
    state.fingerprint = fp
  end
  if #problems > 0 then error(table.concat(problems, "; "), 0) end
end

local function runScenario(shape, stopLine, baseline)
  local state = { stopLine = stopLine, lines = {}, injected = false }
  local G
  local ok, err = pcall(function()
    G = dofile(gpath)
    scenario(G, shape, state, baseline)
  end)
  debug.sethook()
  if G then
    local closed, closeError = pcall(G.close)
    if not closed then ok, err = false, tostring(err) .. "; close: " .. tostring(closeError) end
  end
  -- Also release handles if a scenario failed before the module could close.
  for fh in pairs(handles) do
    local closed, closeError = pcall(io.close, fh)
    if not closed then ok, err = false, tostring(err) .. "; handle: " .. tostring(closeError) end
  end
  equal(ok and "ok" or (string.gsub(tostring(err), "[\r\n]+", " ")), "ok",
    string.format("shape=%s line=%d", shape, stopLine))
  return state, ok
end

local ok, err = pcall(function()
  makeFixture()
  for _, shape in ipairs({ "R1", "R2", "S3" }) do
    local beforeChecks, beforeFailures = checks, failures
    -- Line 0 is the positive control and discovers every executed graph line,
    -- including helpers. Each replay starts with a new real module instance.
    local control, controlOk = runScenario(shape, 0)
    table.sort(control.lines)
    for _, line in ipairs(control.lines) do
      runScenario(shape, line, controlOk and control.fingerprint or nil)
    end
    print(string.format("Graph stop %s: %d stops, %d checks, %d failures", shape,
      #control.lines, checks - beforeChecks, failures - beforeFailures))
  end
end)
debug.sethook()
io, fstat = rio, originalFstat
if not ok then equal((string.gsub(tostring(err), "[\r\n]+", " ")), "ok", "run") end
if fixture then fixture:close() end
if csvpath then
  local removed, removeError = os.remove(csvpath)
  if not removed then equal(removeError, nil, "temporary CSV cleanup") end
end
print(string.format("Graph stop: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
