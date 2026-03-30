local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = loadModule("common.lua")

local M = {}

function M.build(ctx)
  Common.buildSimplePage(ctx, "settings_localization", "section_localization", "Localization", {
    { labelKey = "language", labelFallback = "Language", valueKey = "value_language", valueFallback = "DE" },
    { labelKey = "units", labelFallback = "Units", valueKey = "value_units", valueFallback = "METRIC" },
    { labelKey = "number_format", labelFallback = "Number Format", valueKey = "value_number_format", valueFallback = "1.23" },
    { labelKey = "date_format", labelFallback = "Date Format", valueKey = "value_date_format", valueFallback = "DD.MM.YYYY" },
    { labelKey = "time_format", labelFallback = "Time Format", valueKey = "value_time_format", valueFallback = "24H", withArrow = false }
  })
end

return M
