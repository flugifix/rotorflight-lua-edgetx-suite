local Wrapper = {}

local utils = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/common.lua", "t"))()
local themeCommon = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/default/common.lua", "t"))()

local function rgb(hex, fallback)
  if lcd and type(lcd.RGB) == "function" then
    return lcd.RGB(hex)
  end
  return fallback
end

local ARC_BG_COLOR = rgb(0x444444, GREY_DEFAULT)
local ARC_OK_COLOR = rgb(0x00FF00, GREEN or COLOR_THEME_PRIMARY1)
local ARC_WARN_COLOR = rgb(0xFF8000, COLOR_THEME_WARNING)
local ARC_ALERT_COLOR = rgb(0xFF0000, COLOR_THEME_WARNING)

local function getArcValueColor(value, state, box)
  if type(value) ~= "number" or value <= 0 then
    return ARC_BG_COLOR
  end

  local cells = 1
  if themeCommon and type(themeCommon.estimateCellCount) == "function" then
    cells = math.max(1, themeCommon.estimateCellCount(state))
  else
    local maxValue = utils.toNumber(utils.resolveValue(box.max, box, state), 25.2)
    if type(maxValue) == "number" and maxValue > 0 then
      cells = math.max(1, math.floor((maxValue / 4.2) + 0.5))
    end
  end

  local cellValue = value / cells
  local alertCell = tonumber(box and box.alertcell) or 3.50
  local warnCell = tonumber(box and box.warncell) or 3.70

  if alertCell > warnCell then
    local tmp = alertCell
    alertCell = warnCell
    warnCell = tmp
  end

  if cellValue <= alertCell then return ARC_ALERT_COLOR end
  if cellValue <= warnCell then return ARC_WARN_COLOR end
  return ARC_OK_COLOR
end

local function renderArc(nodes, rect, box, state)
  local gaugeMin = utils.toNumber(utils.resolveValue(box.min, box, state), utils.toNumber(state and state.themeConfig and state.themeConfig.v_min, 18.0))
  local gaugeMax = utils.toNumber(utils.resolveValue(box.max, box, state), utils.toNumber(state and state.themeConfig and state.themeConfig.v_max, 25.2))
  local gaugeValue = utils.toNumber(utils.mapTelemetrySource(utils.resolveValue(box.source, box, state), state), 0)

  local ratio = 0
  if gaugeMax > gaugeMin then
    ratio = utils.clamp((gaugeValue - gaugeMin) / (gaugeMax - gaugeMin), 0, 1)
  end

  local titleReserved = (box and box.titlepos == "bottom") and 22 or 0
  local panelY = rect.y + 4
  local panelH = math.max(40, rect.h - 8 - titleReserved)
  local cx = rect.x + math.floor(rect.w / 2)
  local cy = panelY + math.floor(panelH * 0.52)
  local radius = math.max(18, math.floor(math.min(rect.w - 14, panelH - 10) / 2))
  local thickness = math.max(5, math.floor(radius * 0.18))
  local startAngle = utils.toNumber(utils.resolveValue(box.arcstart, box, state), 135)
  local endAngle = utils.toNumber(utils.resolveValue(box.arcend, box, state), 405)
  if endAngle <= startAngle then
    endAngle = startAngle + 250
  end
  local sweep = endAngle - startAngle
  local valueEndAngle = startAngle + math.floor(sweep * ratio + 0.5)

  local arcBgColor = box.fillbgcolor or ARC_BG_COLOR
  local arcValueColor = box.fillcolor or getArcValueColor(gaugeValue, state, box)

  nodes[#nodes + 1] = {
    type = "arc",
    x = cx,
    y = cy,
    radius = radius,
    thickness = thickness,
    startAngle = startAngle,
    endAngle = endAngle,
    rounded = true,
    color = arcBgColor
  }

  if ratio > 0 then
    nodes[#nodes + 1] = {
      type = "arc",
      x = cx,
      y = cy,
      radius = radius,
      thickness = thickness,
      startAngle = startAngle,
      endAngle = valueEndAngle,
      rounded = true,
      color = arcValueColor
    }
  end

  local valueY = cy - math.floor(thickness * 0.5)
  if valueY < rect.y + 10 then
    valueY = rect.y + 10
  end

  utils.pushLabel(
    nodes,
    rect.x + 4,
    valueY,
    rect.w - 8,
    themeCommon.formatVoltage(gaugeValue),
    box.textcolor or BLACK,
    box.valuealign or box.titlealign or CENTER,
    DBLSIZE
  )
end

function Wrapper.render(nodes, rect, box, state)
  utils.drawContainer(nodes, rect, box, state)
  renderArc(nodes, rect, box or {}, state)
end

return Wrapper
