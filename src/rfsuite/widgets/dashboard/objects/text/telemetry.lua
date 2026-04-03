local Render = {}

function Render.render(nodes, rect, box, state, _, utils)
  local source = utils.resolveValue(box.source, box, state)
  local raw = source ~= nil and utils.mapTelemetrySource(source, state) or nil
  raw = utils.applyTransform(raw, utils.resolveValue(box.transform, box, state))

  local valueText = utils.formatDisplayValue(raw, utils.resolveValue(box.decimals, box, state))
  valueText = utils.appendUnit(valueText, utils.resolveValue(box.unit, box, state))
  local valueFont = utils.resolveValue(box.font, box, state) or MIDSIZE

  local autoSizeChars = utils.resolveValue(box.autosize_chars, box, state)

  if type(autoSizeChars) == "number" and type(valueText) == "string" and string.len(valueText) > autoSizeChars then
    valueFont = utils.resolveValue(box.autosize_font, box, state) or SMLSIZE
  end

  utils.pushLabel(
    nodes,
    rect.x + 4,
    utils.defaultValueY(rect, box),
    rect.w - 8,
    valueText,
    box.textcolor or BLACK,
    box.valuealign or box.titlealign or CENTER,
    valueFont
  )
end

return Render
