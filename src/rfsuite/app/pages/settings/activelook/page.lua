local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = loadModule("common.lua")

local M = {}

function M.build(ctx)
  Common.buildSimplePage(ctx, "settings_activelook", "section_activelook", "ActiveLook", {
    { labelKey = "style", labelFallback = "Style", valueKey = "value_style", valueFallback = "MODERN" },
    { labelKey = "icon_pack", labelFallback = "Icon Pack", valueKey = "value_icon_pack", valueFallback = "RF SUITE" },
    { labelKey = "contrast", labelFallback = "Contrast", valueKey = "value_contrast", valueFallback = "HIGH" },
    { labelKey = "highlight", labelFallback = "Highlight", valueKey = "value_highlight", valueFallback = "AMBER" },
    { labelKey = "animations", labelFallback = "Animations", valueKey = "value_animations", valueFallback = "ON", withArrow = false }
  })
end

return M
