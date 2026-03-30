local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Common = loadModule("common.lua")

local M = {}

function M.build(ctx)
  Common.buildSimplePage(ctx, "settings_audio", "section_audio", "Audio", {
    { labelKey = "events", labelFallback = "Events", valueKey = "value_events", valueFallback = "ON" },
    { labelKey = "switches", labelFallback = "Switches", valueKey = "value_switches", valueFallback = "ON" },
    { labelKey = "timer", labelFallback = "Timer", valueKey = "value_timer", valueFallback = "VOICE" },
    { labelKey = "volume", labelFallback = "Volume", valueKey = "value_volume", valueFallback = "80%" },
    { labelKey = "mute_while_armed", labelFallback = "Mute While Armed", valueKey = "value_mute_while_armed", valueFallback = "OFF", withArrow = false }
  })
end

return M
