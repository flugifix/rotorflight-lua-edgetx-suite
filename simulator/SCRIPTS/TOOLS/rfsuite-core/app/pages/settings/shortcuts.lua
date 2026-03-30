local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = loadModule("common.lua")

local M = {}

function M.build(ctx)
  Common.buildSimplePage(ctx, "settings_shortcuts", "section_shortcuts", "Shortcuts", {
    { labelKey = "primary_actions", labelFallback = "Primary Actions", valueKey = "value_primary_actions", valueFallback = "MODE 1" },
    { labelKey = "secondary_actions", labelFallback = "Secondary Actions", valueKey = "value_secondary_actions", valueFallback = "MODE 2" },
    { labelKey = "switch_mapping", labelFallback = "Switch Mapping", valueKey = "value_switch_mapping", valueFallback = "STANDARD" },
    { labelKey = "quick_access", labelFallback = "Quick Access", valueKey = "value_quick_access", valueFallback = "ENABLED" },
    { labelKey = "long_press_delay", labelFallback = "Long Press Delay", valueKey = "value_long_press_delay", valueFallback = "500ms", withArrow = false }
  })
end

return M
