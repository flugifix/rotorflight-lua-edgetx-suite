local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = loadModule("common.lua")

local M = {}

function M.build(ctx)
  Common.buildSimplePage(ctx, "settings_dashboard", "section_dashboard", "Dashboard", {
    { labelKey = "theme", labelFallback = "Theme", valueKey = "value_theme", valueFallback = "DEFAULT" },
    { labelKey = "layout", labelFallback = "Layout", valueKey = "value_layout", valueFallback = "GRID" },
    { labelKey = "show_labels", labelFallback = "Show Labels", valueKey = "value_show_labels", valueFallback = "ON" },
    { labelKey = "widget_spacing", labelFallback = "Widget Spacing", valueKey = "value_widget_spacing", valueFallback = "MEDIUM" },
    { labelKey = "refresh_rate", labelFallback = "Refresh Rate", valueKey = "value_refresh_rate", valueFallback = "10Hz", withArrow = false }
  })
end

return M
