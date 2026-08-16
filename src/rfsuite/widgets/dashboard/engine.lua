local Engine = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require)
if not requireModule then
  local rChunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/require.lua", "t")
  if rChunk then
    requireModule = rChunk()
  end
end
requireModule = requireModule or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  return assert(loadScript(fullPath, "t"))()
end

local Common = requireModule("widgets/dashboard/themes/default/common.lua")
local Utils = requireModule("widgets/dashboard/objects/common.lua")
local Sensors = requireModule("lib/sensors.lua")

local OBJECTS_BASE = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/"
local objectWrappers = {}

local function isSimulator()
  if type(getVersion) ~= "function" then return false end
  local ok, _, fw = pcall(getVersion)
  if not ok or type(fw) ~= "string" then return false end
  return string.sub(string.lower(fw), -4) == "simu"
end

local function loadObjectWrapper(typ)
  if objectWrappers[typ] ~= nil then
    return objectWrappers[typ]
  end

  local wrapper = requireModule("widgets/dashboard/objects/" .. typ .. ".lua")
  if not wrapper or type(wrapper) ~= "table" then
    objectWrappers[typ] = false
    return nil
  end

  objectWrappers[typ] = wrapper
  return wrapper
end

local function resolveGrid(layout)
  local cols = math.max(1, tonumber(layout and layout.cols) or 1)
  local rows = math.max(1, tonumber(layout and layout.rows) or 1)
  local padding = tonumber(layout and layout.padding) or 0
  return cols, rows, padding
end

local function canReuseGridRects(cache, zone, boxes, cols, rows, padding)
  return cache
    and cache.boxes == boxes
    and cache.zoneX == zone.x
    and cache.zoneY == zone.y
    and cache.zoneW == zone.w
    and cache.zoneH == zone.h
    and cache.cols == cols
    and cache.rows == rows
    and cache.padding == padding
end

