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
  local factory = assert(loadScript("/WIDGETS/rfsuite/app.lua", "t"))
  return factory(zone, options)
end

local function update(widget, options)
  if widget and widget.update then
    widget.update(widget, options)
  end
end

local function refresh(widget, event, touchState)
  if widget and widget.refresh then
    widget.refresh(widget, event, touchState)
  end
end

local function background(widget)
  if widget and widget.background then
    widget.background(widget)
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
