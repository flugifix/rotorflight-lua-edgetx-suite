-- The real dashboard entry points must revoke output before fast sampling or a build can run.
local Stubs = dofile("bin/accounting/stubs/edgetx.lua")
local FC = dofile("bin/accounting/stubs/fc.lua")
Stubs.install(arg[1] or ".")
FC.install(Stubs)
Stubs.reset()
FC.reset()
local Runtime = rfsuite.require("widgets/dashboard/runtime.lua")
local Drive = rfsuite.require("widgets/dashboard/inflight/drive.lua")
local Input = rfsuite.require("widgets/dashboard/inflight/input.lua")
local readBoard = dofile("bin/dashboard/inflight_board_fixture.lua")(rfsuite.require)
local passed, failed, checks = 0, {}, 0
local function check(value, message)
  checks = checks + 1
  assert(value, message)
end
local function scenario(name, run)
  local ok, err = pcall(run)
  if ok then passed = passed + 1; print("PASS " .. name)
  else failed[#failed + 1] = name .. ": " .. tostring(err); print("FAIL " .. failed[#failed]) end
end
local function fixture(armed)
  local widget = Runtime.new({x = 0, y = 0, w = 480, h = 320}, {})
  widget.preferences.general = {preview_inflight_tuning = true}
  widget.preferences.inflight = {enabled = true}
  widget.state.armed, widget.state.armedSeen, widget.state.fblConnected = armed, true, true
  widget._foreground, widget.inflightFullscreen = true, true
  local writes = {}
  local radio = {
    now = getTime, flightMode = function() return 2 end,
    sensor = function(name) if name == "AdjF" then return 0 elseif name == "PID#" or name == "RTE#" then return 1 end end,
    switchValue = function() return false end, channelUs = function() return nil end,
    globalVariableDetails = function() end, mixesCount = function() end, flightModeData = function() end,
    setGlobalVariable = function(index, fm, value) writes[#writes + 1] = {index, fm, value}; return true end
  }
  local d = readBoard(Drive.newDrive(radio, Drive.settings(widget.preferences, {})))
  d._source, d._radioSource = widget.modelPreferences, widget.preferences
  d._checkedAt, d._checkResult = getTime(), "ok"
  d.sessionProfiles = {pid = {[1] = true}, rate = {[1] = true}}
  d.profileValues = {pid = {[1] = {}}, rate = {[1] = {}}, global = {}}
  d.profilePrevious = {pid = {}, rate = {}, global = {}}
  d:watchProfiles()
  d.open, d.live, d.phase = true, true, armed and "live" or "ground"
  d.baseline, d.primedValues = {identity = "control"}, {[18] = 100}
  widget._inflight = d
  return widget, d, writes
end
local function energize(d, writes)
  d.live, d.phase, d.open = true, "live", true
  d:ensureBankArmed()
  check(d:dispatch("step", 1, "touch"), "positive control: a visible live surface steps")
  check(d.written ~= 0 and (d.bankWritten or 0) ~= 0 and #writes > 0, "positive control: both variables are active")
end
local function cleared(d, writes, before)
  local seen = {}
  for i = before + 1, #writes do
    local write = writes[i]
    check(write[3] == 0, "every write after release loss is zero")
    check(write[2] == 2, "cleanup clears the flight mode that owns output")
    seen[write[1]] = true
  end
  check(seen[d.settings.bank_gvar - 1] and seen[d.settings.value_gvar - 1], "both next model writes are zero in the same pass: bank="
    .. tostring(d.bankWritten) .. " value=" .. tostring(d.written) .. " writes=" .. (#writes - before))
  check(not d.live and d.written == 0 and d.bankWritten == 0, "release and both outputs are cleared")
end
local function job(widget)
  widget._job = {kind = "control", oneShot = true, step = function() return true end}
end

scenario("foreground open takes effect before a pending job", function()
  local widget, d = fixture(true)
  d.live, d.open, d.phase = false, false, "ground"
  job(widget); widget:refresh(0, nil)
  check(d.live and (d.bankWritten or 0) ~= 0 and d.phase == "live", "open is effective on this foreground pass")
end)
scenario("quick-menu opening takes effect on its native event pass", function()
  local widget, d = fixture(true)
  d.live, d.open, d.phase, widget.inflightFullscreen = false, false, "ground", nil
  local Menu = rfsuite.require("widgets/dashboard/fullscreen_menu.lua")
  local entry = Menu.entry(widget, "inflight_tuning")
  check(entry and type(entry.press) == "function", "positive control: the quick menu exposes tuning")
  local saved = lvgl.onEvent
  lvgl.onEvent = function() entry.press() end
  job(widget); widget:refresh(0, nil)
  lvgl.onEvent = saved
  check(d.live and (d.bankWritten or 0) ~= 0, "menu opening releases before this event pass returns")
end)
scenario("setup fault and pending trims refuse output", function()
  local widget, d, writes = fixture(false)
  energize(d, writes)
  d.phase, d._checkResult = "ground", {"same_gvar"}
  local before = #writes
  d:evaluateInterlock(getTime(), true)
  cleared(d, writes, before)
  d.settings.trims, d.trimsResolved = true, false
  local scans = 0
  d.radio.switchList = function() scans = scans + 1; return {}, 1 end
  before = #writes
  d:evaluateInterlock(getTime(), true)
  check(not d.live and #writes == before and scans == 1, "a pending trim walk cannot release output")
  d:evaluateInterlock(getTime(), false)
  d:evaluateInterlock(getTime(), false)
  check(scans == 1, "closed tuning performs no trim discovery")
end)
scenario("closed tuning performs no ground MSP work", function()
  local widget, d = fixture(false)
  widget.inflightFullscreen, d.live, d.open = nil, false, false
  local Prime = rfsuite.require("widgets/dashboard/inflight/prime.lua")
  local saved, calls = Prime.tick, 0
  Prime.tick = function() calls = calls + 1 end
  for _ = 1, 4 do Stubs.tick(); widget:refresh(0, nil) end
  Prime.tick = saved
  check(calls == 0, "quick menu and zone do not advance a ground job")
end)

for _, close in ipairs({"release", "touch", "RTN"}) do
  scenario(close .. " close and reopen repeats a refused ground setup check", function()
    local widget, d = fixture(false)
    d.live, d._checkResult, d._checkFault = false, {"same_gvar"}, true
    if close == "release" then d:evaluateInterlock(getTime(), false)
    else Input.dispatch(widget, close == "touch" and "close" or "back", nil, close == "touch" and "touch" or "key") end
    check(d._checkedAt == nil, "closing a refused surface invalidates its verdict")
    d:evaluateInterlock(getTime(), true)
    check(d.live and not d._checkFault, "repaired setup is checked again and released on reopening")
  end)
end

scenario("opening and closing take effect without a seed or delay", function()
  local widget, d, writes = fixture(false)
  d.live, d.phase, d.open = false, nil, false
  d:evaluateInterlock(getTime(), true)
  check(d.live, "first open input is immediately live")
  energize(d, writes)
  local before = #writes
  d:evaluateInterlock(getTime(), false)
  cleared(d, writes, before)
end)
for _, exit in ipairs({"firmware", "background", "radio_disabled", "preview_disabled"}) do
  scenario(exit .. " cancels a queued tuning build", function()
    local widget, d = fixture(true)
    local builds = 0
    widget.renderKey, widget._cachedTuningKey = "tuning|control", "tuning|control"
    widget._job = {kind = "tuning_fs", oneShot = true, step = function() builds = builds + 1; return true end}
    if exit == "firmware" then widget:refresh(nil, nil)
    elseif exit == "background" then widget:background()
    else
      if exit == "radio_disabled" then widget.preferences.inflight.enabled = false
      else widget.preferences.general.preview_inflight_tuning = false end
      widget:refresh(0, nil)
    end
    check(builds == 0, "a closed tuning build never executes")
    check(widget._job == nil or widget._job.kind ~= "tuning_fs", "a closed surface retains no tuning build")
    check(widget.renderKey ~= "tuning|control" and widget._cachedTuningKey == nil, "closure invalidates the tuning scene")
  end)
  scenario(exit .. " clears before a pending job and stays closed", function()
    local widget, d, writes = fixture(true)
    energize(d, writes)
    local before, baseline, fired = #writes, d.baseline, d.fired
    job(widget)
    if exit == "firmware" then widget:refresh(nil, nil)
    elseif exit == "background" then widget:background()
    else
      if exit == "radio_disabled" then widget.preferences.inflight.enabled = false
      else widget.preferences.general.preview_inflight_tuning = false end
      widget:refresh(0, nil)
    end
    cleared(d, writes, before)
    check(not widget.inflightFullscreen, "exit consumes the visit; recovery needs a quick-menu open")
    check(d.baseline == baseline and d.fired == fired, "pause retains session and comparison")
    widget.preferences.inflight.enabled = true
    widget.preferences.general.preview_inflight_tuning = true
    widget.state.fblConnected = true
    for _ = 1, 3 do job(widget); widget:refresh(0, nil) end
    for i = before + 1, #writes do check(writes[i][3] == 0, "foreground/link/feature recovery cannot resume output") end
    check(not d:dispatch("step", 1, "touch"), "stale callback cannot step after exit")
  end)
end
scenario("link loss clears output and automatically resumes the same flight", function()
  local widget, d, writes = fixture(true)
  d.group, d.entry = 2, 3
  local cell = d.groups[2].entries[3]
  d.bank, d.row = cell.bank, cell.row
  energize(d, writes)
  local before, baseline, fired = #writes, d.baseline, d.fired
  widget.state.fblConnected = false
  job(widget); widget:refresh(0, nil)
  cleared(d, writes, before)
  check(widget.inflightFullscreen == true, "link loss preserves the fullscreen visit")
  check(d.phase == "live" and d.group == 2 and d.entry == 3, "link pause retains flight phase and selection")
  local pausedWrites = #writes
  for _ = 1, 20 do
    Stubs.tick(); job(widget); widget:refresh(0, nil)
    check(not d.live and #writes == pausedWrites, "no model write while the link remains down")
  end
  check(not d:dispatch("step", 1, "touch"), "stale step callback cannot write while disconnected")
  check(#writes == pausedWrites, "the disconnected callback leaves both variables zero")
  widget.state.fblConnected = true
  d.radio.channelUs = function() return 998 end
  job(widget); widget:refresh(0, nil)
  check(widget.inflightFullscreen and d.live and d.phase == "live", "link return automatically releases the existing visit")
  check(d.group == 2 and d.entry == 3 and d.bank == cell.bank and d.row == cell.row,
    "automatic resume preserves the same parameter despite a stale channel echo")
  check(d.baseline == baseline and d.fired == fired, "automatic resume retains the session and step count")
  for i = pausedWrites + 1, #writes do
    if writes[i][1] == d.settings.value_gvar - 1 then check(writes[i][3] == 0, "resume never replays the interrupted pulse") end
  end
  check(d.bankWritten == d.bankValues[cell.bank] and d.bankFm == 2, "automatic resume drives the retained bank in its owning flight mode")
  check(d:dispatch("step", 1, "touch") and d.fired == fired + 1, "positive control: a fresh step is accepted after automatic resume")
end)
scenario("link-lost tuning takes precedence over startup and theme reload", function()
  local widget, d = fixture(true)
  local Screen = rfsuite.require("widgets/dashboard/inflight/screen.lua")
  widget.state.fblConnected = false
  widget.theme, widget.connectionReady, widget._viewStack = nil, false, nil
  widget._themeReloadPending, widget.flightMode = true, "preflight"
  widget._lastWorkTick = getTime() / 100
  widget:refresh(0, nil)
  check(widget._job and widget._job.kind == "tuning_fs", "the disconnected visit queues tuning instead of a connection splash")
  widget:refresh(0, nil)
  check(widget._treeKind == "tuning_fs" and d.linkLost and widget.inflightFullscreen,
    "the paused fullscreen is drawn without a loaded theme")
end)
scenario("connection-state drop pauses in the same logic pass", function()
  local widget, d, writes = fixture(true)
  energize(d, writes)
  local Msp = rfsuite.require("tasks/msp/runtime.lua")
  local saved, calls = Msp.isFblConnected, 0
  Msp.isFblConnected = function() calls = calls + 1; return false end
  widget.lastFblConnected, widget._lastLogicTick, widget._lastWorkTick = true, -10000, nil
  widget._lastTelemetryReadAt = getTime() / 100
  local before = #writes
  local ok, err = pcall(function() widget:refresh(0, nil) end)
  Msp.isFblConnected = saved
  check(ok, tostring(err))
  check(calls > 0 and not widget.state.fblConnected and not widget.lastFblConnected,
    "positive control: the real logic pass observed the disconnect edge")
  cleared(d, writes, before)
  check(widget.inflightFullscreen and widget.state.inflight and widget.state.inflight.linkLost,
    "connection-state cleanup retains and publishes the disconnected visit")
end)
scenario("reconnect arm-latch reset cannot start a new flight", function()
  local widget, d, writes = fixture(true)
  d.group, d.entry = 2, 3
  local cell = d.groups[2].entries[3]
  d.bank, d.row = cell.bank, cell.row
  energize(d, writes)
  widget.state.fblConnected = false
  job(widget); widget:refresh(0, nil)
  local before = #writes
  widget.state.fblConnected, widget.state.armed, widget.state.armedSeen = true, false, false
  job(widget); widget:refresh(0, nil)
  check(not d.live and d.phase == "live" and d.group == 2 and d.entry == 3 and #writes == before,
    "unknown arm state on reconnect cannot reset the selection or release output")
  widget.state.armed, widget.state.armedSeen = true, true
  job(widget); widget:refresh(0, nil)
  check(d.live and d.group == 2 and d.entry == 3, "fresh armed telemetry automatically resumes the same flight")
end)
for _, armed in ipairs({true, false}) do
  scenario("link-lost surface replaces the " .. (armed and "live" or "ground") .. " scene", function()
    local widget, d = fixture(armed)
    local Screen = rfsuite.require("widgets/dashboard/inflight/screen.lua")
    local key = Screen.renderKey({phase = d.phase, live = true})
    local builds, nodes = 0, {}
    widget.i18n = {t = function(_, fallback) return fallback end}
    widget._job = {kind = "tuning_fs", oneShot = true, step = function()
      builds = builds + 1
      Screen.buildFullscreen(nodes, widget)
      return true
    end}
    widget.state.fblConnected = false
    widget:refresh(0, nil)
    check(widget.inflightFullscreen and builds == 1, "the queued tuning build draws the paused visit")
    local text, controls = false, 0
    local function walk(tree)
      for _, node in ipairs(tree) do
        local value = type(node.text) == "function" and node.text() or node.text
        if value == "No FC link" then text = true end
        if node.scrolled or node.type == "momentaryButton" then controls = controls + 1 end
        if node.children then walk(node.children) end
      end
    end
    walk(nodes)
    check(text and controls == 0, "paused surface shows the existing no-link text without tuning controls")
    check(Screen.renderKey(widget.state.inflight or {}) ~= key, "link loss changes the retained scene key in every phase")
  end)
end
for _, exit in ipairs({"firmware", "background", "radio_disabled", "preview_disabled", "touch", "RTN"}) do
  scenario(exit .. " still closes a disconnected tuning visit", function()
    local widget, d, writes = fixture(exit ~= "touch" and exit ~= "RTN")
    energize(d, writes)
    widget.state.fblConnected = false
    job(widget); widget:refresh(0, nil)
    check(widget.inflightFullscreen == true and not d.live, "positive control: link loss pauses the visit")
    local before = #writes
    if exit == "firmware" then widget:refresh(nil, nil)
    elseif exit == "background" then widget:background()
    elseif exit == "touch" or exit == "RTN" then
      check(Input.dispatch(widget, exit == "touch" and "close" or "back", nil, exit == "touch" and "touch" or "key"), "ground close accepted while disconnected")
    else
      if exit == "radio_disabled" then widget.preferences.inflight.enabled = false
      else widget.preferences.general.preview_inflight_tuning = false end
      job(widget); widget:refresh(0, nil)
    end
    check(not widget.inflightFullscreen and not d.live, "an explicit exit still ends the visit during link loss")
    widget.preferences.inflight.enabled = true
    widget.preferences.general.preview_inflight_tuning = true
    widget.state.fblConnected = true
    for _ = 1, 3 do job(widget); widget:refresh(0, nil) end
    check(not d.live and #writes == before, "link recovery cannot reopen an explicitly closed visit")
  end)
end
for _, exit in ipairs({"touch", "RTN"}) do
  scenario(exit .. " ground close retains the post-flight comparison", function()
    local widget, d, writes = fixture(false)
    energize(d, writes)
    d:setPhase("post")
    d:writeValue(50, 2)
    local before, baseline, fired = #writes, d.baseline, d.fired
    check(Input.dispatch(widget, exit == "touch" and "close" or "back", nil, exit == "touch" and "touch" or "key"), "ground close accepted")
    cleared(d, writes, before)
    check(d.post and d.phase == "post" and d.baseline == baseline and d.fired == fired, "post comparison survives close")
    job(widget); widget:refresh(0, nil)
    for i = before + 1, #writes do check(writes[i][3] == 0, "quick menu keeps both outputs at zero") end
  end)
end
scenario("air pause resumes the same group and entry", function()
  local widget, d, writes = fixture(true)
  d.group, d.entry = 2, 3
  local cell = d.groups[2].entries[3]
  d.bank, d.row = cell.bank, cell.row
  energize(d, writes)
  local baseline, fired = d.baseline, d.fired
  d.radio.channelUs = function() return 998 end
  Drive.cleanup(widget)
  widget.inflightFullscreen, d.open = true, true
  d:tick(true)
  check(d.live and d.phase == "live" and d.group == 2 and d.entry == 3
    and d.bank == cell.bank and d.row == cell.row, "reopen continues the same parameter despite a stale channel echo")
  check(d.baseline == baseline and d.fired == fired, "reopen retains the flight")
  d:tick(false)
  check(d.phase == "post", "landing after pause retains comparison")
  d:tick(true)
  check(d.group == 1 and d.entry == 1 and d.fired == 0, "next flight starts at group one, entry one")
end)
scenario("closed zone never builds a tuning surface", function()
  local widget, d = fixture(false)
  widget.inflightFullscreen = nil
  job(widget); widget:refresh(nil, nil)
  check(not d.live, "zone revokes release even if a stale live snapshot exists")
  local Screen = rfsuite.require("widgets/dashboard/inflight/screen.lua")
  check(Screen.buildZone == nil, "zone tuning builder is removed")
end)
scenario("stored switch is ignored and cannot cause a setup fault", function()
  local a = Drive.settings({inflight = {enabled = true, switch = 999}}, {})
  local b = Drive.settings({inflight = {enabled = true}}, {})
  check(a.switch == nil and b.switch == nil and Drive.DEFAULTS.switch == nil, "switch is absent from runtime settings and defaults")
  local target = {switch = 999}
  Drive.storeRadioSettings(target, Drive.loadRadioSettings({inflight = {enabled = true}}))
  check(target.switch == 999, "saving leaves the ignored stored switch untouched")
end)
scenario("automatic link resume retains the board identity refusal", function()
  local widget, d, writes = fixture(true)
  energize(d, writes)
  d.board = "board-a"
  local Prime = rfsuite.require("widgets/dashboard/inflight/prime.lua")
  local saved, board = Prime.boardOnLink, nil
  Prime.boardOnLink = function() return board end
  widget.state.fblConnected = false
  job(widget); widget:refresh(0, nil)
  local before = #writes
  widget.state.fblConnected = true
  job(widget); widget:refresh(0, nil)
  check(widget.inflightFullscreen and d.live, "link return releases the visit while identity is pending")
  check(d:profileRefusal() == "board_unknown" and not d:dispatch("step", 1, "touch"), "pending board identity still refuses steps")
  board = "board-b"
  check(d:profileRefusal() == "session_unread" and not d:dispatch("step", 1, "touch"), "another board cannot use the previous session")
  for i = before + 1, #writes do
    if writes[i][1] == d.settings.value_gvar - 1 then check(writes[i][3] == 0, "unknown or foreign identity permits no value pulse") end
  end
  Prime.boardOnLink = saved
end)
scenario("the quick-menu entry is offered before the tuning surface was ever opened", function()
  local Views = rfsuite.require("widgets/dashboard/views.lua")
  local widget = Runtime.new({x = 0, y = 0, w = 480, h = 320}, {})
  widget.preferences.general = {preview_inflight_tuning = true}
  widget.preferences.inflight = {enabled = true}
  widget.state.inflight, widget._inflight, widget.inflightFullscreen = nil, nil, nil
  check(Views.condition("previewInflightTuning", widget) == true,
    "the entry is the only way in, so it must not wait for a snapshot only an open surface publishes")
  widget.preferences.inflight.enabled = false
  check(Views.condition("previewInflightTuning", widget) ~= true, "radio master switch off hides the entry")
  widget.preferences.inflight.enabled = true
  widget.preferences.general.preview_inflight_tuning = false
  check(Views.condition("previewInflightTuning", widget) ~= true, "preview off hides the entry")
end)
Stubs.releaseCard()
print(passed .. " surface regressions passed; " .. #failed .. " failed; " .. checks .. " assertions")
assert(#failed == 0, table.concat(failed, "\n"))
