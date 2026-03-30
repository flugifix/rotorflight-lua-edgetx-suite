local FlowLayout = {}

local function clamp(v)
  if v < 0 then return 0 end
  return v
end

function FlowLayout.layout(bounds, items, spec, out)
  local cfg = spec or {}
  local result = out or {}

  local gapX = cfg.gapX or 0
  local gapY = cfg.gapY or 0
  local pad = cfg.padding or 0

  local x = bounds.x + pad
  local y = bounds.y + pad
  local rowH = 0
  local maxX = bounds.x + clamp(bounds.w - pad)

  for i = 1, #items do
    local item = items[i]
    local w = clamp(item.w or 0)
    local h = clamp(item.h or 0)

    if x + w > maxX and x > bounds.x + pad then
      x = bounds.x + pad
      y = y + rowH + gapY
      rowH = 0
    end

    local slot = result[i] or {}
    slot.id = item.id or i
    slot.x = x
    slot.y = y
    slot.w = w
    slot.h = h
    result[i] = slot

    x = x + w + gapX
    if h > rowH then
      rowH = h
    end
  end

  for i = #items + 1, #result do
    result[i] = nil
  end

  return result
end

return FlowLayout
