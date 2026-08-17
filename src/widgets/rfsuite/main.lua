-- Keep main.lua lightweight; it is loaded for all widgets at boot.
local name = "RFSuite"

if lvgl == nil then
  return {
    name = name,
    options = {},
    create = function() end,
    refresh = function()
      lcd.drawText(10, 10, "LVGL support required", COLOR_THEME_WARNING)
    end,
  }
end

local function create(zone, options)
  local requireChunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/require.lua", "t")
  if requireChunk then
    requireChunk()
  end
  local factory = assert(loadScript("/WIDGETS/rfsuite/app.lua", "t"))
  return factory(zone, options)
end

local function nowSeconds()
  if getTime then
    local ok, value = pcall(getTime)
    if ok and type(value) == "number" then
      return value / 100
    end
  end
  return 0
end

local function isCpuLimitError(err)
  return type(err) == "string" and string.find(err, "CPU limit", 1, true) ~= nil
end

local function update(widget, options)
  if widget and widget.update then
    local ok, err = pcall(widget.update, widget, options)
    if not ok and isCpuLimitError(err) then
      widget._cpuBackoffUntil = nowSeconds() + 0.8
    end
  end
end

local function logGv(msg)
  local fLog = io.open("/SCRIPTS/TOOLS/rfsuite.user/gv_debug.log", "a")
  if fLog then
    local t = (getTime and getTime()) or 0
    io.write(fLog, string.format("[%.2f][Widget.main] %s\n", t / 100, tostring(msg)))
    io.close(fLog)
  end
  if print then pcall(print, "[Widget.main] " .. tostring(msg)) end
end

local function shouldReloadWidget(widget)
  local reload = false
  local reason = ""
  if _G.rfsuite_reload_flag and _G.rfsuite_reload_flag ~= widget._lastSeenReloadFlag then
    reason = "reload_flag(" .. tostring(widget._lastSeenReloadFlag) .. "->" .. tostring(_G.rfsuite_reload_flag) .. ")"
    widget._lastSeenReloadFlag = _G.rfsuite_reload_flag
    reload = true
  end
  if type(model) == "table" and type(model.getGlobalVariable) == "function" then
    for _, fm in ipairs({0, 8}) do
      local ok, val = pcall(model.getGlobalVariable, 8, fm)
      if ok and val == 1 then
        pcall(model.setGlobalVariable, 8, fm, 0)
        reason = reason .. " GV9_FM" .. tostring(fm) .. "=1"
        reload = true
      end
    end
  end
  if reload then
    logGv("Reload triggered: " .. reason)
  end
  return reload
end

local function refresh(widget, event, touchState)
  if _G.rfsuite_tool_active then
    return
  end

  if widget and shouldReloadWidget(widget) then
    widget._cpuBackoffUntil = 0
    logGv("Calling widget.reload()")
    if type(widget.reload) == "function" then
      pcall(widget.reload, widget, true)
    else
      widget.built = false
      widget.theme = nil
      widget.themePath = nil
      widget.renderKey = nil
      widget._cachedRenderKey = nil
    end
  end

  if widget and widget.refresh then
    local now = nowSeconds()
    local backoffUntil = tonumber(widget._cpuBackoffUntil) or 0
    if backoffUntil > 0 and now < backoffUntil then
      return
    end

    local ok, err = pcall(widget.refresh, widget, event, touchState)
    if not ok then
      if isCpuLimitError(err) then
        widget._cpuBackoffUntil = now + 1.2
      end
      widget.built = false
    end
  end
end

local function background(widget)
  if widget and widget.background then
    local ok, err = pcall(widget.background, widget)
    if not ok and isCpuLimitError(err) then
      widget._cpuBackoffUntil = nowSeconds() + 0.8
    end
  end
end

return {
  useLvgl = true,
  name = name,
  options = {},
  create = create,
  update = update,
  refresh = refresh,
  background = background,
}
