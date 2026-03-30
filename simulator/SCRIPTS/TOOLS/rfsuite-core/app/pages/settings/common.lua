local M = {}

function M.t(i18n, pageKey, key, fallback)
  if i18n and i18n.t then
    return i18n.t("app.pages." .. pageKey .. "." .. key)
  end
  return fallback
end

function M.appendSectionHeader(children, x, y, w, title)
  children[#children + 1] = {
    type = "label",
    x = x,
    y = y,
    text = title,
    color = WHITE,
    font = DBLSIZE
  }

  children[#children + 1] = {
    type = "label",
    x = x + w - 18,
    y = y + 2,
    w = 16,
    text = "v",
    color = WHITE,
    align = RIGHT,
    font = DBLSIZE
  }

  children[#children + 1] = {
    type = "rectangle",
    x = x,
    y = y + 34,
    w = w,
    h = 1,
    color = GREY_DEFAULT,
    filled = true
  }
end

function M.appendSettingsRow(children, x, y, w, labelText, valueText, withArrow)
  local valueW = math.floor(w * 0.50)
  local valueX = x + w - valueW

  children[#children + 1] = {
    type = "label",
    x = x,
    y = y + 10,
    w = valueX - x - 8,
    text = labelText,
    color = WHITE,
    font = MIDSIZE
  }

  children[#children + 1] = {
    type = "rectangle",
    x = valueX,
    y = y,
    w = valueW,
    h = 40,
    color = GREY_DEFAULT,
    filled = true
  }

  local valueLabelW = withArrow and (valueW - 26) or (valueW - 10)
  children[#children + 1] = {
    type = "label",
    x = valueX + 6,
    y = y + 10,
    w = valueLabelW,
    text = valueText,
    color = WHITE,
    align = RIGHT,
    font = MIDSIZE
  }

  if withArrow then
    children[#children + 1] = {
      type = "label",
      x = valueX + valueW - 20,
      y = y + 10,
      w = 14,
      text = "v",
      color = WHITE,
      align = RIGHT,
      font = MIDSIZE
    }
  end

  children[#children + 1] = {
    type = "rectangle",
    x = x,
    y = y + 40,
    w = w,
    h = 1,
    color = GREY_DEFAULT,
    filled = true
  }
end

function M.buildSimplePage(ctx, pageKey, sectionKey, sectionFallback, rows)
  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local i18n = ctx.i18n

  M.appendSectionHeader(children, x, y, w, M.t(i18n, pageKey, sectionKey, sectionFallback))

  local rowY = y + 46
  for i = 1, #rows do
    local row = rows[i]
    local yOffset = (i - 1) * 44
    local label = M.t(i18n, pageKey, row.labelKey, row.labelFallback)
    local value = M.t(i18n, pageKey, row.valueKey, row.valueFallback)
    M.appendSettingsRow(children, x, rowY + yOffset, w, label, value, row.withArrow ~= false)
  end
end

return M
