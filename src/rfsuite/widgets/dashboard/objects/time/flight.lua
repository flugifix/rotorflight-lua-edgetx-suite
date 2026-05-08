local Render = {}

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local valueText = themeCommon.formatDuration(state.flightSeconds)
  valueText = utils.applyLowResMaxChars(valueText, box, state, "max_chars_lowres")
  local valueFont = utils.resolveFont(box, state, MIDSIZE, "font", "font_lowres")
  utils.pushLabel(nodes, rect.x + 4, utils.defaultValueY(rect, box), rect.w - 8, valueText, box.textcolor or BLACK, box.valuealign or box.titlealign or CENTER, valueFont)
end

return Render
