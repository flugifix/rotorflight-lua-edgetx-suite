local Wrapper = {}

local function loadModule(path, globalKey)
  if globalKey and _G[globalKey] then return _G[globalKey] end
  local chunk = loadScript(path, "t")
  if not chunk then return nil end
  local ok, mod = pcall(chunk)
  if ok and type(mod) == "table" then
    if globalKey then _G[globalKey] = mod end
    return mod
  end
  return nil
end



local function getUtils()
  return loadModule("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/common.lua", "__rfsuiteObjectsCommonModule")
end

local function getThemeCommon()
  return loadModule("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/default/common.lua", "__rfsuiteThemeDefaultCommonModule")
end

local function rgb(hex, fallback)
  if lcd and type(lcd.RGB) == "function" then
    return lcd.RGB(hex)
  end
  return fallback
end

local ARC_BG_COLOR = rgb(0x444444, GREY_DEFAULT)
local ARC_OK_COLOR = rgb(0x00FF00, GREEN or 0x00FF00)
local ARC_WARN_COLOR = rgb(0xFF8000, 0xFF8000)
local ARC_ALERT_COLOR = rgb(0xFF0000, 0xFF0000)

local function getArcValueColor(value, state, box, themeCommon, utils)
  if type(value) ~= "number" then
    return ARC_BG_COLOR
  end

  local unit = box and box.unit
  if unit == "%" then
    local alertPct = tonumber(box and box.alertpct) or 15
    local warnPct = tonumber(box and box.warnpct) or 30
    if value <= alertPct then return ARC_ALERT_COLOR end
    if value <= warnPct then return ARC_WARN_COLOR end
    return ARC_OK_COLOR
  end

  if value <= 0 then
    return ARC_BG_COLOR
  end

  local cells = 1
  if themeCommon and type(themeCommon.estimateCellCount) == "function" then
    cells = math.max(1, themeCommon.estimateCellCount(state))
  elseif utils then
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

local function renderArc(nodes, rect, box, state, themeCommon, utils)
  local source = utils.resolveValue(box.source, box, state)
  local rawValue = utils.mapTelemetrySource(source, state)
  local hasValue = type(rawValue) == "number"
  local gaugeValue = utils.toNumber(rawValue, 0)

  -- Statische Werte cachen
  box._gaugeMin = box._gaugeMin or utils.toNumber(utils.resolveValue(box.min, box, state), utils.toNumber(state and state.themeConfig and state.themeConfig.v_min, 18.0))
  box._gaugeMax = box._gaugeMax or utils.toNumber(utils.resolveValue(box.max, box, state), utils.toNumber(state and state.themeConfig and state.themeConfig.v_max, 25.2))
  local gaugeMin = box._gaugeMin
  local gaugeMax = box._gaugeMax

  -- Schutz gegen extreme Werte
  if gaugeMin == gaugeMax or gaugeMax - gaugeMin < 0.1 then return end

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
  
  if endAngle <= startAngle then endAngle = startAngle + 250 end
  local sweep = endAngle - startAngle
  local valueEndAngle = startAngle + math.floor(sweep * ratio + 0.5)

  local arcBgColor = box.fillbgcolor or ARC_BG_COLOR
  local arcValueColor = box.fillcolor or getArcValueColor(gaugeValue, state, box, themeCommon, utils)

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

  local valueYOffset = utils.toNumber(utils.resolveValue(box.value_offset_y, box, state), 0)
  local valueY = cy - math.floor(thickness * 1.3) + valueYOffset
  if valueY < rect.y + 10 then valueY = rect.y + 10 end

  local unit = utils.resolveValue(box.unit, box, state)
  local decimals = utils.resolveValue(box.decimals, box, state)
  local valueText = nil
  if source == "voltage" and themeCommon and type(themeCommon.formatVoltage) == "function" then
    valueText = themeCommon.formatVoltage(gaugeValue)
  elseif not hasValue then
    if unit ~= nil and unit ~= "" then
      valueText = "-- " .. tostring(unit)
    else
      valueText = "--"
    end
  else
    valueText = utils.appendUnit(utils.formatDisplayValue(gaugeValue, decimals), unit)
  end

  local valueColor = box.textcolor or BLACK
  if unit == "%" and hasValue then
    valueColor = getArcValueColor(gaugeValue, state, box, themeCommon, utils)
  end

  utils.pushLabel(
    nodes,
    rect.x + 4,
    valueY,
    rect.w - 8,
    valueText,
    valueColor,
    box.valuealign or box.titlealign or CENTER,
    DBLSIZE
  )
end

function Wrapper.render(nodes, rect, box, state)
  local utils = getUtils()
  local themeCommon = getThemeCommon()
  if not utils then return end

  utils.drawContainer(nodes, rect, box, state)
  renderArc(nodes, rect, box or {}, state, themeCommon, utils)
end

return Wrapper
