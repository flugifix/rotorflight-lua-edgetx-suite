local M = {}
local function load(path) return assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. path, "t"))() end
local Common, Controls, Standby, t
local NONE = ""
local NOTE_LINE_H = 24
local ui = { loaded = false, dirty = false, enabled = false, items = {}, runtime = nil }
local function deps()
  Common = Common or load("app/pages/settings/common.lua")
  Controls = Controls or load("ui/controls.lua")
  Standby = Standby or load("widgets/dashboard/standby.lua")
  ui.runtime = ui.runtime or Common.createFormRuntime(ui)
  t = t or Common.pageT("settings_dashboard_standby")
end
local function fromPrefs(prefs)
  local dashboard = type(prefs.dashboard) == "table" and prefs.dashboard or {}
  ui.enabled = dashboard[Standby.KEY_ENABLED] == true
  ui.items = Standby.decode(dashboard[Standby.KEY_LAYOUT])
  while #ui.items < Standby.MAX_ITEMS do ui.items[#ui.items + 1] = { type = NONE, size = "small" } end
end
local function ensure(prefs) if not ui.loaded then fromPrefs(prefs); ui.loaded = true end end
local function typeLabel(i18n, id)
  if id == "clock" then return t(i18n, "module_clock", "Clock") end
  if id == "date" then return t(i18n, "module_date", "Date") end
  if id == "tx_battery" then return t(i18n, "module_tx_battery", "TX battery") end
  if id == "model" then return t(i18n, "module_model", "Selected model") end
  if id == "timer1" then return t(i18n, "module_timer1", "Timer 1") end
  if id == "timer2" then return t(i18n, "module_timer2", "Timer 2") end
  if id == "timer3" then return t(i18n, "module_timer3", "Timer 3") end
  if id == "tx_gps" then return t(i18n, "module_tx_gps", "TX GPS") end
  if id == "uptime" then return t(i18n, "module_uptime", "Radio uptime") end
  if id == "firmware" then return t(i18n, "module_firmware", "Firmware") end
  if id == "elrs" then return t(i18n, "module_elrs", "ELRS TX configuration") end
  return id
end
local function typeOptions(i18n)
  local out = { { value = NONE, label = t(i18n, "module_none", "-") } }
  for i = 1, #Standby.TYPES do local id = Standby.TYPES[i]; out[#out + 1] = { value = id, label = typeLabel(i18n, id) } end
  return out
end
local function sizeOptions(i18n)
  return { { value = "small", label = t(i18n, "size_small", "Small") }, { value = "wide", label = t(i18n, "size_wide", "Wide") }, { value = "full", label = t(i18n, "size_full", "Full row") } }
end
local function fitLabels(i18n, typeChoices)
  local labels = {}
  if typeChoices then
    for i = 2, #typeChoices do labels[typeChoices[i].value] = typeChoices[i].label end
  else
    for i = 1, #Standby.TYPES do local id = Standby.TYPES[i]; labels[id] = typeLabel(i18n, id) end
  end
  labels.elrs_last_read = t(i18n, "elrs_last_read", "Last read %d s ago")
  labels.elrs_packet_rate = t(i18n, "elrs_packet_rate", "Packet Rate")
  labels.elrs_telemetry_ratio = t(i18n, "elrs_telemetry_ratio", "Telemetry Ratio")
  labels.elrs_max_power = t(i18n, "elrs_max_power", "Max Power")
  labels.elrs_dynamic = t(i18n, "elrs_dynamic", "Dynamic")
  labels.gps_latitude = t(i18n, "gps_latitude", "Latitude")
  labels.gps_longitude = t(i18n, "gps_longitude", "Longitude")
  labels.gps_altitude = t(i18n, "gps_altitude", "Altitude")
  labels.gps_speed = t(i18n, "gps_speed", "Speed")
  labels.gps_course = t(i18n, "gps_course", "Course")
  labels.gps_hdop = t(i18n, "gps_hdop", "HDOP")
  labels.gps_satellites = t(i18n, "gps_satellites", "Sat")
  labels.gps_time_unavailable = t(i18n, "gps_time_unavailable", "Time status unknown")
  return labels
