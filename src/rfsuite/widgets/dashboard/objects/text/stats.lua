local Render = {}

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local source = utils.resolveValue(box.source, box, state)
  local raw = nil

  local function formatWithUnit(value)
    local transformed = utils.applyTransform(value, utils.resolveValue(box.transform, box, state))
    local decimals = utils.resolveValue(box.decimals, box, state)
    local unit = utils.resolveValue(box.unit, box, state)
    return utils.appendUnit(utils.formatDisplayValue(transformed, decimals), unit)
  end

  if source == "min_link" then
    raw = themeCommon.formatInteger(state.lastMinLq, "%")
  elseif source == "min_voltage_cell" then
    raw = themeCommon.formatCellVoltage(state, state.lastMinVoltage)
  else
    local stattype = utils.resolveValue(box.stattype, box, state)
    local statSource = nil
    if type(source) == "string" and source ~= "" then
      if stattype == "max" then
        statSource = source .. "+"
      elseif stattype == "min" then
        statSource = source .. "-"
      end
    end

    local statValue = nil
    if stattype == "max" then
      if source == "throttle_percent" then
        statValue = state and (state.lastFlightMaxThrottlePercent or state.currentFlightMaxThrottlePercent or state.throttlePercent)
      elseif source == "rpm" then
        statValue = state and (state.lastFlightMaxRpm or state.currentFlightMaxRpm or state.rpm)
      elseif source == "current" then
        if statSource then
          statValue = utils.mapTelemetrySource(statSource, state)
        end
        if statValue == nil then
          statValue = state and (state.lastFlightMaxCurrent or state.currentFlightMaxCurrent or state.current)
        end
      elseif source == "watts" then
        statValue = state and (state.lastFlightMaxWatts or state.currentFlightMaxWatts or state.watts)
      elseif source == "esc_temp" then
        statValue = state and (state.lastFlightMaxEscTemp or state.currentFlightMaxEscTemp or state.escTemp)
      elseif source == "smartconsumption" then
        statValue = state and state.consumedMah
      end
    elseif stattype == "min" then
      if source == "fuel" then
        statValue = state and (state.lastFlightMinFuel or state.currentFlightMinFuel or state.fuel)
      end
    end

    if statValue == nil and statSource then
      statValue = utils.mapTelemetrySource(statSource, state)
    end
    if statValue == nil and type(source) == "string" then
      statValue = utils.mapTelemetrySource(source, state)
    end

    if statValue ~= nil then
      raw = formatWithUnit(statValue)
    end
  end

  local valueText = raw and tostring(raw) or "--"
  valueText = utils.applyLowResMaxChars(valueText, box, state, "max_chars_lowres")
  utils.pushLabel(
    nodes,
    rect.x + 4,
    utils.defaultValueY(rect, box),
    rect.w - 8,
    valueText,
    box.textcolor or BLACK,
    box.valuealign or box.titlealign or CENTER,
    utils.resolveFont(box, state, MIDSIZE, "font", "font_lowres")
  )
end

return Render
