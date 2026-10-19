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
  timer1 = "<-999:59", timer2 = "<-999:59", timer3 = "<-999:59", tx_gps = "Fix · 99+",
  uptime = ">999:59", firmware = "WWWWWWWWWWWWWWWWWWWW",
}
local ELRS_WORST = {
  { "elrs_last_read", "Last read 99999+ s ago", nil },
  { "elrs_packet_rate", "Packet Rate", "1000Hz Full" },
  { "elrs_telemetry_ratio", "Telemetry Ratio", "1:128" },
  { "elrs_max_power", "Max Power", "25/250 mW" },
  { "elrs_dynamic", "Dynamic", "AUX12" },
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
local function layout(items, width, height, labels)
  local columns = width >= 700 and 4 or 2
  local compact = height < 400
  local gap, margin = compact and 6 or 10, compact and 10 or 16
  local colW = math.floor((width - margin * 2 - gap * (columns - 1)) / columns)
  local top, footer = compact and 82 or 112, 64
  local available = height - top - footer - gap
  local rows, used, y, rowHeight = {}, 0, top, 0
  local current = {}
  local metrics = {}
  local function finishRow()
    if #current == 0 then return true end
    rows[#rows + 1] = { items = current, y = y, h = rowHeight }
    y, used, rowHeight, current = y + rowHeight + gap, 0, 0, {}
    return y - gap - top <= available
  end
  for i = 1, #items do
    local item = items[i]
    if item.type == "elrs" and item.size == "small" then return nil, "size" end
    local span = math.min(units(item.size), columns)
    if used > 0 and used + span > columns and not finishRow() then return nil, "fit" end
    local boxW = span * colW + (span - 1) * gap
    local metricKey = item.type .. item.size .. boxW
    local metric = metrics[metricKey]
    if not metric then
      local label = labels and labels[item.type] or item.type
      local lw, lh = measure(label, SMLSIZE)
      local font = item.type == "elrs" and SMLSIZE
        or (item.type == "clock" and item.size ~= "small" and (compact and MIDSIZE or DBLSIZE))
        or MIDSIZE
      local vw, vh = measure(WORST[item.type] or "-", font)
      if item.type == "elrs" then
        local columnsPerLine = boxW >= 600 and 4 or 2
        local fieldWidth = math.floor((boxW - 16 - gap * (columnsPerLine - 1)) / columnsPerLine)
        for n = 1, #ELRS_WORST do
          local spec = ELRS_WORST[n]
          local line = labels and labels[spec[1]] or spec[2]
          line = spec[3] and (line .. ": " .. spec[3]) or string.gsub(line, "%%d", "99999+")
          local lineW = measure(line, font)
          if lineW > (n == 1 and boxW - 16 or fieldWidth) then return nil, "width" end
        end
      elseif vw > boxW - 16 then return nil, "width" end
      if lw > boxW - 16 then return nil, "width" end
      local _, detailHeight = measure("Ag", SMLSIZE)
      local verticalPadding = compact and 22 or 30
      metric = { font = font, lh = lh, vh = vh,
        needed = lh + vh * (item.type == "elrs" and (boxW >= 600 and 1 or 2) or 1)
          + detailHeight + verticalPadding }
      metrics[metricKey] = metric
    end
    rowHeight = math.max(rowHeight, metric.needed)
    current[#current + 1] = { item = item, x = margin + used * (colW + gap), w = boxW, font = metric.font,
      lineHeight = metric.vh, valueY = metric.lh + 13 }
    used = used + span
  end
  if not finishRow() then return nil, "fit" end
  if y - gap - top > available then return nil, "fit" end
  return rows
end

function M.validate(items, width, height, labels)
  if type(items) ~= "table" or #items == 0 then return false, "empty" end
  if #items > M.MAX_ITEMS then return false, "count" end
  local rows, err = layout(items, width, height, labels)
  return rows ~= nil, err, rows
end

local function valuesFit(items, values, width, height, labels, rows)
  rows = rows or layout(items, width, height, labels)
  if not rows then return false end
  for r = 1, #rows do
    for i = 1, #rows[r].items do
      local box = rows[r].items[i]
      if box.item.type == "elrs" then
        local fieldColumns = box.w >= 600 and 4 or 2
        local gap = height < 400 and 6 or 10
        local fieldW = math.floor((box.w - 16 - gap * (fieldColumns - 1)) / fieldColumns)
        local lines = values._elrsLines or {}
        for n = 1, #lines do
          local lineW = measure(lines[n], box.font)
          if lineW > (n == 1 and box.w - 16 or fieldW) then return false end
        end
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
  local dt = safeCall(getDateTime)
  local info = model and safeCall(model.getInfo) or nil
  local wantsGps, wantsBattery = false, false
  for i = 1, #(items or {}) do
    local itemType = items[i].type
    if itemType == "tx_gps" then wantsGps = true elseif itemType == "tx_battery" then wantsBattery = true end
  end
  local gps = wantsGps and safeCall(getTxGPS) or nil
  local version = nil
  if type(getVersion) == "function" then
    local ok, firmwareVersion = pcall(getVersion)
    if ok and type(firmwareVersion) == "string" and firmwareVersion ~= "" then version = firmwareVersion end
  end
  local now = type(getTime) == "function" and getTime() or 0
  local values = {
    clock = type(dt) == "table" and string.format("%02d:%02d", dt.hour or 0, dt.min or 0) or "-",
    date = type(dt) == "table" and string.format("%04d-%02d-%02d", dt.year or 0, dt.mon or 0, dt.day or 0) or "-",
    tx_battery = wantsBattery and battery(cache) or nil,
    model = bounded(type(info) == "table" and info.name or nil, 15),
    timer1 = timerValue(1), timer2 = timerValue(2), timer3 = timerValue(3),
    uptime = now > 359999999 and ">999:59"
      or string.format("%d:%02d", math.floor(now / 360000), math.floor(now / 6000) % 60),
    firmware = bounded(version, 20),
    elrs = M.elrsText(cache, type(getTime) == "function" and getTime() / 100 or 0),
  }
  if wantsGps and type(gps) == "table" then
    if gps.fix == true or gps.fix == 1 then
      local fix = cache.text and cache.text("gps_fix", "Fix") or "Fix"
      values.tx_gps = type(gps.numsat) == "number"
        and string.format("%s · %s", fix, gps.numsat > 99 and "99+" or tostring(math.max(0, math.floor(gps.numsat)))) or fix
    elseif gps.fix == false or gps.fix == 0 then
      values.tx_gps = cache.text and cache.text("gps_no_fix", "No fix") or "No fix"
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
  local hasElrs = false
  for i = 1, #items do
    local id = items[i].type
    if labels[id] == nil then labels[id] = i18n(TYPE_KEYS[id], id) end
    if id == "elrs" then hasElrs = true end
  end
  if hasElrs then
    for i = 1, #ELRS_WORST do labels[ELRS_WORST[i][1]] = i18n(ELRS_WORST[i][1], ELRS_WORST[i][2]) end
  end
  cache.zoneW, cache.zoneH, cache.labels = w, h, labels
  local valid, _, rows = M.validate(items, w, h, labels)
  cache.valueOverflow = valid and not valuesFit(items, values, w, h, labels, rows)
  local ok = valid and not cache.valueOverflow
  local compact = h < 400
  local logoW = compact and math.min(145, math.floor(w * 0.34)) or math.min(210, math.floor(w * 0.30))
  local logoH = math.floor(logoW * 84 / 400 + 0.5)
  local headerY = compact and 6 or 8
  local titleY = compact and 47 or 72
  local footerH = 64
  local footerY = h - footerH
  local headerDividerY = compact and 75 or 103
  local contentMargin = compact and 10 or 16
  local contentWidth = w - contentMargin * 2
  local infoX = compact and 18 or 24
  local infoWidth = w - (compact and 28 or 40)
  local children = {
    { type = "rectangle", x = 0, y = 0, w = w, h = h, color = COLOR_THEME_PRIMARY3, filled = true },
    { type = "image", x = contentMargin, y = headerY, w = logoW, h = logoH,
      file = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png" },
    { type = "label", x = contentMargin, y = titleY, w = contentWidth,
      text = i18n("screen_title", "Standby"), color = COLOR_THEME_PRIMARY2, font = MIDSIZE },
    { type = "rectangle", x = contentMargin, y = headerDividerY, w = contentWidth, h = 1,
      color = COLOR_THEME_SECONDARY1, filled = true },
    { type = "rectangle", x = 0, y = footerY, w = w, h = 23, color = COLOR_THEME_SECONDARY2, filled = true },
    { type = "rectangle", x = contentMargin, y = footerY + 5, w = 3, h = 13, filled = true,
      color = info and (info.level == "warning" or info.level == "error") and COLOR_THEME_WARNING
        or COLOR_THEME_SECONDARY1 },
    { type = "label", x = infoX, y = footerY + 3, w = infoWidth, h = 18,
      text = fitLine(info and info.text or "", infoWidth, SMLSIZE),
      color = COLOR_THEME_PRIMARY1, font = SMLSIZE },
    { type = "label", x = contentMargin, y = footerY + 27, w = contentWidth,
      h = footerH - 32, text = tostring(statusLine or ""),
      color = COLOR_THEME_PRIMARY2, font = SMLSIZE },
  }
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
      local fieldGap = compact and 6 or 10
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
      if item.type == "tx_battery" then
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
        detail = i18n("timer_detail", "EdgeTX model timer")
      elseif item.type == "tx_gps" then detail = i18n("tx_gps_detail", "Internal transmitter GPS")
      elseif item.type == "uptime" then detail = i18n("uptime_detail", "Since radio power-on")
      elseif item.type == "firmware" then detail = i18n("firmware_detail", "Radio firmware")
      elseif item.type == "date" then detail = i18n("date_detail", "Radio date") end
      local detailW = item.type == "tx_battery" and boxW - 57 or boxW - 16
      children[#children + 1] = { type = "label", x = x + 8, y = y + row.h - 21, w = detailW,
        text = item.type == "clock"
          and function() local snap = cache.snapshotValues or values; return tostring(snap.date or "-") end
          or detail,
        color = COLOR_THEME_PRIMARY1, font = SMLSIZE }
    end
    end
  end
  return children
end

return M
