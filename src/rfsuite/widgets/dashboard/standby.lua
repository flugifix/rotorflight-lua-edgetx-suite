local M = {}
local MODULE_PATH = "widgets/dashboard/standby.lua"
local consumers = {}

function M.acquire(owner)
  if owner ~= nil then consumers[owner] = true end
end

function M.release(owner)
  if owner ~= nil then consumers[owner] = nil end
  if next(consumers) == nil and type(_G) == "table" and type(_G.rfsuite) == "table"
      and type(_G.rfsuite.clearModule) == "function" then
    _G.rfsuite.clearModule(MODULE_PATH)
  end
end

function M.consumerCount()
  local count = 0
  for _ in pairs(consumers) do count = count + 1 end
  return count
end
local function loadRadioStatus()
  if _G.rfsuite and type(_G.rfsuite.require) == "function" then return _G.rfsuite.require("lib/radio_status.lua") end
  if type(loadScript) ~= "function" then return nil end
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/radio_status.lua", "t")
  return chunk and chunk() or nil
end
local RadioStatus = loadRadioStatus()

M.KEY_ENABLED = "standby_enabled"
M.KEY_LAYOUT = "standby_layout"
M.MAX_ITEMS = 8

M.TYPES = { "clock", "date", "tx_battery", "model", "timer1", "timer2", "timer3", "tx_gps", "uptime", "firmware", "elrs" }
M.SIZES = { "small", "wide", "full" }
local TYPE_KEYS = {
  clock = "module_clock", date = "module_date", tx_battery = "module_tx_battery", model = "module_model",
  timer1 = "module_timer1", timer2 = "module_timer2", timer3 = "module_timer3", tx_gps = "module_tx_gps",
  uptime = "module_uptime", firmware = "module_firmware", elrs = "module_elrs",
}

local DEFAULT = "clock:small,tx_battery:small,model:full"
local TYPE_SET, SIZE_SET = {}, { small = true, wide = true, full = true }
for i = 1, #M.TYPES do TYPE_SET[M.TYPES[i]] = true end

local function copy(item) return { type = item.type, size = item.size } end

