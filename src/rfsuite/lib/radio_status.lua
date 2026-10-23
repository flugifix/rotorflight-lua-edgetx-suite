local M = {}

function M.txVoltage()
  local ok, value = pcall(getValue, "tx-voltage")
  if ok and type(value) == "number" and value > 0 then return value end
  return nil
end

function M.txBattery()
  local volts = M.txVoltage()
  local minimum, maximum, warning = 6.6, 8.4, nil
  local ok, settings = pcall(getGeneralSettings)
  if ok and type(settings) == "table" then
    if type(settings.battMin) == "number" and settings.battMin > 0 then minimum = settings.battMin end
    if type(settings.battMax) == "number" and settings.battMax > minimum then maximum = settings.battMax end
    if type(settings.battWarn) == "number" and settings.battWarn > 0 then warning = settings.battWarn end
  end
  local percent, low = nil, false
  if volts then
    percent = math.floor((volts - minimum) / (maximum - minimum) * 100 + 0.5)
    percent = math.max(0, math.min(100, percent))
    if warning then
      local warningPercent = math.ceil(100 - (100 * (maximum - warning) / (maximum - minimum)))
      low = percent < warningPercent
    end
  end
  return volts, percent, low
end

return M
