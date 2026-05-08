local Render = {}

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local valueText = themeCommon.blackboxLabel(state)
  valueText = utils.applyLowResMaxChars(valueText, box, state, "max_chars_lowres")
  local valueFont = utils.resolveFont(box, state, MIDSIZE, "font", "font_lowres")

  local autoSizeChars = utils.resolveValue(box.autosize_chars, box, state)
  if type(autoSizeChars) == "number" and type(valueText) == "string" and #valueText > autoSizeChars then
    local autoSizeFont = utils.resolveValue(box.autosize_font, box, state)
    valueFont = autoSizeFont or SMLSIZE
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
