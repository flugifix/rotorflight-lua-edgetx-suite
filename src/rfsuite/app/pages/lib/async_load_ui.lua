local M = {}

local function clamp01(v)
  local n = tonumber(v) or 0
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

function M.begin(state, nowSec, totalSteps, showOverlay)
  state.loading = true
  state.showLoadingOverlay = showOverlay == true
  state.loadingStartedAt = tonumber(nowSec) or 0
  state.done = 0
  state.total = math.max(0, tonumber(totalSteps) or 0)
  state.progress = 0
  state.errorMessage = nil
  state.errorDialogShown = nil
end

function M.stepDone(state)
  state.done = (tonumber(state.done) or 0) + 1
  local total = tonumber(state.total) or 0
  if total > 0 then
    state.progress = clamp01(state.done / total)
  else
    state.progress = 1
  end

  if total > 0 and state.done >= total then
    state.loading = false
    state.showLoadingOverlay = false
    return true
  end

  return false
end

function M.fail(state, i18n, tfn, reason)
  local total = tonumber(state.total) or 0
  state.done = total
  state.progress = 1
  state.loading = false
  state.showLoadingOverlay = false

  local prefix = tfn(i18n, "loading_failed", "Loading failed")
  if reason and reason ~= "" then
    state.errorMessage = prefix .. ": " .. tostring(reason)
  else
    state.errorMessage = prefix
  end

  state.errorDialogShown = nil
end

function M.isTimedOut(state, nowSec)
  if state.loading ~= true then return false end
  local started = tonumber(state.loadingStartedAt) or 0
  local timeoutSec = tonumber(state.loadingTimeoutSec) or 12
  return (tonumber(nowSec) or 0) - started >= timeoutSec
end

function M.showErrorDialog(state, i18n, tfn)
  local message = state.errorMessage
  if type(message) ~= "string" or message == "" then
    return
  end
  if state.errorDialogShown == message then
    return
  end

  local title = tfn(i18n, "loading_failed", "Loading failed")
  local shown = false

  if lvgl and type(lvgl.message) == "function" then
    local ok = pcall(lvgl.message, {
      title = title,
      text = message,
      message = message
    })
    if ok then shown = true end
  end

  if not shown and lvgl and type(lvgl.alert) == "function" then
    pcall(lvgl.alert, {
      title = title,
      message = message
    })
    shown = true
  end

  if shown then
    state.errorDialogShown = message
  end
end

function M.reset(state)
  state.loading = false
  state.showLoadingOverlay = false
  state.loadingStartedAt = 0
  state.progress = 0
  state.done = 0
  state.total = 0
  state.errorMessage = nil
  state.errorDialogShown = nil
end

return M
