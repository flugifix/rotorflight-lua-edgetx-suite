local M = {}
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
  return #tostring(text) * (font == MIDSIZE and 12 or 8), font == MIDSIZE and 24 or 18
end

local function layout(items, width, height, labels)
  local columns = width >= 700 and 4 or 2
  local gap, margin = 6, math.floor(width * 0.03)
  local colW = math.floor((width - margin * 2 - gap * (columns - 1)) / columns)
  local top = height >= 440 and 150 or 116
  local available = height - top - 8
  local rows, used, y, rowHeight = {}, 0, top, 0
  local current = {}
  local function finishRow()
    if #current == 0 then return true end
    rows[#rows + 1] = { items = current, y = y, h = rowHeight }
    y, used, rowHeight, current = y + rowHeight + gap, 0, 0, {}
    return y - gap - top <= available
  end
  for i = 1, #items do
    local item, span = items[i], math.min(units(items[i].size), columns)
    if used > 0 and used + span > columns and not finishRow() then return nil, "fit" end
    local boxW = span * colW + (span - 1) * gap
    local label = labels and labels[item.type] or item.type
    local lw, lh = measure(label, SMLSIZE)
    local font = item.size == "small" and SMLSIZE or MIDSIZE
    local vw, vh = measure(WORST[item.type] or "-", font)
    local lines = item.type == "elrs" and 5 or 1
    if item.type == "elrs" then
      for n = 1, #ELRS_WORST do
        local spec = ELRS_WORST[n]
        local line = labels and labels[spec[1]] or spec[2]
        line = spec[3] and (line .. ": " .. spec[3]) or string.gsub(line, "%%d", "99999+")
        local lineW = measure(line, font)
        if lineW > boxW - 16 then return nil, "width" end
      end
    elseif vw > boxW - 16 then return nil, "width" end
    if lw > boxW - 16 then return nil, "width" end
    local needed = lh + vh * lines + 22
    rowHeight = math.max(rowHeight, needed)
    current[#current + 1] = { item = item, x = margin + used * (colW + gap), w = boxW, font = font,
      lineHeight = vh, valueY = lh + 11 }
    used = used + span
  end
  if not finishRow() then return nil, "fit" end
  if y - gap - top > available then return nil, "fit" end
  return rows
end

function M.validate(items, width, height, labels)
  if type(items) ~= "table" or #items == 0 then return false, "empty" end
  if #items > M.MAX_ITEMS then return false, "count" end
  for i = 1, #items do
    if items[i].type == "elrs" and items[i].size == "small" then return false, "size" end
  end
  local rows, err = layout(items, width, height, labels)
  return rows ~= nil, err, rows
end

local function valuesFit(items, values, width, height, labels, rows)
  rows = rows or layout(items, width, height, labels)
  if not rows then return false end
  for r = 1, #rows do
    for i = 1, #rows[r].items do
      local box = rows[r].items[i]
      local value = tostring(values[box.item.type] or "-")
      for line in string.gmatch(value .. "\n", "([^\n]*)\n") do
        local lineW = measure(line, box.font)
        if lineW > box.w - 16 then return false end
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
  if not volts or not pct then return "-" end
  return string.format("%.1f V  %d%%", volts, pct)
end

local function readValues(cache)
  local dt = safeCall(getDateTime)
  local info = model and safeCall(model.getInfo) or nil
  local gps = safeCall(getTxGPS)
  local version = nil
  if type(getVersion) == "function" then
    local ok, firmwareVersion = pcall(getVersion)
    if ok and type(firmwareVersion) == "string" and firmwareVersion ~= "" then version = firmwareVersion end
  end
  local now = type(getTime) == "function" and getTime() or 0
  local values = {
    clock = type(dt) == "table" and string.format("%02d:%02d", dt.hour or 0, dt.min or 0) or "-",
    date = type(dt) == "table" and string.format("%04d-%02d-%02d", dt.year or 0, dt.mon or 0, dt.day or 0) or "-",
    tx_battery = battery(cache),
    model = bounded(type(info) == "table" and info.name or nil, 15),
    timer1 = timerValue(1), timer2 = timerValue(2), timer3 = timerValue(3),
    uptime = now > 359999999 and ">999:59"
      or string.format("%d:%02d", math.floor(now / 360000), math.floor(now / 6000) % 60),
    firmware = bounded(version, 20),
    elrs = M.elrsText(cache, type(getTime) == "function" and getTime() / 100 or 0),
  }
  if type(gps) == "table" then
    if gps.fix == true or gps.fix == 1 then
      local fix = cache.text and cache.text("gps_fix", "Fix") or "Fix"
      values.tx_gps = type(gps.numsat) == "number"
        and string.format("%s · %s", fix, gps.numsat > 99 and "99+" or tostring(math.max(0, math.floor(gps.numsat)))) or fix
    elseif gps.fix == false or gps.fix == 0 then
      values.tx_gps = cache.text and cache.text("gps_no_fix", "No fix") or "No fix"
    else
      values.tx_gps = "-"
    end
  else
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
  cache = cache or M._testCache or {}; M._testCache = cache
  local now = type(getTime) == "function" and getTime() or 0
  if cache.snapshotValues and now < (cache.snapshotAt or 0) + 100 then return cache.snapshotValues, cache.snapshotKey end
  local values = readValues(cache)
  if cache.zoneW and cache.zoneH and cache.labels then
    cache.valueOverflow = not valuesFit(items, values, cache.zoneW, cache.zoneH, cache.labels)
  end
  local key = {}
  for i = 1, #items do key[#key + 1] = items[i].type .. "=" .. tostring(values[items[i].type]) end
  cache.snapshotValues, cache.snapshotKey, cache.snapshotAt = values, table.concat(key, "|"), now
  return cache.snapshotValues, cache.snapshotKey
end

function M.build(zone, statusLine, i18n, items, values, cache)
  cache = cache or M._testCache or {}; M._testCache = cache
  cache.text = i18n
  local w, h = zone.w or LCD_W, zone.h or LCD_H
  local labels = {}
  for i = 1, #M.TYPES do local id = M.TYPES[i]; labels[id] = i18n(TYPE_KEYS[id], id) end
  for i = 1, #ELRS_WORST do labels[ELRS_WORST[i][1]] = i18n(ELRS_WORST[i][1], ELRS_WORST[i][2]) end
  cache.zoneW, cache.zoneH, cache.labels = w, h, labels
  local valid, _, rows = M.validate(items, w, h, labels)
  cache.valueOverflow = valid and not valuesFit(items, values, w, h, labels, rows)
  local ok = valid and not cache.valueOverflow
  local logoW = math.floor(w * 0.32)
  local logoH = math.floor(logoW * 84 / 400 + 0.5)
  local toolSize = h > 350 and 44 or 20
  local toolMargin = h > 350 and 8 or 1
  local statusX = math.floor(w * 0.39)
  local statusRight = w - toolSize - toolMargin - 6
  local children = {
    { type = "rectangle", x = 0, y = 0, w = w, h = h, color = COLOR_THEME_PRIMARY3, filled = true },
    { type = "image", x = math.floor(w * 0.04), y = math.floor(h * 0.04), w = logoW, h = logoH, file = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png" },
    { type = "label", x = statusX, y = math.floor(h * 0.055), w = math.max(0, statusRight - statusX),
      h = math.max(20, (h >= 440 and 150 or 116) - math.floor(h * 0.055) - 8),
      text = tostring(statusLine or ""), align = RIGHT, color = COLOR_THEME_PRIMARY2, font = SMLSIZE },
  }
  if not ok then
    children[#children + 1] = { type = "label", x = 10, y = math.floor(h * 0.48), w = w - 20, text = i18n("layout_invalid", "Standby layout does not fit"), align = CENTER, color = COLOR_THEME_WARNING, font = MIDSIZE }
    return children
  end
  for r = 1, #rows do
    local row = rows[r]
    for i = 1, #row.items do
    local box = row.items[i]
    local item = copy(box.item)
    local x, y, boxW = box.x, row.y, box.w
    local label = labels[item.type]
    children[#children + 1] = { type = "rectangle", x = x, y = y, w = boxW, h = row.h, color = COLOR_THEME_SECONDARY2, filled = true, radius = 5 }
    children[#children + 1] = { type = "label", x = x + 8, y = y + 5, w = boxW - 16, text = label, color = COLOR_THEME_PRIMARY2, font = SMLSIZE }
    children[#children + 1] = { type = "label", x = x + 8, y = y + box.valueY, w = boxW - 16,
      text = function() local snap = cache.snapshotValues or values; return tostring(snap[item.type] or "-") end,
      color = function() return item.type == "tx_battery" and cache.batteryLow and COLOR_THEME_WARNING or COLOR_THEME_PRIMARY1 end,
      font = box.font }
    end
  end
  return children
end

return M
