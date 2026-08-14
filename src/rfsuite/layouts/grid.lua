local GridLayout = {}

local function clamp(v)
  if v < 0 then return 0 end
  return v
end

local function buildTracks(total, count, gap, weights, out)
  local tracks = out or {}
  if count <= 0 then
    return tracks
  end

  local totalGap = gap * (count - 1)
  local usable = clamp(total - totalGap)

  local weightSum = 0
  for i = 1, count do
    local w = (weights and weights[i]) or 1
    if w < 0 then w = 0 end
    tracks[i] = tracks[i] or {}
    tracks[i].weight = w
    weightSum = weightSum + w
  end

  if weightSum <= 0 then
    weightSum = count
    for i = 1, count do
      tracks[i].weight = 1
    end
  end

  local remaining = usable
  for i = 1, count do
    local size = math.floor((usable * tracks[i].weight) / weightSum)
    tracks[i].size = size
    remaining = remaining - size
  end

  local i = 1
  while remaining > 0 and count > 0 do
    tracks[i].size = tracks[i].size + 1
    remaining = remaining - 1
    i = i + 1
    if i > count then i = 1 end
  end

  for j = count + 1, #tracks do
    tracks[j] = nil
  end

  return tracks
end

function GridLayout.layout(bounds, spec, out)
  local cfg = spec or {}
  local result = out or {}

  local rows = cfg.rows or 1
  local cols = cfg.cols or 1
  local gapX = cfg.gapX or cfg.gap or 0
  local gapY = cfg.gapY or cfg.gap or 0
  local pad = cfg.padding or 0

  local innerX = bounds.x + pad
  local innerY = bounds.y + pad
  local innerW = clamp(bounds.w - (pad * 2))
  local innerH = clamp(bounds.h - (pad * 2))

  result._colTracks = buildTracks(innerW, cols, gapX, cfg.colWeights, result._colTracks)
  result._rowTracks = buildTracks(innerH, rows, gapY, cfg.rowWeights, result._rowTracks)

  local colPos = result._colPos or {}
  local rowPos = result._rowPos or {}

  local cx = innerX
  for c = 1, cols do
    colPos[c] = cx
    cx = cx + result._colTracks[c].size + gapX
  end

  local cy = innerY
  for r = 1, rows do
    rowPos[r] = cy
    cy = cy + result._rowTracks[r].size + gapY
  end

  result._colPos = colPos
  result._rowPos = rowPos

  local items = cfg.items or {}
  for i = 1, #items do
    local item = items[i]
    local row = item.row or 1
    local col = item.col or 1
    local rowSpan = item.rowSpan or 1
    local colSpan = item.colSpan or 1

    if row < 1 then row = 1 end
    if col < 1 then col = 1 end
    if row > rows then row = rows end
    if col > cols then col = cols end

    local endRow = row + rowSpan - 1
    local endCol = col + colSpan - 1
    if endRow > rows then endRow = rows end
    if endCol > cols then endCol = cols end

    local w = 0
    for c = col, endCol do
      w = w + result._colTracks[c].size
    end
    w = w + gapX * (endCol - col)

    local h = 0
    for r = row, endRow do
      h = h + result._rowTracks[r].size
    end
    h = h + gapY * (endRow - row)

    local slot = result[i] or {}
    slot.id = item.id or i
    slot.row = row
    slot.col = col
    slot.x = colPos[col]
    slot.y = rowPos[row]
    slot.w = w
    slot.h = h
    slot.data = item.data
    result[i] = slot
  end

  for i = #items + 1, #result do
    result[i] = nil
  end

  return result
end

return GridLayout
