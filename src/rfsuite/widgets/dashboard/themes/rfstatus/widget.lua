local Theme = {}

local LOGO_FILE = "/SCRIPTS/TOOLS/rfsuite-core/assets/icon.png"

local function metricFuel(state)
  return string.format("%d%%", math.floor((state.fuel or 0) + 0.5))
end

local function metricVoltage(state)
  return string.format("%.1fV", state.voltage or 0)
end

local function getVoltageColor(state)
  local cfg = state and state.themeConfig or nil
  local vMin = tonumber(cfg and cfg.v_min) or 18.0
  local vMax = tonumber(cfg and cfg.v_max) or 25.2
  local v = tonumber(state and state.voltage) or 0
  if v <= 0 then return BLACK end
  if v < vMin or v > vMax then return COLOR_THEME_WARNING end
  return COLOR_THEME_PRIMARY1
end

function Theme.build(zone, state)
  local panelY = zone.y + 30
  local panelH = zone.h - 70
  local rowY = panelY + math.floor(panelH * 0.22)

  return {
    {
      type = "rectangle",
      x = zone.x,
      y = zone.y,
      w = zone.w,
      h = zone.h,
      color = COLOR_THEME_PRIMARY2,
      filled = true
    },
    {
      type = "image",
      x = zone.x + 4,
      y = zone.y + 2,
      w = 26,
      h = 26,
      file = LOGO_FILE
    },
    {
      type = "label",
      x = zone.x + 36,
      y = zone.y + 6,
      w = zone.w - 40,
      text = "RF STATUS",
      color = WHITE,
      font = MIDSIZE
    },
    {
      type = "rectangle",
      x = zone.x + 6,
      y = panelY,
      w = zone.w - 12,
      h = panelH,
      color = WHITE,
      filled = true
    },
    {
      type = "label",
      x = zone.x + 14,
      y = rowY,
      w = zone.w - 28,
      text = function() return state.armed and "ARMED" or "DISARMED" end,
      color = function() return state.armed and COLOR_THEME_WARNING or BLACK end,
      align = CENTER,
      font = DBLSIZE
    },
    {
      type = "label",
      x = zone.x + 14,
      y = rowY + 34,
      w = zone.w - 28,
      text = function() return "RPM " .. tostring(math.floor(state.rpm or 0)) end,
      color = BLACK,
      align = CENTER,
      font = MIDSIZE
    },
    {
      type = "label",
      x = zone.x + 14,
      y = rowY + 62,
      w = zone.w - 28,
      text = function() return "LQ " .. tostring(math.floor(state.lq or 0)) end,
      color = BLACK,
      align = CENTER,
      font = MIDSIZE
    },
    {
      type = "label",
      x = zone.x + 14,
      y = rowY + 92,
      w = zone.w - 28,
      text = function() return "FUEL " .. metricFuel(state) end,
      color = BLACK,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = zone.x + 14,
      y = rowY + 114,
      w = zone.w - 28,
      text = function() return "VOLT " .. metricVoltage(state) end,
      color = function() return getVoltageColor(state) end,
      align = CENTER,
      font = SMLSIZE
    }
  }
end

return Theme
