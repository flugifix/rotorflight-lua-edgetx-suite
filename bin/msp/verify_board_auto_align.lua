local Api = assert(loadfile("src/rfsuite/tasks/msp/api/board_auto_align.lua"))()
local Lifecycle = assert(loadfile("src/rfsuite/app/pages/setup/alignment/auto_align_lifecycle.lua"))()
local View = assert(loadfile("src/rfsuite/app/pages/setup/alignment/auto_align_view.lua"))()
local checks = 0
local function equal(actual, expected, label)
  checks = checks + 1
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
end
local reply = Api.parse({ 2, 0xF4, 0xFF, 0x0F, 0x00, 0x00, 0x80, 12 })
equal(reply.state, Api.states.success, "state")
equal(reply.roll_degrees, -12, "negative roll")
equal(reply.pitch_degrees, 15, "positive pitch")
equal(reply.yaw_degrees, -32768, "minimum yaw")
equal(reply.matched_samples, 12, "matched samples")
equal(Api.parse({ 2, 0, 0, 0, 0, 0, 0 }), nil, "short reply")
equal(Api.buildPayload(Api.actions.poll)[1], 0, "poll action")
equal(Api.buildPayload(Api.actions.start)[1], 1, "start action")
for name, value in pairs(Api.states) do
  equal(Api.parse({ value, 0, 0, 0, 0, 0, 0, 0 }).state, value, "state " .. name)
end
local runtime = { generation = 4 }
local session = {}
local token = Lifecycle.capture(runtime, session, "12.0.10:board-a", 3)
equal(Lifecycle.isCurrent(runtime, true, session, "12.0.10:board-a", true, 3, token), true, "current callback")
equal(Lifecycle.isCurrent(runtime, false, session, "12.0.10:board-a", true, 3, token), false, "closed page callback")
equal(Lifecycle.isCurrent(runtime, true, session, "12.0.10:board-b", true, 3, token), false, "changed signature callback")
equal(Lifecycle.isCurrent(runtime, true, {}, "12.0.10:board-a", true, 3, token), false, "changed session callback")
equal(Lifecycle.isCurrent(runtime, true, session, "12.0.10:board-a", false, 3, token), false, "disconnected callback")
equal(Lifecycle.isCurrent(runtime, true, session, "12.0.10:board-a", true, 4, token), false, "armed transition callback")
equal(Lifecycle.isCurrent({ generation = 4 }, true, session, "12.0.10:board-a", true, 3, token), false, "replaced runtime callback")
Lifecycle.invalidate(runtime)
equal(Lifecycle.isCurrent(runtime, true, session, "12.0.10:board-a", true, 3, token), false, "invalidated callback")
local children = { { type = "existing" } }
equal(View.append(children, false, { type = "button", text = "Auto-align" }), 0, "unsupported node count")
equal(#children, 1, "unsupported child count")
equal(View.append(children, true, { type = "button", text = "Auto-align", active = true }), 1, "supported node count")
equal(#children, 2, "supported child count")
equal(children[2].type, "button", "supported node type")
equal(children[2].text, "Auto-align", "supported node label")
equal(children[2].active, true, "supported node active state")
local expected = {
  idle = { "idle", false }, waitingForTailLift = { "waiting", true }, success = { "success", false },
  rejectedArmed = { "rejected_armed", false }, timeout = { "timeout", false }, noMatch = { "no_match", false },
  rejectedUncalibrated = { "rejected_uncalibrated", false }
}
for name, value in pairs(Api.states) do
  local outcome, active = Api.classify(value)
  equal(outcome, expected[name][1], "outcome " .. name)
  equal(active, expected[name][2], "active " .. name)
end
print(string.format("board auto-align API: %d checks passed", checks))
