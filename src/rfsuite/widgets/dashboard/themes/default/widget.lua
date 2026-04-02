local Theme = {}

local LOGO_FILE = "/SCRIPTS/TOOLS/rfsuite-core/assets/icon.png"

local function metricTextLeft(state)
  return string.format("%d%%", math.floor(state.fuel + 0.5))
end

local function metricTextRight(state)
  return string.format("%.1fV", state.voltage)
end

local function getVoltageColor(state)
  local cfg = state and state.themeConfig or nil
  local vMin = tonumber(cfg and cfg.v_min) or 18.0
  local vMax = tonumber(cfg and cfg.v_max) or 25.2
  local v = tonumber(state and state.voltage) or 0
  if v <= 0 then return BLACK end
  if v < vMin or v > vMax then
    return COLOR_THEME_WARNING
  end
  return BLACK
end

function Theme.build(zone, state)
  local cardGap = 6
  local topPad = 4
  local headerH = 28
  local bottomH = 40
  local metricY = zone.y + headerH + topPad
  local metricH = math.max(58, zone.h - headerH - bottomH - topPad - 6)
  local metricW = math.floor((zone.w - cardGap) / 2)

  local bottomY = zone.y + zone.h - bottomH
  local statW = math.floor(zone.w / 4)

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
      w = math.max(50, zone.w - 120),
      text = "ROTORFLIGHT",
      color = WHITE,
      font = MIDSIZE
    },
    {
      type = "label",
      x = zone.x + zone.w - 110,
      y = zone.y + 6,
      w = 100,
      text = function() return state.armed and "ARMED" or "DISARMED" end,
      color = function()
        if state.armed then return COLOR_THEME_WARNING end
        return COLOR_THEME_SECONDARY1
      end,
      align = RIGHT,
      font = SMLSIZE
    },

    {
      type = "rectangle",
      x = zone.x,
      y = metricY,
      w = metricW,
      h = metricH,
      color = WHITE,
      filled = true
    },
    {
      type = "rectangle",
      x = zone.x + metricW + cardGap,
      y = metricY,
      w = metricW,
      h = metricH,
      color = WHITE,
      filled = true
    },
    {
      type = "label",
      x = zone.x,
      y = metricY + math.floor(metricH * 0.32),
      w = metricW,
      text = function() return metricTextLeft(state) end,
      color = BLACK,
      align = CENTER,
      font = DBLSIZE
    },
    {
      type = "label",
      x = zone.x,
      y = metricY + metricH - 24,
      w = metricW,
      text = "FUEL",
      color = GREY_DEFAULT,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = zone.x + metricW + cardGap,
      y = metricY + math.floor(metricH * 0.32),
      w = metricW,
      text = function() return metricTextRight(state) end,
      color = function() return getVoltageColor(state) end,
      align = CENTER,
      font = DBLSIZE
    },
    {
      type = "label",
      x = zone.x + metricW + cardGap,
      y = metricY + metricH - 24,
      w = metricW,
      text = "VOLTAGE",
      color = GREY_DEFAULT,
      align = CENTER,
      font = SMLSIZE
    },

    {
      type = "rectangle",
      x = zone.x,
      y = bottomY,
      w = zone.w,
      h = bottomH,
      color = COLOR_THEME_PRIMARY1,
      filled = true
    },
    {
      type = "label",
      x = zone.x + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("RPM %d", math.floor(state.rpm or 0)) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = zone.x + statW + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("PROF %d", state.profile or 1) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = zone.x + statW * 2 + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("FLIGHTS %d", state.flights or 0) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = zone.x + statW * 3 + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("LQ %d", math.floor(state.lq or 0)) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    }
  }
end

return Theme
