local zone, options = ...

local w = {
  zone = zone,
  options = options,
  built = false,
  values = {
    state = "DISARMED",
    rpm = 0,
    profile = 1,
    rates = 1,
    flights = 0,
    lq = 0,
    fuel = 100,
    voltage = 0
  }
}

local LOGO_FILE = "/SCRIPTS/TOOLS/rfsuite-core/assets/icon.png"

local function readValue(name, fallback)
  if not getValue then return fallback end
  local ok, value = pcall(getValue, name)
  if not ok or value == nil then
    return fallback
  end
  return value
end

local function readTelemetry(widget)
  local v = widget.values
  v.rpm = readValue("RPM", v.rpm)
  v.lq = readValue("RQly", v.lq)

  local fuel = readValue("Fuel", v.fuel)
  if type(fuel) == "number" then
    if fuel < 0 then fuel = 0 end
    if fuel > 100 then fuel = 100 end
    v.fuel = fuel
  end

  local voltage = readValue("VFAS", v.voltage)
  if type(voltage) == "number" then
    v.voltage = voltage
  end

  local armState = readValue("ARM", 0)
  if type(armState) == "number" and bit32 then
    v.state = bit32.btest(armState, 1) and "ARMED" or "DISARMED"
  end
end

local function metricTextLeft()
  return string.format("%d%%", math.floor(w.values.fuel + 0.5))
end

local function metricTextRight()
  return string.format("%.1fV", w.values.voltage)
end

local function buildWidget(widget)
  if lvgl == nil then return end

  local z = widget.zone
  local cardGap = 6
  local topPad = 4
  local headerH = 28
  local bottomH = 40
  local metricY = z.y + headerH + topPad
  local metricH = math.max(58, z.h - headerH - bottomH - topPad - 6)
  local metricW = math.floor((z.w - cardGap) / 2)

  local bottomY = z.y + z.h - bottomH
  local statW = math.floor(z.w / 4)

  lvgl.clear()
  lvgl.build({
    {
      type = "rectangle",
      x = z.x,
      y = z.y,
      w = z.w,
      h = z.h,
      color = COLOR_THEME_PRIMARY2,
      filled = true
    },
    {
      type = "image",
      x = z.x + 4,
      y = z.y + 2,
      w = 26,
      h = 26,
      file = LOGO_FILE
    },
    {
      type = "label",
      x = z.x + 36,
      y = z.y + 6,
      w = math.max(50, z.w - 120),
      text = "ROTORFLIGHT",
      color = WHITE,
      font = MIDSIZE
    },
    {
      type = "label",
      x = z.x + z.w - 110,
      y = z.y + 6,
      w = 100,
      text = function() return widget.values.state end,
      color = function()
        if widget.values.state == "ARMED" then return COLOR_THEME_WARNING end
        return COLOR_THEME_SECONDARY1
      end,
      align = RIGHT,
      font = SMLSIZE
    },

    {
      type = "rectangle",
      x = z.x,
      y = metricY,
      w = metricW,
      h = metricH,
      color = WHITE,
      filled = true
    },
    {
      type = "rectangle",
      x = z.x + metricW + cardGap,
      y = metricY,
      w = metricW,
      h = metricH,
      color = WHITE,
      filled = true
    },
    {
      type = "label",
      x = z.x,
      y = metricY + math.floor(metricH * 0.32),
      w = metricW,
      text = metricTextLeft,
      color = BLACK,
      align = CENTER,
      font = DBLSIZE
    },
    {
      type = "label",
      x = z.x,
      y = metricY + metricH - 24,
      w = metricW,
      text = "KRAFTSTOFF",
      color = GREY_DEFAULT,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = z.x + metricW + cardGap,
      y = metricY + math.floor(metricH * 0.32),
      w = metricW,
      text = metricTextRight,
      color = BLACK,
      align = CENTER,
      font = DBLSIZE
    },
    {
      type = "label",
      x = z.x + metricW + cardGap,
      y = metricY + metricH - 24,
      w = metricW,
      text = "SPANNUNG",
      color = GREY_DEFAULT,
      align = CENTER,
      font = SMLSIZE
    },

    {
      type = "rectangle",
      x = z.x,
      y = bottomY,
      w = z.w,
      h = bottomH,
      color = COLOR_THEME_PRIMARY1,
      filled = true
    },
    {
      type = "label",
      x = z.x + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("RPM %d", math.floor(widget.values.rpm or 0)) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = z.x + statW + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("PROF %d", widget.values.profile or 1) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = z.x + statW * 2 + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("FLUEGE %d", widget.values.flights or 0) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    },
    {
      type = "label",
      x = z.x + statW * 3 + 4,
      y = bottomY + 4,
      w = statW - 8,
      text = function() return string.format("LQ %d", math.floor(widget.values.lq or 0)) end,
      color = WHITE,
      align = CENTER,
      font = SMLSIZE
    }
  })

  widget.built = true
end

w.update = function(widget, newOptions)
  widget.options = newOptions
  widget.built = false
end

w.refresh = function(widget, event, touchState)
  readTelemetry(widget)

  if not widget.built then
    buildWidget(widget)
  end
end

w.background = function(widget)
  readTelemetry(widget)
  return 0
end

return w
