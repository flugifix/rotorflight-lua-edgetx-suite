local M = {}

function M.show(ctx)
  local title = ctx.title or "Unsupported MSP API"
  local message = ctx.message or ""

  if lvgl and type(lvgl.alert) == "function" then
    local ok = pcall(lvgl.alert, {
      title = title,
      message = message
    })
    if ok then
      return true
    end
  end

  if type(ctx.onFallback) == "function" then
    ctx.onFallback(title, message)
    return true
  end

  return false
end

return M
