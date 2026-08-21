-- Keep main.lua lightweight; it is loaded for all widgets at boot.
local name = "RFSuite Service"

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
  local factory = assert(loadScript("/WIDGETS/rfsuiteservice/app.lua", "t"))
  return factory(zone, options)
end

-- Every entry point is wrapped: this widget exists to keep the background service running, so an
-- error in one pass must not be the last pass. The next call rebuilds what it needs.
local function update(widget, options)
  if widget and widget.update then
    pcall(widget.update, widget, options)
  end
end

local function refresh(widget, event, touchState)
  if widget and widget.refresh then
    local ok = pcall(widget.refresh, widget, event, touchState)
    if not ok then
      widget.built = false
    end
  end
end

local function background(widget)
  if widget and widget.background then
    pcall(widget.background, widget)
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
