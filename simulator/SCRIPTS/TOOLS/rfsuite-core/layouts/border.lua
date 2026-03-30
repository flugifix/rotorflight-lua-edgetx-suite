local BorderLayout = {}

local function clamp(value)
  if value < 0 then
    return 0
  end
  return value
end

function BorderLayout.layout(bounds, spec, out)
  local cfg = spec or {}
  local result = out or {}

  local gap = cfg.gap or 0
  local pad = cfg.padding or 0
  local northH = cfg.northHeight or 0
  local southH = cfg.southHeight or 0
  local westW = cfg.westWidth or 0
  local eastW = cfg.eastWidth or 0

  local innerX = bounds.x + pad
  local innerY = bounds.y + pad
  local innerW = clamp(bounds.w - (pad * 2))
  local innerH = clamp(bounds.h - (pad * 2))

  local topY = innerY
  local bottomY = innerY + innerH

  result.north = {
    x = innerX,
    y = topY,
    w = innerW,
    h = clamp(northH)
  }

  topY = topY + result.north.h
  if result.north.h > 0 then
    topY = topY + gap
  end

  result.south = {
    x = innerX,
    y = clamp(bottomY - clamp(southH)),
    w = innerW,
    h = clamp(southH)
  }

  bottomY = result.south.y
  if result.south.h > 0 then
    bottomY = bottomY - gap
  end

  local centerH = clamp(bottomY - topY)

  result.west = {
    x = innerX,
    y = topY,
    w = clamp(westW),
    h = centerH
  }

  local centerX = innerX + result.west.w
  if result.west.w > 0 then
    centerX = centerX + gap
  end

  result.east = {
    x = clamp(innerX + innerW - clamp(eastW)),
    y = topY,
    w = clamp(eastW),
    h = centerH
  }

  local centerRight = result.east.x
  if result.east.w > 0 then
    centerRight = centerRight - gap
  else
    centerRight = innerX + innerW
  end

  result.center = {
    x = centerX,
    y = topY,
    w = clamp(centerRight - centerX),
    h = centerH
  }

  return result
end

return BorderLayout
