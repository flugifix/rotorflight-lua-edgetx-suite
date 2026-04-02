local Render = {}

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local source = utils.resolveValue(box.source, box, state)
  local raw = nil
  if source == "min_link" then
    raw = themeCommon.formatInteger(state.lastMinLq, "%")
  elseif source == "min_voltage_cell" then
    raw = themeCommon.formatCellVoltage(state, state.lastMinVoltage)
  end

  local valueText = raw and tostring(raw) or "--"
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