local function buildGridRects(zone, boxes, cols, rows, padding)
  local rects = {}

  local function buildTrackStarts(totalSize, trackCount, gap)
    local starts = {}
    local sizes = {}
    local totalGap = (trackCount - 1) * gap
    local usable = totalSize - totalGap
    if usable < 0 then usable = 0 end

    local base = math.floor(usable / trackCount)
    local remainder = usable - (base * trackCount)
    local cursor = 0

    for i = 1, trackCount do
      -- Keep early tracks stable and distribute extra pixels to the right/bottom edge.
      local extra = (i > (trackCount - remainder)) and 1 or 0
      sizes[i] = base + extra
      starts[i] = cursor
      cursor = cursor + sizes[i] + gap
    end

    return starts, sizes
  end

  local colStarts, colSizes = buildTrackStarts(zone.w, cols, padding)
  local rowStarts, rowSizes = buildTrackStarts(zone.h, rows, padding)

  for index = 1, #boxes do
    local box = boxes[index]
    local col = Utils.clamp(tonumber(box.col) or 1, 1, cols)
    local row = Utils.clamp(tonumber(box.row) or 1, 1, rows)
    local colSpan = math.max(1, tonumber(box.colspan) or 1)
    local rowSpan = math.max(1, tonumber(box.rowspan) or 1)
    local endCol = Utils.clamp(col + colSpan - 1, 1, cols)
    local endRow = Utils.clamp(row + rowSpan - 1, 1, rows)

    local x = zone.x + colStarts[col]
    local y = zone.y + rowStarts[row]

    local w = 0
    for c = col, endCol do
      w = w + colSizes[c]
    end
    w = w + (endCol - col) * padding

    local h = 0
    for r = row, endRow do
      h = h + rowSizes[r]
    end
    h = h + (endRow - row) * padding

    rects[#rects + 1] = { box = box, x = x, y = y, w = w, h = h }
  end

  return rects
end
local function renderBox(nodes, rect, state)
  local box = rect.box
  local typ = box.type or "text"
  local wrapper = loadObjectWrapper(typ)
  if wrapper and type(wrapper.render) == "function" then
    wrapper.render(nodes, rect, box, state)
  else
    Utils.drawContainer(nodes, rect, box, state)
    Utils.pushLabel(nodes, rect.x + 4, Utils.defaultValueY(rect, box), rect.w - 8, "--", box.textcolor or BLACK, box.valuealign or box.titlealign or CENTER, MIDSIZE)
  end
end

function Engine.build(zone, state, theme)
  local nodes = {}
  local layout = Utils.resolveValue(theme.layout, nil, state) or { cols = 1, rows = 1, padding = 0 }
  local boxes = Utils.resolveValue(theme.boxes, nil, state) or {}
  local cols, rows, padding = resolveGrid(layout)
  local engineCache = state and state._engineCache
  if type(engineCache) ~= "table" and type(state) == "table" then
    engineCache = {}
    state._engineCache = engineCache
  end

  local rects = nil
  if canReuseGridRects(engineCache and engineCache.main, zone, boxes, cols, rows, padding) then
    rects = engineCache.main.rects
  else
    rects = buildGridRects(zone, boxes, cols, rows, padding)
    if engineCache then
      engineCache.main = {
        boxes = boxes,
        zoneX = zone.x,
        zoneY = zone.y,
        zoneW = zone.w,
        zoneH = zone.h,
        cols = cols,
        rows = rows,
        padding = padding,
        rects = rects
      }
    end
  end

  for i = 1, #rects do
    renderBox(nodes, rects[i], state)
  end

  local headerLayout = Utils.resolveValue(theme.header_layout, nil, state)
  local headerBoxes = Utils.resolveValue(theme.header_boxes, nil, state)
  if type(headerLayout) == "table" and type(headerBoxes) == "table" and #headerBoxes > 0 then
    local headerHeight = math.max(24, math.floor(zone.h * 0.16))
    local headerZone = { x = zone.x, y = zone.y, w = zone.w, h = headerHeight }
    local hCols, hRows, hPadding = resolveGrid(headerLayout)
    local headerRects = nil
    if canReuseGridRects(engineCache and engineCache.header, headerZone, headerBoxes, hCols, hRows, hPadding) then
      headerRects = engineCache.header.rects
    else
      headerRects = buildGridRects(headerZone, headerBoxes, hCols, hRows, hPadding)
      if engineCache then
        engineCache.header = {
          boxes = headerBoxes,
          zoneX = headerZone.x,
          zoneY = headerZone.y,
          zoneW = headerZone.w,
          zoneH = headerZone.h,
          cols = hCols,
          rows = hRows,
          padding = hPadding,
          rects = headerRects
        }
      end
    end
    for i = 1, #headerRects do
      renderBox(nodes, headerRects[i], state)
    end
  end

  return nodes
end

local function hashNum(h, num)
  local n = math.floor((num or 0) + 0.5)
  return (h * 31 + n) % 2147483647
end

local function hashStr(h, str)
  if type(str) ~= "string" then return h end
  for i = 1, #str do
    h = (h * 31 + string.byte(str, i)) % 2147483647
  end
  return h
end

function Engine.renderKey(state, boxSources)
  local h = 2166136261
  local voltage = Utils.toNumber(state and state.voltage, 0)
  local lq = Utils.toNumber(state and state.lq, 0)
  local fuel = Utils.toNumber(state and state.fuel, 0)
  local rpm = Utils.toNumber(state and state.rpm, 0)
  local flight = Utils.toNumber(state and state.flightSeconds, 0)
  local total = Utils.toNumber(state and state.totalFlightSeconds, 0)
  local bb_used = state and state.dataflash and state.dataflash.used or 0
  local bb_total = state and state.dataflash and state.dataflash.total or 0
  local cells = Utils.toNumber(state and state.batteryCellCount, 0)
  local themeMin = Utils.toNumber(state and state.themeConfig and state.themeConfig.v_min, 0)
  local themeMax = Utils.toNumber(state and state.themeConfig and state.themeConfig.v_max, 0)
  local armFlags = Utils.toNumber(state and state.armFlags, 0)

  h = hashNum(h, lq)
  h = hashNum(h, fuel)
  h = hashNum(h, rpm)
  h = hashNum(h, flight)
  h = hashNum(h, total)
  h = hashNum(h, voltage * 10)
  h = hashNum(h, bb_used)
  h = hashNum(h, bb_total)
  h = hashNum(h, cells)
  h = hashNum(h, themeMin * 10)
  h = hashNum(h, themeMax * 10)
  h = hashNum(h, armFlags)

  if boxSources and state then
    for i = 1, #boxSources do
      local source = boxSources[i]
      local v = nil
      if source == "esc_temp" then v = state.escTemp
      elseif source == "mcu_temp" then v = state.mcuTemp
      elseif source == "pid_profile" then v = state.profile
      elseif source == "rate_profile" then v = state.rateProfile
      elseif source == "battery_profile" then v = state.batteryProfile
      elseif source == "governor" then
        h = hashNum(h, state.governor or 0)
        h = hashNum(h, state.armDisableFlags or 0)
      else
        v = state[source]
      end
      if type(v) == "number" then
        h = hashNum(h, v * 10)
      elseif type(v) == "string" then
        h = hashStr(h, v)
      end
    end
  end
  return h
end

return Engine