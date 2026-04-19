local M = {}

local Log = nil
local function ensureLog()
  if Log then return end
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/log.lua", "t")
  if type(chunk) ~= "function" then return end
  local ok, mod = pcall(chunk)
  if ok and type(mod) == "table" and type(mod.emit) == "function" then
    Log = mod
  end
end

local unpack_fn = table.unpack or unpack
local function safeCall(fn, ...)
  if type(fn) ~= "function" then return false, "not a function" end
  if type(debug) == "table" and type(debug.traceback) == "function" and type(xpcall) == "function" then
    local args = { ... }
    local function wrapped()
      return fn(unpack_fn(args))
    end
    local ok, res = xpcall(wrapped, debug.traceback)
    return ok, res
  end
  return pcall(fn, ...)
end

-- Show a confirm dialog that behaves like legacy `lvgl.confirm` when possible.
-- ctx: { title=string, message=string, onConfirm=function, onCancel=function, onFallback=function }
-- Returns true if a UI was shown or fallback executed, false otherwise.
function M.show(ctx)
  local title = (ctx and ctx.title) or "Confirm"
  local message = (ctx and ctx.message) or ""
  local onConfirm = ctx and ctx.onConfirm
  local onCancel = ctx and ctx.onCancel
  local onFallback = ctx and ctx.onFallback

  -- Diagnostics
  ensureLog()
  if Log and type(Log.emit) == "function" then
    pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl types: message=" .. tostring(type(lvgl and lvgl.message)), "debug", true)
  end

  local function handle(action)
    if type(action) == "number" then
      if action == 1 then if type(onConfirm) == "function" then pcall(onConfirm) end else if type(onCancel) == "function" then pcall(onCancel) end end
    elseif type(action) == "string" then
      local s = string.lower(action)
      if string.find(s, "y") or string.find(s, "ok") or string.find(s, "ja") or string.find(s, "yes") then
        if type(onConfirm) == "function" then pcall(onConfirm) end
      else
        if type(onCancel) == "function" then pcall(onCancel) end
      end
    else
      if type(onCancel) == "function" then pcall(onCancel) end
    end
  end

  -- Only use lvgl.message per request; try common message signatures.
  if lvgl and type(lvgl.message) == "function" then
    do
      local ok, res = safeCall(function() lvgl.message({ title = title, text = message, buttons = {"Yes", "No"}, onAction = handle }) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.message attempt 1 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
      ok, res = safeCall(function() lvgl.message({ title = title, message = message, buttons = {"Yes", "No"}, onAction = handle }) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.message attempt 2 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
      ok, res = safeCall(function() lvgl.message({ title = title, text = message, onClose = handle }) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.message attempt 3 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
      ok, res = safeCall(function() lvgl.message(title, message, {"Yes", "No"}, handle) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.message attempt 4 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
    end
  end

  if type(onFallback) == "function" then
    pcall(onFallback, title, message)
    return true
  end

  return false
end

return M
      elseif type(action) == "string" then
        local s = string.lower(action)
        if string.find(s, "y") or string.find(s, "ok") or string.find(s, "ja") or string.find(s, "yes") then
          if type(onConfirm) == "function" then pcall(onConfirm) end
        else
          if type(onCancel) == "function" then pcall(onCancel) end
        end
      else
        if type(onCancel) == "function" then pcall(onCancel) end
      end
    end

    do
      local ok, res = safeCall(function() lvgl.dialog({ title = title, message = message, buttons = {"Yes", "No"}, onAction = handle }) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.dialog attempt 1 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
      ok, res = safeCall(function() lvgl.dialog({ title = title, text = message, buttons = {"Yes", "No"}, onAction = handle }) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.dialog attempt 2 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
      ok, res = safeCall(function() lvgl.dialog({ title = title, message = message, onClose = handle }) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.dialog attempt 3 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
      ok, res = safeCall(function() lvgl.dialog(title, message, {"Yes", "No"}, handle) end)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.dialog attempt 4 ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
      if ok then return true end
    end
  end

  -- Fallback: simple alert then treat as confirmed (legacy behavior used to proceed)
  if lvgl and type(lvgl.alert) == "function" then
    local ok, res = safeCall(lvgl.alert, { title = title, message = message })
    if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.ui.confirm_dialog", "lvgl.alert ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true) end
    if ok then
      if type(onConfirm) == "function" then pcall(onConfirm) end
      return true
    end
  end

  if type(onFallback) == "function" then
    pcall(onFallback, title, message)
    return true
  end

  return false
end

return M
