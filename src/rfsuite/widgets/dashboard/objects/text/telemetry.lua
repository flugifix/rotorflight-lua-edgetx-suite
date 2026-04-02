local Render = {}

function Render.render(nodes, rect, box, state, _, utils)
  local source = utils.resolveValue(box.source, box, state)
  local raw = source ~= nil and utils.mapTelemetrySource(source, state) or nil
  raw = utils.applyTransform(raw, utils.resolveValue(box.transform, box, state))

  local valueText = utils.formatDisplayValue(raw, utils.resolveValue(box.decimals, box, state))
  valueText = utils.appendUnit(valueText, utils.resolveValue(box.unit, box, state))

  utils.pushLabel(
    nodes,
    rect.x + 4,
    utils.defaultValueY(rect, box),
    rect.w - 8,
    valueText,
    box.textcolor or BLACK,
    box.valuealign or box.titlealign or CENTER,
    MIDSIZE
  )
end

return Render
