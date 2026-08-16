local Wrapper = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require) or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local chunk = loadScript(fullPath, "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local function getUtils()
  return requireModule("widgets/dashboard/objects/common.lua")
end

local function getThemeCommon()
  return requireModule("widgets/dashboard/themes/default/common.lua")
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
local BAR_BG_COLOR = rgb(0x1a1a1a, BLACK)
local BAR_OK_COLOR = rgb(0x00FF00, GREEN or 0x00FF00)
local BAR_WARN_COLOR = rgb(0xFF8000, 0xFF8000)
local BAR_ALERT_COLOR = rgb(0xFF0000, 0xFF0000)

local function resolveThresholdColor(value, thresholds, defaultColor)
  if type(value) ~= "number" or type(thresholds) ~= "table" or #thresholds == 0 then
    return defaultColor
  end

  for i = 1, #thresholds do
    local threshold = thresholds[i]
    if type(threshold) == "table" and type(threshold.value) == "number" and value <= threshold.value then
      return threshold.fillcolor or threshold.color or defaultColor
    end
  end

  return defaultColor
end

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

local function getMaxValue(source, state, box, utils)
  if source == "throttle_percent" then
    return state.currentFlightMaxThrottlePercent or state.lastFlightMaxThrottlePercent
  elseif source == "rpm" then
    return state.currentFlightMaxRpm or state.lastFlightMaxRpm
  elseif source == "temp_esc" or source == "esc_temp" then
    return state.currentFlightMaxEscTemp or state.lastFlightMaxEscTemp
  elseif source == "temp_mcu" or source == "mcu_temp" then
    return state.currentFlightMaxMcuTemp or state.lastFlightMaxMcuTemp
  elseif source == "current" then
    return state.currentFlightMaxCurrent or state.lastFlightMaxCurrent
  elseif source == "watts" then
    return state.currentFlightMaxWatts or state.lastFlightMaxWatts
  end
  return nil
end

local function resolveGaugeBounds(box, state, utils, defaultMin, defaultMax)
  local fallbackMin = utils.toNumber(
    state and state.themeConfig and state.themeConfig.v_min,
    utils.toNumber(defaultMin, 0)
  )
  local fallbackMax = utils.toNumber(
    state and state.themeConfig and state.themeConfig.v_max,
    utils.toNumber(defaultMax, 100)
  )

  if type(box.min) == "number" and type(box.max) == "number" then
    box._gaugeMin = box._gaugeMin or box.min
    box._gaugeMax = box._gaugeMax or box.max
    return utils.toNumber(box._gaugeMin, fallbackMin), utils.toNumber(box._gaugeMax, fallbackMax)
  end

  local minValue = utils.toNumber(utils.resolveValue(box.min, box, state), fallbackMin)
  local maxValue = utils.toNumber(utils.resolveValue(box.max, box, state), fallbackMax)
  return minValue, maxValue
end

local function renderBar(nodes, rect, box, state, themeCommon, utils)
  local source = utils.resolveValue(box.source, box, state)
  local rawValue = utils.mapTelemetrySource(source, state)
  local hasValue = type(rawValue) == "number"
  local gaugeValue = utils.toNumber(rawValue, 0)

  local gaugeMin, gaugeMax = resolveGaugeBounds(box, state, utils, 0, 100)
  
  if gaugeMax <= gaugeMin then gaugeMax = 100 end
  
  local ratio = 0
  if gaugeMax > gaugeMin then
    ratio = utils.clamp((gaugeValue - gaugeMin) / (gaugeMax - gaugeMin), 0, 1)
  end
  
  local gaugeOrientation = utils.resolveValue(box.gaugeorientation, box, state) or "horizontal"
  
  -- VERTICAL GAUGE
  if gaugeOrientation == "vertical" then
    local gaugePaddingTop = utils.toNumber(utils.resolveValue(box.gaugepaddingtop, box, state), 2)
    local gaugePaddingBottom = utils.toNumber(utils.resolveValue(box.gaugepaddingbottom, box, state), 0)
    local gaugePaddingLeft = utils.toNumber(utils.resolveValue(box.gaugepaddingleft, box, state), 4)
    local gaugePaddingRight = utils.toNumber(utils.resolveValue(box.gaugepaddingright, box, state), 4)
    local titleReserved = (box and box.titlepos == "bottom") and 20 or 0
    local panelH = math.max(24, rect.h - titleReserved - gaugePaddingTop - gaugePaddingBottom - 2)
    local barWidth = math.max(10, math.floor(rect.w - gaugePaddingLeft - gaugePaddingRight))
    local barX = rect.x + gaugePaddingLeft
    local panelY = rect.y + gaugePaddingTop
    local barY = panelY
    local barH = panelH
    
    local thresholds = box.thresholds or {}
    local barColor = box.fillcolor or BAR_OK_COLOR
    if hasValue then
      barColor = resolveThresholdColor(gaugeValue, thresholds, barColor)
    end
    
    -- Background bar (vertical)
    nodes[#nodes + 1] = {
      type = "rectangle",
      x = barX,
      y = barY,
      w = barWidth,
      h = barH,
      color = box.fillbgcolor or BAR_BG_COLOR,
      filled = true
    }
    
    -- Filled bar (from bottom, grows upward)
    if ratio > 0 then
      local filledH = math.max(1, math.floor(barH * ratio))
      nodes[#nodes + 1] = {
        type = "rectangle",
        x = barX,
        y = barY + (barH - filledH),
        w = barWidth,
        h = filledH,
        color = barColor,
        filled = true
      }
    end

    -- Optional segmented battery look for vertical bars.
    if box.battery then
      local segmentCount = utils.toNumber(utils.resolveValue(box.batterysegments, box, state), 5)
      segmentCount = utils.clamp(math.floor(segmentCount + 0.5), 2, 10)
      local separatorColor = box.bgcolor or BLACK
      for i = 1, segmentCount - 1 do
        local sepY = barY + math.floor((barH * i) / segmentCount)
        nodes[#nodes + 1] = {
          type = "rectangle",
          x = barX,
          y = sepY,
          w = barWidth,
          h = 1,
          color = separatorColor,
          filled = true
        }
      end
    end
    
    -- Value text (above or inside gauge)
    local unit = utils.resolveValue(box.unit, box, state)
    local decimals = utils.resolveValue(box.decimals, box, state)
    local valueText = nil
    
    if not hasValue then
      if unit ~= nil and unit ~= "" then
        valueText = "-- " .. tostring(unit)
      else
        valueText = "--"
      end
    else
      valueText = utils.appendUnit(utils.formatDisplayValue(gaugeValue, decimals), unit)
    end
    
    local textFont = utils.resolveValue(box.valuefont, box, state) or utils.resolveValue(box.font, box, state) or DBLSIZE
    local valuePaddingTop = utils.toNumber(utils.resolveValue(box.valuepaddingtop, box, state), 0)
    local valuePosition = utils.resolveValue(box.valueposition, box, state) or "center"
    local valueAlign = utils.resolveValue(box.valuealign, box, state) or CENTER
    local valueY = barY + math.floor((barH - 8) / 2) + valuePaddingTop

    if valuePosition == "top" then
      valueY = barY + 4 + valuePaddingTop
    elseif valuePosition == "bottom" then
      valueY = barY + barH - 12 + valuePaddingTop
    end
    
    utils.pushLabel(
      nodes,
      barX,
      valueY,
      barWidth,
      valueText,
      utils.resolveTextColor(box, state, WHITE),
      valueAlign,
      textFont
    )
  
  -- HORIZONTAL GAUGE (default)
  else
    local titleReserved = (box and box.titlepos == "top") and 18 or 0
    local panelY = rect.y + titleReserved + 2
    local panelH = math.max(20, rect.h - titleReserved - 4)
    local barHeight = math.max(12, math.floor(panelH * 0.5))
    local barX = rect.x + 4
    local barW = rect.w - 8
    local barY = panelY + math.floor((panelH - barHeight) / 2)
    
    local thresholds = box.thresholds or {}
    local barColor = box.fillcolor or BAR_OK_COLOR
    if hasValue then
      barColor = resolveThresholdColor(gaugeValue, thresholds, barColor)
    end
    
    -- Background bar
    nodes[#nodes + 1] = {
      type = "rectangle",
      x = barX,
      y = barY,
      w = barW,
      h = barHeight,
      color = box.fillbgcolor or BAR_BG_COLOR,
      filled = true
    }
    
    -- Filled bar
    if ratio > 0 then
      nodes[#nodes + 1] = {
        type = "rectangle",
        x = barX,
        y = barY,
        w = math.max(1, math.floor(barW * ratio)),
        h = barHeight,
        color = barColor,
        filled = true
      }
    end
    
    -- Value text
    local unit = utils.resolveValue(box.unit, box, state)
    local decimals = utils.resolveValue(box.decimals, box, state)
    local valueText = nil
    
    if not hasValue then
      if unit ~= nil and unit ~= "" then
        valueText = "-- " .. tostring(unit)
      else
        valueText = "--"
      end
    else
      valueText = utils.appendUnit(utils.formatDisplayValue(gaugeValue, decimals), unit)
    end
    
    local textFont = utils.resolveValue(box.valuefont, box, state) or utils.resolveValue(box.font, box, state) or DBLSIZE
    local valuePaddingLeft = utils.toNumber(utils.resolveValue(box.valuepaddingleft, box, state), 8)
    local valuePaddingTop = utils.toNumber(utils.resolveValue(box.valuepaddingtop, box, state), 0)
    local valueAlign = utils.resolveValue(box.valuealign, box, state) or LEFT
    
    utils.pushLabel(
      nodes,
      barX + valuePaddingLeft,
      barY + math.floor((barHeight - 8) / 2) + valuePaddingTop,
      barW - valuePaddingLeft - 4,
      valueText,
      utils.resolveTextColor(box, state, WHITE),
      valueAlign,
      textFont
    )
  
    -- Battery advanced info (like capacity) - only for horizontal
    if box.battadv then
      local battAdvText = ""
      if source == "smartfuel" or source == "fuel" then
        local voltageText = nil
        if themeCommon and type(themeCommon.formatVoltage) == "function" and type(state and state.voltage) == "number" and state.voltage > 0 then
          local cellText = nil
          local cells = nil
          if type(state and state.batteryCellCount) == "number" and state.batteryCellCount > 0 then
            cells = state.batteryCellCount
          elseif type(themeCommon.estimateCellCount) == "function" then
            cells = themeCommon.estimateCellCount(state)
          end

          if type(cells) == "number" and cells > 0 then
            cellText = string.format("%.2fV (%dS)", state.voltage / cells, cells)
          elseif type(themeCommon.formatCellVoltage) == "function" then
            cellText = themeCommon.formatCellVoltage(state, state.voltage)
          end

          if cellText and cellText ~= "" then
            voltageText = themeCommon.formatVoltage(state.voltage) .. " / " .. cellText
          else
            voltageText = themeCommon.formatVoltage(state.voltage)
          end
        end

        local consumptionText = nil
        local consumedMah = tonumber(state and state.consumedMah)
        if consumedMah and consumedMah >= 0 then
          consumptionText = string.format("%d mah", math.floor(consumedMah + 0.5))
        end

        local singleLineDetails = utils.resolveValue(box.battadvsingleline, box, state)

        if voltageText and consumptionText then
          if singleLineDetails then
            battAdvText = voltageText .. " " .. consumptionText
          else
            battAdvText = voltageText .. "\n" .. consumptionText
          end
        else
          battAdvText = voltageText or consumptionText or ""
        end
      end
      
      if battAdvText ~= "" then
        local battAdvFont = utils.resolveValue(box.battadvfont, box, state) or 0
        local battAdvPaddingTop = utils.toNumber(utils.resolveValue(box.battadvpaddingtop, box, state), math.floor((barHeight - 8) / 2))
        local battAdvPaddingRight = utils.toNumber(utils.resolveValue(box.battadvpaddingright, box, state), 6)
        local battAdvAlign = utils.resolveValue(box.battadvvaluealign, box, state) or RIGHT
        
        utils.pushLabel(
          nodes,
          rect.x + 4,
          barY + battAdvPaddingTop,
          barW - battAdvPaddingRight - 4,
          battAdvText,
          box.battadvtextcolor or WHITE,
          battAdvAlign,
          battAdvFont
        )
      end
    end
  end
end

local function renderArc(nodes, rect, box, state, themeCommon, utils)
  local source = utils.resolveValue(box.source, box, state)
  local rawValue = utils.mapTelemetrySource(source, state)
  local hasValue = type(rawValue) == "number"
  local gaugeValue = utils.toNumber(rawValue, 0)

  local gaugeMin, gaugeMax = resolveGaugeBounds(box, state, utils, 18.0, 25.2)

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
  local arcValueColor = box.fillcolor
  if not arcValueColor then
    if type(box.thresholds) == "table" and #box.thresholds > 0 and hasValue then
      arcValueColor = resolveThresholdColor(gaugeValue, box.thresholds, ARC_OK_COLOR)
    else
      arcValueColor = getArcValueColor(gaugeValue, state, box, themeCommon, utils)
    end
  end

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
  local displayH = tonumber(state and state.zoneH) or tonumber(LCD_H) or 0
  local defaultCenterLift = (displayH >= 400) and 8 or 0
  local valueCenterLift = utils.toNumber(utils.resolveValue(box.value_center_lift, box, state), defaultCenterLift)
  local valueY = cy - math.floor(thickness * 1.3) - valueCenterLift + valueYOffset
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

  local valueColor = utils.resolveTextColor(box, state, WHITE)
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
    utils.resolveFont(box, state, DBLSIZE, "value_font", "value_font_lowres")
  )
  
  -- MAX value display
  if box.arcmax then
    local maxValue = getMaxValue(source, state, box, utils)
    if maxValue and type(maxValue) == "number" and maxValue > 0 then
      local maxPrefix = utils.resolveValue(box.maxprefix, box, state) or "Max: "
      local maxDecimals = utils.resolveValue(box.maxdecimals, box, state)
      local maxUnit = utils.resolveValue(box.maxunit, box, state) or unit or ""
      local maxText = maxPrefix .. utils.formatDisplayValue(maxValue, maxDecimals) .. maxUnit
      
      local maxFont = utils.resolveValue(box.maxfont, box, state) or 0
      local maxTextColor = utils.resolveValue(box.maxtextcolor, box, state) or "orange"
      local maxPosition = utils.resolveValue(box.maxposition, box, state)
      local maxAlign = utils.resolveValue(box.maxalign, box, state) or LEFT
      local maxPaddingTop = utils.toNumber(utils.resolveValue(box.maxpaddingtop, box, state), 30)
      local maxPaddingLeft = utils.toNumber(utils.resolveValue(box.maxpaddingleft, box, state), 20)
      local maxPaddingRight = utils.toNumber(utils.resolveValue(box.maxpaddingright, box, state), 4)
      local maxPaddingBottom = utils.toNumber(utils.resolveValue(box.maxpaddingbottom, box, state), 26)

      local maxX = rect.x + maxPaddingLeft
      local maxY = rect.y + maxPaddingTop
      local maxW = rect.w - maxPaddingLeft - maxPaddingRight

      if maxPosition == "bottom" then
        maxAlign = utils.resolveValue(box.maxalign, box, state) or CENTER
        maxY = rect.y + rect.h - titleReserved - maxPaddingBottom
        if maxY < rect.y + 6 then
          maxY = rect.y + 6
        end
      end
      
      utils.pushLabel(
        nodes,
        maxX,
        maxY,
        maxW,
        maxText,
        maxTextColor,
        maxAlign,
        maxFont
      )
    end
  end
end

function Wrapper.render(nodes, rect, box, state)
  local utils = getUtils()
  local themeCommon = getThemeCommon()
  if not utils then return end

  utils.drawContainer(nodes, rect, box, state)
  
  local subtype = utils.resolveValue(box.subtype, box, state) or "arc"
  
  if subtype == "bar" then
    renderBar(nodes, rect, box or {}, state, themeCommon, utils)
  else
    renderArc(nodes, rect, box or {}, state, themeCommon, utils)
  end
end

return Wrapper
