-- EdgeTX MSP API: BOARD_AUTO_ALIGN (MSP2_BOARD_AUTO_ALIGN 0x5F13)

local Api = {
  command = 0x5F13,
  actions = { poll = 0, start = 1 },
  states = { idle = 0, waitingForTailLift = 1, success = 2, rejectedArmed = 3,
    timeout = 4, noMatch = 5, rejectedUncalibrated = 6 }
}

local function u8(buf, i) return tonumber(buf[i]) or 0 end
local function s16(buf, i)
  local value = u8(buf, i) | (u8(buf, i + 1) << 8)
  if value >= 0x8000 then value = value - 0x10000 end
  return value
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 8 then return nil end
  return { state = u8(buf, 1), roll_degrees = s16(buf, 2), pitch_degrees = s16(buf, 4),
    yaw_degrees = s16(buf, 6), matched_samples = u8(buf, 8) }
end

function Api.buildPayload(action)
  return { action == Api.actions.start and Api.actions.start or Api.actions.poll }
end

function Api.classify(state)
  if state == Api.states.waitingForTailLift then return "waiting", true end
  if state == Api.states.success then return "success", false end
  if state == Api.states.rejectedArmed then return "rejected_armed", false end
  if state == Api.states.timeout then return "timeout", false end
  if state == Api.states.noMatch then return "no_match", false end
  if state == Api.states.rejectedUncalibrated then return "rejected_uncalibrated", false end
  if state == Api.states.idle then return "idle", false end
  return "unknown", false
end

return Api
