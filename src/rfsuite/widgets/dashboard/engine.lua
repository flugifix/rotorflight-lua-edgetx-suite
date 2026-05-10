local Engine = {}

local Common = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/default/common.lua", "t"))()
local Utils = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/common.lua", "t"))()
local Sensors = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/sensors.lua", "t"))()

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

  local chunk = loadScript(OBJECTS_BASE .. typ .. ".lua", "t")
  if not chunk then
    objectWrappers[typ] = false
    return nil
  end

  local ok, wrapper = pcall(chunk)
  if not ok or type(wrapper) ~= "table" then
    objectWrappers[typ] = false
    return nil
  end

  objectWrappers[typ] = wrapper
  return wrapper
end

local function buildGridRects(zone, layout, boxes)
  local rects = {}
  local cols = math.max(1, tonumber(layout and layout.cols) or 1)
  local rows = math.max(1, tonumber(layout and layout.rows) or 1)
  local padding = tonumber(layout and layout.padding) or 0
  local cellW = math.floor((zone.w - (cols - 1) * padding) / cols)
  local cellH = math.floor((zone.h - (rows - 1) * padding) / rows)

  for index = 1, #boxes do
    local box = boxes[index]
    local col = Utils.clamp(tonumber(box.col) or 1, 1, cols)
    local row = Utils.clamp(tonumber(box.row) or 1, 1, rows)
    local colSpan = math.max(1, tonumber(box.colspan) or 1)
    local rowSpan = math.max(1, tonumber(box.rowspan) or 1)
    local endCol = Utils.clamp(col + colSpan - 1, 1, cols)
    local endRow = Utils.clamp(row + rowSpan - 1, 1, rows)

    local x = zone.x + (col - 1) * (cellW + padding)
    local y = zone.y + (row - 1) * (cellH + padding)
    local w = (endCol - col + 1) * cellW + (endCol - col) * padding
    local h = (endRow - row + 1) * cellH + (endRow - row) * padding

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
  local rects = buildGridRects(zone, layout, boxes)

  local maxMainRects = #rects
  local maxHeaderRects = 9999
  if isSimulator() then
    -- Simulator has a stricter per-refresh instruction budget than TX16.
    -- Render a reduced subset to keep the widget alive in desktop simulation.
    maxMainRects = math.min(maxMainRects, 14)
    maxHeaderRects = 4
  end

  for i = 1, maxMainRects do
    renderBox(nodes, rects[i], state)
  end

  local headerLayout = Utils.resolveValue(theme.header_layout, nil, state)
  local headerBoxes = Utils.resolveValue(theme.header_boxes, nil, state)
  if type(headerLayout) == "table" and type(headerBoxes) == "table" and #headerBoxes > 0 then
    local headerHeight = math.max(24, math.floor(zone.h * 0.16))
    local headerZone = { x = zone.x, y = zone.y, w = zone.w, h = headerHeight }
    local headerRects = buildGridRects(headerZone, headerLayout, headerBoxes)
    local headerLimit = math.min(#headerRects, maxHeaderRects)
    for i = 1, headerLimit do
      renderBox(nodes, headerRects[i], state)
    end
  end

  return nodes
end

function Engine.renderKey(state, boxSources)
  local voltage = Utils.toNumber(state and state.voltage, 0)
  local lq = Utils.toNumber(state and state.lq, 0)
  local fuel = Utils.toNumber(state and state.fuel, 0)
  local rpm = Utils.toNumber(state and state.rpm, 0)
  local flight = Utils.toNumber(state and state.flightSeconds, 0)
  local total = Utils.toNumber(state and state.totalFlightSeconds, 0)
  local bb_used = state and state.dataflash and state.dataflash.used or 0
  local bb_total = state and state.dataflash and state.dataflash.total or 0
  local cells = Utils.toNumber(state and state.batteryCellCount, 0)
  local armFlags = Utils.toNumber(state and state.armFlags, 0)
  local parts = {
    tostring(math.floor(lq + 0.5)),
    tostring(math.floor(fuel + 0.5)),
    tostring(math.floor(rpm + 0.5)),
    tostring(math.floor(flight + 0.5)),
    tostring(math.floor(total + 0.5)),
    tostring(math.floor(voltage * 10 + 0.5)),
    tostring(bb_used),
    tostring(bb_total),
    tostring(math.floor(cells + 0.5)),
    tostring(math.floor(armFlags + 0.5))
  }
  if boxSources and state then
    for i = 1, #boxSources do
      local source = boxSources[i]
      local v = nil
      -- Zuerst im State suchen (wird in readTelemetry aktualisiert)
      if source == "esc_temp" then v = state.escTemp
      elseif source == "mcu_temp" then v = state.mcuTemp
      elseif source == "pid_profile" then v = state.profile
      elseif source == "rate_profile" then v = state.rateProfile
      elseif source == "battery_profile" then v = state.batteryProfile
      elseif source == "governor" then
        v = tostring(state.governor or "x") .. ":" .. tostring(state.armDisableFlags or "x")
      else
        -- Fallback auf Sensors, aber gedrosselt oder nur wenn absolut nötig
        -- In der Regel sollten alle wichtigen Dashboard-Quellen im State sein
        v = state[source]
      end
      if type(v) == "number" then
        parts[#parts + 1] = tostring(math.floor(v * 10 + 0.5))
      elseif type(v) == "string" then
        parts[#parts + 1] = v
      else
        parts[#parts + 1] = "x"
      end
    end
  end
  return table.concat(parts, "|")
end

return Engine