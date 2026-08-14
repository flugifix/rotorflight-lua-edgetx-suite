local Render = {}

local boxConfigCache = setmetatable({}, { __mode = "k" })

local FAST_STATE_SOURCES = {
  pid_profile = "profile",
  rate_profile = "rateProfile",
  battery_profile = "batteryProfile",
  link = "lq",
  voltage = "voltage",
  rpm = "rpm",
  fuel = "fuel",
  governor = "governor",
  esc_temp = "escTemp",
  mcu_temp = "mcuTemp"
}

local function compileBoxConfig(box)
  local cfg = {
    source = box and box.source or nil,
    sourceDynamic = type(box and box.source) == "function",
    transform = box and box.transform or nil,
    transformDynamic = type(box and box.transform) == "function",
    decimals = box and box.decimals or nil,
    decimalsDynamic = type(box and box.decimals) == "function",
    unit = box and box.unit or nil,
    unitDynamic = type(box and box.unit) == "function",
    font = box and box.font or nil,
    fontDynamic = type(box and box.font) == "function",
    fontLowRes = box and box.font_lowres or nil,
    fontLowResDynamic = type(box and box.font_lowres) == "function",
    autoSizeChars = box and box.autosize_chars or nil,
    autoSizeCharsDynamic = type(box and box.autosize_chars) == "function",
    autoSizeFont = box and box.autosize_font or nil,
    autoSizeFontDynamic = type(box and box.autosize_font) == "function"
  }
  boxConfigCache[box] = cfg
  return cfg
end

local function getBoxConfig(box)
  local cfg = box and boxConfigCache[box] or nil
  if cfg then return cfg end
  return compileBoxConfig(box)
end

local function mapSourceFast(source, state, utils)
  if type(source) ~= "string" then
    return nil
  end

  local stateKey = FAST_STATE_SOURCES[source]
  if stateKey and type(state) == "table" then
    local direct = state[stateKey]
    if direct ~= nil then
      return direct
    end
  end

  return utils.mapTelemetrySource(source, state)
end

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local cfg = getBoxConfig(box)

  local source = cfg.source
  if cfg.sourceDynamic then
    source = utils.resolveValue(source, box, state)
  end

  local raw = source ~= nil and mapSourceFast(source, state, utils) or nil

  local transform = cfg.transform
  if cfg.transformDynamic then
    transform = utils.resolveValue(transform, box, state)
  end
  raw = utils.applyTransform(raw, transform)

  local decimals = cfg.decimals
  if cfg.decimalsDynamic then
    decimals = utils.resolveValue(decimals, box, state)
  end

  local valueText = nil
  if source == "voltage" and themeCommon and type(themeCommon.formatVoltage) == "function" then
    valueText = themeCommon.formatVoltage(raw)
  else
    valueText = utils.formatDisplayValue(raw, decimals)
  end

  local unit = cfg.unit
  if cfg.unitDynamic then
    unit = utils.resolveValue(unit, box, state)
  end
  if not (source == "voltage" and themeCommon and type(themeCommon.formatVoltage) == "function") then
    valueText = utils.appendUnit(valueText, unit)
  end

  local valueFont = cfg.font
  if cfg.fontDynamic then
    valueFont = utils.resolveValue(valueFont, box, state)
  end
  if utils.isLowResolution(state) then
    local lowFont = cfg.fontLowRes
    if cfg.fontLowResDynamic then
      lowFont = utils.resolveValue(lowFont, box, state)
    end
    if lowFont ~= nil then
      valueFont = lowFont
    end
  end
  valueFont = valueFont or MIDSIZE

  valueText = utils.applyLowResMaxChars(valueText, box, state, "max_chars_lowres")

  local autoSizeChars = cfg.autoSizeChars
  if cfg.autoSizeCharsDynamic then
    autoSizeChars = utils.resolveValue(autoSizeChars, box, state)
  end

  if type(autoSizeChars) == "number" and type(valueText) == "string" and #valueText > autoSizeChars then
    local autoSizeFont = cfg.autoSizeFont
    if cfg.autoSizeFontDynamic then
      autoSizeFont = utils.resolveValue(autoSizeFont, box, state)
    end
    valueFont = autoSizeFont or SMLSIZE
  end

  utils.pushLabel(
    nodes,
    rect.x + 4,
    utils.defaultValueY(rect, box),
    rect.w - 8,
    valueText,
    utils.resolveTextColor(box, state, WHITE),
    box.valuealign or box.titlealign or CENTER,
    valueFont
  )
end

return Render
