local Render = {}

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local valueText = themeCommon.formatInteger(state.flights, "")
  local valueFont = utils.resolveValue(box.font, box, state) or MIDSIZE
  utils.pushLabel(nodes, rect.x + 4, utils.defaultValueY(rect, box), rect.w - 8, valueText, box.textcolor or BLACK, box.valuealign or box.titlealign or CENTER, valueFont)
end

return Render
