local Render = {}

local function useFahrenheit()
  local prefs = type(_G) == "table" and _G.rfsuite and _G.rfsuite.preferences or nil
  local localizations = prefs and prefs.localizations or nil
  return tonumber(localizations and localizations.temperature_unit) == 1
end

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local source = utils.resolveValue(box.source, box, state)
  local raw = nil

  local function formatWithUnit(value)
    local adjustedValue = value
    local unit = utils.resolveValue(box.unit, box, state)

    if source == "esc_temp" or source == "mcu_temp" then
      if useFahrenheit() and type(adjustedValue) == "number" then
        adjustedValue = (adjustedValue * 9 / 5) + 32
        unit = "°F"
      else
        unit = "°C"
      end
    end

    local transformed = utils.applyTransform(adjustedValue, utils.resolveValue(box.transform, box, state))
    local decimals = utils.resolveValue(box.decimals, box, state)
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
      elseif source == "mcu_temp" then
        statValue = state and (state.lastFlightMaxMcuTemp or state.currentFlightMaxMcuTemp or state.mcuTemp)
      elseif source == "watts" then
        statValue = state and (state.lastFlightMaxWatts or state.currentFlightMaxWatts or state.watts)
      elseif source == "altitude" then
        statValue = state and (state.lastFlightMaxAltitude or state.currentFlightMaxAltitude or state.altitude)
      elseif source == "esc_temp" then
        statValue = state and (state.lastFlightMaxEscTemp or state.currentFlightMaxEscTemp or state.escTemp)
      elseif source == "smartconsumption" then
        statValue = state and state.consumedMah
      end
    elseif stattype == "min" then
      if source == "fuel" then
        statValue = state and (state.lastFlightMinFuel or state.currentFlightMinFuel or state.fuel)
      elseif source == "rpm" then
        statValue = state and (state.lastFlightMinRpm or state.currentFlightMinRpm or state.rpm)
      elseif source == "current" then
        statValue = state and (state.lastFlightMinCurrent or state.currentFlightMinCurrent or state.current)
      end
    elseif stattype == "consumed" then
      if source == "current" then
        statValue = state and state.consumedMah
      end
    elseif stattype == "cell" then
      if source == "voltage" then
        local voltage = state and state.voltage
        local cellCount = state and state.batteryCellCount or 6
        if type(voltage) == "number" and cellCount > 0 then
          statValue = voltage / cellCount
        end
      end
    elseif stattype == "count" then
      statValue = utils.mapTelemetrySource(source, state)
    elseif stattype == "time" then
      statValue = utils.mapTelemetrySource(source, state)
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