function M.decode(value)
  if value == nil then value = DEFAULT end
  if value == "-" then return {} end
  if type(value) ~= "string" or value == "" then return {}, "malformed" end
  if string.sub(value, 1, 1) == "," or string.sub(value, -1) == "," or string.find(value, ",,", 1, true) then
    return {}, "malformed"
  end
  local out = {}
  local count = 0
  for token in string.gmatch(value, "[^,]+") do
    count = count + 1
    local kind, size = string.match(token, "^([%w_]+):([%w_]+)$")
    if not TYPE_SET[kind] or not SIZE_SET[size] then return {}, "unknown" end
    if count > M.MAX_ITEMS then return {}, "count" end
    if kind == "elrs" and size == "small" then return {}, "size" end
    out[#out + 1] = { type = kind, size = size }
  end
  if #out == 0 then return {}, "malformed" end
  return out, nil
end

function M.encode(items)
  local out = {}
  for i = 1, math.min(#items, M.MAX_ITEMS) do
    local item = items[i]
    if TYPE_SET[item.type] and SIZE_SET[item.size] then out[#out + 1] = item.type .. ":" .. item.size end
  end
  if #out == 0 then return "-" end
  return table.concat(out, ",")
end

local function units(size)
  if size == "small" then return 1 end
  if size == "wide" then return 2 end
  return 4
end

local WORST = {
  clock = "23:59", date = "2099-12-31", tx_battery = "12.0 V  100%", model = "WWWWWWWWWWWWWWW",
  timer1 = "<-999:59", timer2 = "<-999:59", timer3 = "<-999:59", tx_gps = "No fix · Sat 99+",
  uptime = ">999:59", firmware = "WWWWWWWWWWWWWWWWWWWW",
}
local ELRS_WORST = {
  { "elrs_last_read", "Last read 99999+ s ago", nil },
  { "elrs_packet_rate", "Packet Rate", "1000Hz Full" },
  { "elrs_telemetry_ratio", "Telemetry Ratio", "1:128" },
  { "elrs_max_power", "Max Power", "25/250 mW" },
  { "elrs_dynamic", "Dynamic", "AUX12" },
}
local GPS_WORST = {
  { "gps_latitude", "Latitude", "-180.00000°" },
  { "gps_longitude", "Longitude", "-180.00000°" },
  { "gps_altitude", "Altitude", "-99999.9 m" },
  { "gps_speed", "Speed", "9999.9 m/s" },
  { "gps_course", "Course", "359.9°" },
  { "gps_hdop", "HDOP", "655.35" },
}

local function measure(text, font)
  if lcd and type(lcd.sizeText) == "function" then
    local ok, w, h = pcall(lcd.sizeText, tostring(text), font)
    if ok and type(w) == "number" and type(h) == "number" then return w, h end
  end
  if font == DBLSIZE then return #tostring(text) * 20, 38 end
  return #tostring(text) * (font == MIDSIZE and 12 or 8), font == MIDSIZE and 24 or 18
end

local function fitLine(text, width, font)
  text = tostring(text or "")
  local byteLimit = 192
  if #text <= byteLimit and measure(text, font) <= width then return text end
  local positions, i = {}, 1
  while i <= #text and i <= byteLimit do
    positions[#positions + 1] = i
    local byte = string.byte(text, i)
    i = i + (byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4)
  end
  local low, high, best = 1, #positions, 0
  while low <= high do
    local middle = math.floor((low + high) / 2)
    local candidate = string.sub(text, 1, positions[middle] - 1) .. "..."
    if measure(candidate, font) <= width then
      best, low = middle, middle + 1
    else
      high = middle - 1
    end
  end
  if best > 0 then return string.sub(text, 1, positions[best] - 1) .. "..." end
  return "..."
end
local function frameGeometry(height)
  local compact = height < 400
  if height < 160 then return true, 0, 24, nil, true, true end
  local short = height < 300
  return compact, short and 34 or compact and 49 or 68,
    short and 52 or 64, short and 28 or compact and 43 or 60, short, false
end
local function layout(items, width, height, labels)
  local columns = width >= 700 and 4 or width >= 360 and 2 or 1
  local compact, top, footer, _, _, micro = frameGeometry(height)
  local gap = micro and 4 or compact and 6 or 10
  local margin = width < 360 and 6 or compact and 10 or 16
  local colW = math.floor((width - margin * 2 - gap * (columns - 1)) / columns)
  local available = height - top - footer - gap
  local rows, used, y, rowHeight, rowStart = {}, 0, top, 0, 1
  local current = {}
  local metrics = {}
  local function finishRow()
    if #current == 0 then return true end
    rows[#rows + 1] = { items = current, y = y, h = rowHeight }
    y, used, rowHeight, current = y + rowHeight + gap, 0, 0, {}
    return y - gap - top <= available, rowStart
  end
  for i = 1, #items do
    local item = items[i]
    if item.type == "elrs" and item.size == "small" then return nil, "size", i end
    local span = math.min(units(item.size), columns)
    if used > 0 and used + span > columns then
      local fits, offending = finishRow()
      if not fits then return nil, "fit", offending end
    end
    if #current == 0 then rowStart = i end
    local boxW = span * colW + (span - 1) * gap
    local metricKey = item.type .. item.size .. boxW
    local metric = metrics[metricKey]
    if not metric then
      local label = labels and labels[item.type] or item.type
      local lw, lh = measure(label, SMLSIZE)
      local font = item.type == "elrs" and SMLSIZE
        or (item.type == "clock" and item.size ~= "small" and (compact and MIDSIZE or DBLSIZE))
        or MIDSIZE
      local worstValue = WORST[item.type] or "-"
      if item.type == "tx_gps" then
        worstValue = string.format("%s · %s 99+",
          labels and labels.gps_no_fix or "No fix",
          labels and labels.gps_satellites or "Sat")
      end
      local vw, vh = measure(worstValue, font)
      if item.type == "elrs" then
        local columnsPerLine = boxW >= 600 and 4 or 2
        local fieldWidth = math.floor((boxW - 16 - gap * (columnsPerLine - 1)) / columnsPerLine)
        for n = 1, #ELRS_WORST do
          local spec = ELRS_WORST[n]
          local line = labels and labels[spec[1]] or spec[2]
          line = spec[3] and (line .. ": " .. spec[3]) or string.gsub(line, "%%d", "99999+")
          local lineW = measure(line, font)
          if lineW > (n == 1 and boxW - 16 or fieldWidth) then return nil, "width", i end
        end
      elseif item.type == "tx_gps" and item.size ~= "small" then
        if vw > boxW - 16 then return nil, "width", i end
        local fieldColumns = boxW >= 600 and 3 or 2
        local fieldWidth = math.floor((boxW - 16 - gap * (fieldColumns - 1)) / fieldColumns)
        for n = 1, #GPS_WORST do
          local spec = GPS_WORST[n]
          local line = (labels and labels[spec[1]] or spec[2]) .. ": " .. spec[3]
          if measure(line, SMLSIZE) > fieldWidth then return nil, "width", i end
        end
        local timeLine = labels and labels.gps_time_unavailable or "Time status unknown"
        if measure(timeLine, SMLSIZE) > boxW - 16 then return nil, "width", i end
      elseif item.type == "tx_gps" then
        if vw > boxW - 16 then return nil, "width", i end
        local timeLine = labels and labels.gps_time_unavailable or "Time status unknown"
        if measure(timeLine, SMLSIZE) > boxW - 16 then return nil, "width", i end
      elseif vw > boxW - 16 then return nil, "width", i end
      if lw > boxW - 16 then return nil, "width", i end
      local _, detailHeight = measure("Ag", SMLSIZE)
      local verticalPadding = micro and 22 or compact and 22 or 30
      local valueLines = item.type == "elrs" and (boxW >= 600 and 1 or 2) or 1
      local detailLines = item.type == "tx_gps" and item.size ~= "small"
        and (boxW >= 600 and 3 or 4) or 1
      metric = { font = font, lh = lh, vh = vh, detailHeight = detailHeight,
        needed = lh + vh * valueLines + detailHeight * detailLines + verticalPadding
          + (detailLines > 1 and 4 or 0) }
      metrics[metricKey] = metric
    end
    rowHeight = math.max(rowHeight, metric.needed)
    current[#current + 1] = { item = item, x = margin + used * (colW + gap), w = boxW, font = metric.font,
      lineHeight = metric.vh, detailHeight = metric.detailHeight, valueY = metric.lh + 13 }
    used = used + span
  end
  local fits, offending = finishRow()
  if not fits then return nil, "fit", offending end
  if y - gap - top > available then return nil, "fit", rowStart end
  return rows
end

function M.validate(items, width, height, labels)
  if type(items) ~= "table" or #items == 0 then return false, "empty" end
  if #items > M.MAX_ITEMS then return false, "count" end
  if width < 200 or height < 45 then return false, "fit", nil, 1 end
  local rows, err, offending = layout(items, width, height, labels)
  return rows ~= nil, err, rows, offending
end

local function valuesFit(items, values, width, height, labels, rows)
  rows = rows or layout(items, width, height, labels)
  if not rows then return false end
  for r = 1, #rows do
    for i = 1, #rows[r].items do
      local box = rows[r].items[i]
      if box.item.type == "elrs" then
        local fieldColumns = box.w >= 600 and 4 or 2
        local _, _, _, _, _, micro = frameGeometry(height)
        local gap = micro and 4 or height < 400 and 6 or 10
        local fieldW = math.floor((box.w - 16 - gap * (fieldColumns - 1)) / fieldColumns)
        local lines = values._elrsLines or {}
        for n = 1, #lines do
          local lineW = measure(lines[n], box.font)
          if lineW > (n == 1 and box.w - 16 or fieldW) then return false end
        end
      elseif box.item.type == "tx_gps" and box.item.size ~= "small" then
        local fieldColumns = box.w >= 600 and 3 or 2
        local _, _, _, _, _, micro = frameGeometry(height)
        local gap = micro and 4 or height < 400 and 6 or 10
        local fieldW = math.floor((box.w - 16 - gap * (fieldColumns - 1)) / fieldColumns)
        local lines = values._gpsLines or {}
        for n = 1, #GPS_WORST do
          if measure(lines[n] or "-", SMLSIZE) > fieldW then return false end
        end
        if measure(values._gpsTime or "Time status unknown", SMLSIZE) > box.w - 16 then return false end
      else
        local value = tostring(values[box.item.type] or "-")
        for line in string.gmatch(value .. "\n", "([^\n]*)\n") do
          local lineW = measure(line, box.font)
          if lineW > box.w - 16 then return false end
        end
      end
    end
  end
  return true
end

local function safeCall(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, ...)
  if ok then return value end
  return nil
end

local function timerValue(index)
  if not model or type(model.getTimer) ~= "function" then return nil end
  local value = safeCall(model.getTimer, index - 1)
  if type(value) == "table" then value = value.value end
  if type(value) ~= "number" then return nil end
  local sign = value < 0 and "-" or ""
  value = math.abs(math.floor(value))
  if value > 59999 then return sign == "-" and "<-999:59" or ">999:59" end
  return string.format("%s%d:%02d", sign, math.floor(value / 60), value % 60)
end

local function bounded(value, limit)
  if type(value) ~= "string" or value == "" then return "-" end
  local positions, i = {}, 1
  while i <= #value do
    positions[#positions + 1] = i
    local byte = string.byte(value, i)
    i = i + (byte < 0x80 and 1 or byte < 0xE0 and 2 or byte < 0xF0 and 3 or 4)
  end
  if #positions <= limit then return value end
  return string.sub(value, 1, positions[limit - 2] - 1) .. "..."
end

local function battery(cache)
  local volts, pct, low = nil, nil, false
  if RadioStatus then volts, pct, low = RadioStatus.txBattery() end
  cache.batteryLow = low
  cache.batteryPercent = pct
  if not volts or not pct then return "-" end
  return string.format("%.1f V  %d%%", volts, pct)
end

local function readValues(cache, items)
  local selected = {}
  local wantsGps, wantsGpsDetails = false, false
  for i = 1, #(items or {}) do
    local itemType = items[i].type
    selected[itemType] = true
    if itemType == "tx_gps" then
      wantsGps = true
      if items[i].size ~= "small" then wantsGpsDetails = true end
    end
  end
  local dt = (selected.clock or selected.date) and safeCall(getDateTime) or nil
  local info = selected.model and model and safeCall(model.getInfo) or nil
  local gps = wantsGps and safeCall(getTxGPS) or nil
  local version = nil
  if selected.firmware and type(getVersion) == "function" then
    local ok, firmwareVersion = pcall(getVersion)
    if ok and type(firmwareVersion) == "string" and firmwareVersion ~= "" then version = firmwareVersion end
  end
  local now = selected.uptime and type(getTime) == "function" and getTime() or 0
  local values = {
    clock = selected.clock and (type(dt) == "table"
      and string.format("%02d:%02d", dt.hour or 0, dt.min or 0) or "-") or nil,
    date = (selected.clock or selected.date) and (type(dt) == "table"
      and string.format("%04d-%02d-%02d", dt.year or 0, dt.mon or 0, dt.day or 0) or "-") or nil,
    tx_battery = selected.tx_battery and battery(cache) or nil,
    model = selected.model and bounded(type(info) == "table" and info.name or nil, 15) or nil,
    timer1 = selected.timer1 and timerValue(1) or nil,
    timer2 = selected.timer2 and timerValue(2) or nil,
    timer3 = selected.timer3 and timerValue(3) or nil,
    uptime = selected.uptime and (now > 359999999 and ">999:59"
      or string.format("%d:%02d", math.floor(now / 360000), math.floor(now / 6000) % 60)) or nil,
    firmware = selected.firmware and bounded(version, 20) or nil,
    elrs = selected.elrs and M.elrsText(cache, type(getTime) == "function" and getTime() / 100 or 0) or nil,
  }
  if wantsGps then
    values._gpsTime = cache.text and cache.text("gps_time_unavailable", "Time status unknown")
      or "Time status unknown"
  end
  if wantsGps and type(gps) == "table" then
    if gps.fix == true or gps.fix == 1 then
      local fix = cache.text and cache.text("gps_fix", "Fix") or "Fix"
      values.tx_gps = type(gps.numsat) == "number"
        and string.format("%s · %s", fix, gps.numsat > 99 and "99+" or tostring(math.max(0, math.floor(gps.numsat)))) or fix
      local function usable(value, minimum, maximum)
        return type(value) == "number" and value == value and value > -math.huge and value < math.huge
          and value >= minimum and value <= maximum
      end
      local function scaledGpsValue(key, format, unit, minimum, maximum)
        local value = gps[key]
        if not usable(value, minimum, maximum) then return "-" end
        return string.format(format, value / 10) .. unit
      end
      if wantsGpsDetails then
        local gpsValues = {
          usable(gps.lat, -90, 90) and string.format("%.5f°", gps.lat) or "-",
          usable(gps.lon, -180, 180) and string.format("%.5f°", gps.lon) or "-",
          scaledGpsValue("alt", "%.1f", " m", -999999, 999999),
          scaledGpsValue("speed", "%.1f", " m/s", 0, 99999),
          scaledGpsValue("heading", "%.1f", "°", 0, 3599),
          usable(gps.hdop, 0, 65535) and string.format("%.2f", gps.hdop / 100) or "-",
        }
        values._gpsLines = {}
        for i = 1, #GPS_WORST do
          local caption = cache.text and cache.text(GPS_WORST[i][1], GPS_WORST[i][2]) or GPS_WORST[i][2]
          values._gpsLines[i] = caption .. ": " .. gpsValues[i]
        end
      end
    elseif gps.fix == false or gps.fix == 0 then
      local noFix = cache.text and cache.text("gps_no_fix", "No fix") or "No fix"
      local sat = cache.text and cache.text("gps_satellites", "Sat") or "Sat"
      values.tx_gps = type(gps.numsat) == "number"
        and string.format("%s · %s %s", noFix, sat, gps.numsat > 99 and "99+"
          or tostring(math.max(0, math.floor(gps.numsat)))) or noFix
    else
      values.tx_gps = "-"
    end
  elseif wantsGps then
    values.tx_gps = "-"
  end
  return values
end

function M.setElrsSnapshot(cache, snapshot, now)
  local old = cache.elrs
  cache.elrs = snapshot
  cache.elrsNow = now
  if type(old) ~= "table" or type(snapshot) ~= "table" or old.status ~= snapshot.status or old.readAt ~= snapshot.readAt
      or old.identity ~= snapshot.identity or old.packetRate ~= snapshot.packetRate or old.telemetryRatio ~= snapshot.telemetryRatio
      or old.maxPower ~= snapshot.maxPower or old.dynamic ~= snapshot.dynamic then cache.snapshotAt = nil end
end

function M.elrsText(cache, now)
  local snap, text = cache.elrs, cache.text
  if type(snap) ~= "table" or snap.status == "unavailable" then return text and text("elrs_unavailable", "Unavailable") or "Unavailable" end
  if snap.status == "reading" then return text and text("elrs_reading", "Reading") or "Reading" end
  local age = math.max(0, math.floor((now or cache.elrsNow or 0) - (snap.readAt or now or 0)))
  local ageText = age > 99999 and "99999+" or tostring(age)
  local ageFormat = text and text("elrs_last_read", "Last read %s s ago") or "Last read %s s ago"
  ageFormat = string.gsub(ageFormat, "%%d", "%%s")
  local lines = { string.format(ageFormat, ageText) }
  local fields = {
    { "elrs_packet_rate", "Packet Rate", snap.packetRate },
    { "elrs_telemetry_ratio", "Telemetry Ratio", snap.telemetryRatio },
    { "elrs_max_power", "Max Power", snap.maxPower },
    { "elrs_dynamic", "Dynamic", snap.dynamic },
  }
  for i = 1, #fields do
    local row = fields[i]
    local value = tostring(row[3] or "-")
    if row[1] == "elrs_max_power" and snap.fields and snap.fields.maxPower and snap.fields.maxPower.unit
        and snap.fields.maxPower.unit ~= "" then value = value .. " " .. tostring(snap.fields.maxPower.unit) end
    lines[#lines + 1] = (text and text(row[1], row[2]) or row[2]) .. ": " .. value
  end
  return table.concat(lines, "\n")
end

function M.snapshot(items, cache)
  cache = cache or {}
  local now = type(getTime) == "function" and getTime() or 0
  if cache.snapshotValues and now < (cache.snapshotAt or 0) + 100 then return cache.snapshotValues, cache.snapshotKey end
  local values = readValues(cache, items)
  values._elrsLines = {}
  for line in string.gmatch(tostring(values.elrs or "-") .. "\n", "([^\n]*)\n") do
    values._elrsLines[#values._elrsLines + 1] = line
  end
  if cache.zoneW and cache.zoneH and cache.labels then
    cache.valueOverflow = not valuesFit(items, values, cache.zoneW, cache.zoneH, cache.labels)
  end
  local key = {}
  for i = 1, #items do key[#key + 1] = items[i].type .. "=" .. tostring(values[items[i].type]) end
  cache.snapshotValues, cache.snapshotKey, cache.snapshotAt = values, table.concat(key, "|"), now
  return cache.snapshotValues, cache.snapshotKey
end

function M.build(zone, statusLine, i18n, items, values, cache, info)
  cache = cache or {}
  cache.text = i18n
  local w, h = zone.w or LCD_W, zone.h or LCD_H
  local labels = {}
  local hasElrs, hasGps, hasGpsDetails = false, false, false
  for i = 1, #items do
    local id = items[i].type
    if labels[id] == nil then labels[id] = i18n(TYPE_KEYS[id], id) end
    if id == "elrs" then hasElrs = true end
    if id == "tx_gps" then
      hasGps = true
      if items[i].size ~= "small" then hasGpsDetails = true end
    end
  end
  if hasElrs then
    for i = 1, #ELRS_WORST do labels[ELRS_WORST[i][1]] = i18n(ELRS_WORST[i][1], ELRS_WORST[i][2]) end
  end
  if hasGpsDetails then
    for i = 1, #GPS_WORST do labels[GPS_WORST[i][1]] = i18n(GPS_WORST[i][1], GPS_WORST[i][2]) end
  end
  if hasGps then
    labels.gps_no_fix = i18n("gps_no_fix", "No fix")
    labels.gps_satellites = i18n("gps_satellites", "Sat")
    labels.gps_time_unavailable = i18n("gps_time_unavailable", "Time status unknown")
  end
  cache.zoneW, cache.zoneH, cache.labels = w, h, labels
  local valid, _, rows = M.validate(items, w, h, labels)
  cache.valueOverflow = valid and not valuesFit(items, values, w, h, labels, rows)
  local ok = valid and not cache.valueOverflow
  local compact, _, footerH, headerDividerY, short, micro = frameGeometry(h)
  local logoW = short and math.min(100, math.floor(w * 0.28))
    or compact and math.min(145, math.floor(w * 0.34)) or math.min(210, math.floor(w * 0.30))
  local logoH = math.floor(logoW * 84 / 400 + 0.5)
  local headerY = compact and 6 or 8
  local footerY = h - footerH
  local contentMargin = w < 360 and 6 or compact and 10 or 16
  local contentWidth = w - contentMargin * 2
  local infoX = contentMargin + 8
  local infoWidth = w - infoX - contentMargin
  if w < 200 or h < 90 then
    return {
      { type = "rectangle", x = 0, y = 0, w = w, h = h, color = COLOR_THEME_PRIMARY3, filled = true },
      { type = "label", x = 6, y = math.max(4, math.floor(h * 0.4)), w = math.max(1, w - 12),
        text = i18n("layout_invalid", "Standby layout does not fit"), align = CENTER,
        color = COLOR_THEME_WARNING, font = SMLSIZE },
    }
  end
  local stripH, markerY, infoY, statusY, statusH = 23, 5, 3, 27, footerH - 32
  if short then stripH, markerY, infoY, statusY, statusH = 19, 3, 1, 22, footerH - 26 end
  local children
  if micro then
    children = {
      { type = "rectangle", x = 0, y = 0, w = w, h = h, color = COLOR_THEME_PRIMARY3, filled = true },
      { type = "rectangle", x = 0, y = footerY, w = w, h = footerH,
        color = COLOR_THEME_SECONDARY2, filled = true },
      { type = "label", x = 4, y = footerY + 3, w = math.max(1, w - 8), h = footerH - 6,
        text = fitLine(info and info.text or statusLine or "", math.max(1, w - 8), SMLSIZE),
        color = COLOR_THEME_PRIMARY1, font = SMLSIZE },
    }
  else
    children = {
    { type = "rectangle", x = 0, y = 0, w = w, h = h, color = COLOR_THEME_PRIMARY3, filled = true },
    { type = "image", x = contentMargin, y = headerY, w = logoW, h = logoH,
      file = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png" },
    { type = "rectangle", x = contentMargin, y = headerDividerY, w = contentWidth, h = 1,
      color = COLOR_THEME_SECONDARY1, filled = true },
    { type = "rectangle", x = 0, y = footerY, w = w, h = stripH, color = COLOR_THEME_SECONDARY2, filled = true },
    { type = "rectangle", x = contentMargin, y = footerY + markerY, w = 3, h = 13, filled = true,
      color = info and (info.level == "warning" or info.level == "error") and COLOR_THEME_WARNING
        or COLOR_THEME_SECONDARY1 },
    { type = "label", x = infoX, y = footerY + infoY, w = infoWidth, h = 18,
      text = fitLine(info and info.text or "", infoWidth, SMLSIZE),
      color = COLOR_THEME_PRIMARY1, font = SMLSIZE },
    { type = "label", x = contentMargin, y = footerY + statusY, w = contentWidth,
      h = statusH, text = tostring(statusLine or ""),
      color = COLOR_THEME_PRIMARY2, font = SMLSIZE },
    }
  end
  if not ok then
    children[#children + 1] = { type = "label", x = 10, y = math.floor(h * 0.46), w = w - 20,
      text = i18n("layout_invalid", "Standby layout does not fit"), align = CENTER,
      color = COLOR_THEME_WARNING, font = MIDSIZE }
    return children
  end
  for r = 1, #rows do
    local row = rows[r]
    for i = 1, #row.items do
    local box = row.items[i]
    local item = box.item
    local x, y, boxW = box.x, row.y, box.w
    local label = labels[item.type]
    children[#children + 1] = { type = "rectangle", x = x, y = y, w = boxW, h = row.h,
      color = COLOR_THEME_SECONDARY2, filled = true, rounded = compact and 5 or 7 }
    children[#children + 1] = { type = "label", x = x + 8, y = y + 5, w = boxW - 16, text = label, color = COLOR_THEME_SECONDARY1, font = SMLSIZE }
    if item.type == "elrs" then
      local fieldColumns = boxW >= 600 and 4 or 2
      local fieldGap = micro and 4 or compact and 6 or 10
      local fieldW = math.floor((boxW - 16 - fieldGap * (fieldColumns - 1)) / fieldColumns)
      for field = 1, 4 do
        local column = (field - 1) % fieldColumns
        local line = math.floor((field - 1) / fieldColumns)
        children[#children + 1] = { type = "label", x = x + 8 + column * (fieldW + fieldGap),
          y = y + box.valueY + line * box.lineHeight, w = fieldW,
          text = function()
            local snap = cache.snapshotValues or values
            return snap._elrsLines and snap._elrsLines[field + 1] or "-"
          end,
          color = COLOR_THEME_PRIMARY1, font = box.font }
      end
      children[#children + 1] = { type = "label", x = x + 8, y = y + row.h - 21, w = boxW - 16,
        text = function()
          local snap = cache.snapshotValues or values
          return snap._elrsLines and snap._elrsLines[1] or "-"
        end,
        color = COLOR_THEME_PRIMARY1, font = SMLSIZE }
    else
      children[#children + 1] = { type = "label", x = x + 8, y = y + box.valueY, w = boxW - 16,
        text = function() local snap = cache.snapshotValues or values; return tostring(snap[item.type] or "-") end,
        color = item.type == "tx_battery"
          and function() return cache.batteryLow and COLOR_THEME_WARNING or COLOR_THEME_PRIMARY1 end
          or COLOR_THEME_PRIMARY1,
        font = box.font }
      local detail = ""
      if item.type == "tx_gps" and item.size ~= "small" then
        local fieldColumns = boxW >= 600 and 3 or 2
        local fieldGap = micro and 4 or compact and 6 or 10
        local fieldW = math.floor((boxW - 16 - fieldGap * (fieldColumns - 1)) / fieldColumns)
        local detailY = y + box.valueY + box.lineHeight + 4
        for field = 1, #GPS_WORST do
          local column = (field - 1) % fieldColumns
          local line = math.floor((field - 1) / fieldColumns)
          children[#children + 1] = { type = "label", x = x + 8 + column * (fieldW + fieldGap),
            y = detailY + line * box.detailHeight, w = fieldW,
            text = function()
              local snap = cache.snapshotValues or values
              return snap._gpsLines and snap._gpsLines[field] or ""
            end,
            color = COLOR_THEME_PRIMARY1, font = SMLSIZE }
        end
        children[#children + 1] = { type = "label", x = x + 8,
          y = detailY + math.ceil(#GPS_WORST / fieldColumns) * box.detailHeight,
          w = boxW - 16, text = values._gpsTime or labels.gps_time_unavailable,
          color = COLOR_THEME_PRIMARY1, font = SMLSIZE }
      elseif item.type == "tx_battery" then
        detail = i18n("tx_battery_detail", "Radio battery")
        local batteryW = compact and 30 or 36
        local batteryH = compact and 12 or 14
        local terminalW = 3
        local batteryX = x + boxW - 8 - batteryW - terminalW
        local batteryY = y + row.h - 20
        children[#children + 1] = { type = "rectangle", x = batteryX + batteryW,
          y = batteryY + 3, w = terminalW, h = batteryH - 6,
          color = COLOR_THEME_PRIMARY1, filled = true }
        children[#children + 1] = { type = "hline", x = batteryX + 2,
          y = batteryY + math.floor(batteryH / 2), w = 1, h = batteryH - 4,
          size = function()
            local pct = cache.batteryPercent or 0
            return math.max(0, math.floor((batteryW - 4) * pct / 100)), batteryH - 4
          end,
          color = function() return cache.batteryLow and COLOR_THEME_WARNING or COLOR_THEME_SECONDARY1 end }
        children[#children + 1] = { type = "rectangle", x = batteryX, y = batteryY,
          w = batteryW, h = batteryH, color = COLOR_THEME_PRIMARY1, filled = false,
          rounded = 2, thickness = 1 }
      elseif item.type == "model" then detail = i18n("model_detail", "EdgeTX model")
      elseif item.type == "timer1" or item.type == "timer2" or item.type == "timer3" then
        detail = i18n(item.type .. "_detail", "EdgeTX model timer")
      elseif item.type == "tx_gps" then
        detail = i18n("gps_time_unavailable", "Time status unknown")
      elseif item.type == "uptime" then detail = i18n("uptime_detail", "Since radio power-on")
      elseif item.type == "firmware" then detail = i18n("firmware_detail", "Radio firmware")
      elseif item.type == "date" then detail = i18n("date_detail", "Radio date") end
      local detailW = item.type == "tx_battery" and boxW - 57 or boxW - 16
      if not (item.type == "tx_gps" and item.size ~= "small") then
        children[#children + 1] = { type = "label", x = x + 8, y = y + row.h - 21, w = detailW,
          text = item.type == "clock"
            and function() local snap = cache.snapshotValues or values; return tostring(snap.date or "-") end
            or detail,
          color = COLOR_THEME_PRIMARY1, font = SMLSIZE }
      end
    end
    end
  end
  return children
end

return M