end
local function selectedItems()
  local items, slots = {}, {}
  for i = 1, Standby.MAX_ITEMS do
    if ui.items[i].type ~= NONE then
      items[#items + 1] = ui.items[i]
      slots[#slots + 1] = i
    end
  end
  return items, slots
end
local function fitMessage(i18n, reason, offendingIndex, items, slots, labels)
  if reason == "empty" then return t(i18n, "fit_empty", "Add at least one item before saving.") end
  local item = offendingIndex and items[offendingIndex] or nil
  local slot = offendingIndex and slots[offendingIndex] or nil
  if item and slot then
    local label = labels[item.type] or typeLabel(i18n, item.type)
    if reason == "size" then
      return string.format(t(i18n, "fit_item_size", "Position %d (%s): choose Wide or Full row."), slot, label)
    elseif reason == "width" then
      return string.format(t(i18n, "fit_item_width", "Position %d (%s): choose a wider size or remove this tile."), slot, label)
    elseif reason == "fit" then
      return string.format(t(i18n, "fit_item_height", "Position %d (%s): this row no longer fits. Remove a tile or choose smaller sizes."), slot, label)
    end
  end
  return t(i18n, "invalid_message", "Every selected item must fit readably on one screen.")
end
local function appendFitNote(children, x, y, w, text, color)
  children[#children + 1] = { type = "label", x = x, y = y, w = w, text = text, color = color, font = SMLSIZE }
  if type(Controls.estimateWrappedTextHeight) == "function" then
    local height = Controls.estimateWrappedTextHeight(text, w, SMLSIZE)
    if type(height) == "number" and height > NOTE_LINE_H then return height end
  end
  return NOTE_LINE_H
end
local function button(children, x, y, w, text, press)
  children[#children + 1] = { type = "button", x = x, y = y, w = w, h = 36, text = text, press = press }
end
function M.getHeaderActions() deps(); return { save = true, help = true } end
function M.onReload(ctx) deps(); fromPrefs(ctx.preferences); ui.dirty = false end
function M.onSave(ctx)
  deps()
  local items, slots = selectedItems()
  local labels = fitLabels(ctx.i18n)
  local valid, reason, _, offendingIndex = Standby.validate(items, LCD_W or 480, LCD_H or 320, labels)
  if ui.enabled and not valid then
    ctx.reportSave({ title = t(ctx.i18n, "invalid_title", "Layout not saved"), message = fitMessage(ctx.i18n, reason, offendingIndex, items, slots, labels) }); return
  end
  local encodedLayout = valid and Standby.encode(items) or nil
  ctx.preferences.dashboard = ctx.preferences.dashboard or {}
  local previousEnabled = ctx.preferences.dashboard[Standby.KEY_ENABLED]
  local previousLayout = ctx.preferences.dashboard[Standby.KEY_LAYOUT]
  ctx.preferences.dashboard[Standby.KEY_ENABLED] = ui.enabled
  if encodedLayout ~= nil then ctx.preferences.dashboard[Standby.KEY_LAYOUT] = encodedLayout end
  local ok, err = ctx.savePreferences()
  if ok then ui.dirty = false; ctx.reportSave({ ok = true, title = t(ctx.i18n, "saved_title", "Saved"), message = t(ctx.i18n, "saved_message", "Standby screen saved") })
  else
    ctx.preferences.dashboard[Standby.KEY_ENABLED] = previousEnabled
    ctx.preferences.dashboard[Standby.KEY_LAYOUT] = previousLayout
    ctx.reportSave({ title = t(ctx.i18n, "save_error_title", "Error"), message = t(ctx.i18n, "save_error_message", "Save failed") .. ": " .. Common.saveFailureReason(ctx.i18n, err) })
  end
end
function M.build(ctx)
  deps(); ensure(ctx.preferences); ui.runtime.setRequestRebuild(ctx.requestRebuild)
  local children, x, w, i18n, y = ctx.children, ctx.x, ctx.w, ctx.i18n, ctx.y
  y = y + Controls.appendRadioSwitch(children, x, y, w, t(i18n, "enabled", "Standby screen"), ui.enabled,
    function(value) ui.enabled = value == true; ui.dirty = true; ctx.requestRebuild() end)
  local types, sizes, fmt = typeOptions(i18n), sizeOptions(i18n), t(i18n, "position", "Position %d")
  local selected, slots = selectedItems()
  local labels = fitLabels(i18n, types)
  local valid, reason, _, offendingIndex = Standby.validate(selected, LCD_W or 480, LCD_H or 320, labels)
  local offendingSlot = offendingIndex and slots[offendingIndex] or nil
  local fitText = valid and t(i18n, "fit_ok", "Fits this screen") or fitMessage(i18n, reason, offendingIndex, selected, slots, labels)
  for i = 1, Standby.MAX_ITEMS do
    y = y + Controls.appendComboSelect(children, x, y, w, string.format(fmt, i), types, ui.items[i].type,
      function(value)
        ui.items[i].type = value
        if value == "elrs" and ui.items[i].size == "small" then ui.items[i].size = "wide" end
        ui.dirty = true
        ctx.requestRebuild()
      end)
    if ui.items[i].type ~= NONE then
      y = y + Controls.appendComboSelect(children, x, y, w, t(i18n, "size", "Size"), sizes, ui.items[i].size, function(value) ui.items[i].size = value; ui.dirty = true; ctx.requestRebuild() end)
      local bw = math.floor((w - 12) / 3)
      if i > 1 then button(children, x, y, bw, t(i18n, "move_up", "Move up"), function() ui.items[i - 1], ui.items[i] = ui.items[i], ui.items[i - 1]; ui.dirty = true; ctx.requestRebuild() end) end
      if i < Standby.MAX_ITEMS and ui.items[i + 1].type ~= NONE then button(children, x + bw + 6, y, bw, t(i18n, "move_down", "Move down"), function() ui.items[i + 1], ui.items[i] = ui.items[i], ui.items[i + 1]; ui.dirty = true; ctx.requestRebuild() end) end
      button(children, x + (bw + 6) * 2, y, bw, t(i18n, "remove", "Remove"), function() table.remove(ui.items, i); ui.items[#ui.items + 1] = { type = NONE, size = "small" }; ui.dirty = true; ctx.requestRebuild() end)
      y = y + 42
      if i == offendingSlot then y = y + appendFitNote(children, x, y, w, fitText, COLOR_THEME_WARNING) end
    end
  end
  if valid or offendingSlot == nil then appendFitNote(children, x, y, w, fitText, valid and COLOR_THEME_PRIMARY1 or COLOR_THEME_WARNING) end
end
function M.onClose() Common.resetPageState(ui); Common, Controls, Standby, t = nil, nil, nil, nil end
function M.hasUnsavedChanges() return ui.dirty == true end
return M
