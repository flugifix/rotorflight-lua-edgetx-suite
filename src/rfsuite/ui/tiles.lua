-- ui/tiles.lua
-- Pure tile rendering helpers: layout calculation, text wrapping, tile widget builder.

local Tiles = {}

local function formatTileText(text)
  if type(text) ~= "string" then return "" end
  local len = string.len(text)
  if len <= 11 then return text end
  local bestSpace, mid = nil, math.floor(len / 2)
  for i = 1, len do
    if string.sub(text, i, i) == " " then
      if bestSpace == nil or math.abs(i - mid) < math.abs(bestSpace - mid) then
        bestSpace = i
      end
    end
  end
  if bestSpace then
    return string.sub(text, 1, bestSpace - 1) .. "\n" .. string.sub(text, bestSpace + 1)
  end
  return string.sub(text, 1, mid) .. "\n" .. string.sub(text, mid + 1)
end

function Tiles.computeColumns(width, minCardWidth, maxColumns)
  local cols = math.floor(width / minCardWidth)
  if cols < 1 then cols = 1 end
  if cols > maxColumns then cols = maxColumns end
  return cols
end

function Tiles.flattenRootCards(groups)
  local flat = {}
  for i = 1, #groups do
    local cards = groups[i].cards or {}
    for j = 1, #cards do flat[#flat + 1] = cards[j] end
  end
  return flat
end

-- Append LVGL widgets for a single tile into `children`.
-- LVGL handles focus/ENTER natively between button tiles via its built-in focus box.
-- `focused` is accepted for API compatibility but visual focus is handled by LVGL.
function Tiles.append(children, x, y, size, iconFile, text, focused, pressHandler, enabled)
  local isEnabled = enabled ~= false

  children[#children + 1] = {
    type  = "button",
    x = x, y = y, w = size, h = size,
    text  = "",
    -- Disabled tiles must be excluded from wheel focus traversal.
    active = function()
      return isEnabled
    end,
    press = isEnabled and pressHandler or nil
  }

  if not isEnabled then
    children[#children + 1] = {
      type = "rectangle", x = x + 1, y = y + 1, w = size - 2, h = size - 2,
      color = GREY_DEFAULT, filled = true
    }
  end

  if iconFile then
    local iconSize = math.max(16, math.floor(size * 0.36))
    children[#children + 1] = {
      type = "image",
      x = x + math.floor((size - iconSize) / 2),
      y = y + math.max(5, math.floor(size * 0.08)),
      w = iconSize, h = iconSize,
      file = iconFile
    }
  end

  children[#children + 1] = {
    type  = "label",
    x = x + 4,
    y = y + math.floor(size * 0.56),
    w = size - 8,
    text  = formatTileText(text),
    font  = SMLSIZE,
    color = isEnabled and BLACK or WHITE,
    align = CENTER
  }
end

return Tiles
