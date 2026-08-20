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

-- The load failed and the pilot has to be told. This used to be a native lvgl.message,
-- which is a modal outside the tool's own run loop: while one stands, run() is not
-- reached, and whether a hardware key closes it depends on whether anything focusable was
-- created after it in the same build -- so a dialog raised mid-build can only be closed by
-- touch. It is now the tool's own notice box with one acknowledging button, which is drawn
-- into the page's own child list and needs no special case anywhere.
--
-- The caller supplies the geometry it is drawing into, because only the caller knows it.
function M.appendErrorNotice(children, opts, state, i18n, tfn)
  if type(children) ~= "table" or type(opts) ~= "table" or type(state) ~= "table" then
    return false
  end

  local message = state.errorMessage
  if type(message) ~= "string" or message == "" then
    return false
  end

  local overlay = opts.overlay
  if type(overlay) ~= "table" or type(overlay.appendNotice) ~= "function" then
    return false
  end

  overlay.appendNotice(children, {
    x = opts.x,
    y = opts.y,
    w = opts.w,
    h = opts.h,
    title = tfn(i18n, "loading_failed", "Loading failed"),
    message = message,
    -- "OK" rather than a lookup: no page bundle in the tree carries a key for it, so a
    -- lookup here would only be a lookup that fails.
    buttonText = "OK",
    press = function()
      state.errorMessage = nil
      state.errorDialogShown = nil
      if type(opts.requestRebuild) == "function" then
        opts.requestRebuild()
      end
    end
  })

  return true
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
