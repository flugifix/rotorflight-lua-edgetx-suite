local Render = {}

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local valueText = themeCommon.formatDuration(state.flightSeconds)
  valueText = utils.applyLowResMaxChars(valueText, box, state, "max_chars_lowres")
  local valueFont = utils.resolveFont(box, state, MIDSIZE, "font", "font_lowres")
  local valueY = utils.defaultValueY(rect, box)
  local valuePosition = utils.resolveValue(box.valueposition, box, state)
  if valuePosition == "center" then
    local valuePaddingTop = utils.toNumber(utils.resolveValue(box.valuepaddingtop, box, state), 0)
    local textHeight = utils.toNumber(utils.resolveValue(box.valueheight, box, state), 18)
    valueY = rect.y + math.floor((rect.h - textHeight) / 2) + valuePaddingTop
  end
  utils.pushLabel(nodes, rect.x + 4, valueY, rect.w - 8, valueText, utils.resolveTextColor(box, state, WHITE), box.valuealign or box.titlealign or CENTER, valueFont)
end

return Render
