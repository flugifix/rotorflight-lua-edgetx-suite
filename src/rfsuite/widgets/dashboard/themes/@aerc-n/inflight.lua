local Theme = {}

local function cfgValue(key, fallback, state)
  local cfg = state and state.themeConfig or nil
  local value = cfg and cfg[key] or nil
  if type(value) == "number" then
    return value
  end
  return fallback
end

Theme.layout = { cols = 6, rows = 12, padding = 1 }

Theme.boxes = {
  -- Left: RPM Arc Gauge
  {
    col = 1,
    colspan = 2,
    row = 1,
    rowspan = 12,
    type = "gauge",
    subtype = "arc",
    source = "rpm",
    arcmax = true,
    title = "@i18n(widgets.dashboard.headspeed):upper()@",
    titlepos = "bottom",
    min = function(_, state) return cfgValue("rpm_min", 0, state) end,
    max = function(_, state) return cfgValue("rpm_max", 3000, state) end,
    unit = "",
    transform = "floor",
    bgcolor = BLACK,
    titlecolor = GREY_DEFAULT,
    textcolor = WHITE,
    fillbgcolor = GREY_DEFAULT,
    maxtextcolor = YELLOW,
    maxfont = SMLSIZE,
    maxposition = "top",
    maxalign = CENTER,
    maxpaddingtop = 300,
    thresholds = {
      { value = 500, fillcolor = BLUE },
      { value = 2000, fillcolor = GREEN },
      { value = 3000, fillcolor = YELLOW },
      { value = 10000, fillcolor = RED }
    }
  },

  -- Center top: Flight time
  {
    col = 3,
    colspan = 2,
    row = 1,
    rowspan = 2,
    type = "time",
    subtype = "flight",
    valueposition = "center",
    valuepaddingtop = -12,
    bgcolor = BLACK,
    titlecolor = GREY_DEFAULT,
    textcolor = YELLOW
  },

  -- Center: BEC Voltage vertical
  {
    col = 3,
    colspan = 2,
    row = 3,
    rowspan = 10,
    type = "gauge",
    subtype = "bar",
    source = "bec_voltage",
    gaugeorientation = "vertical",
    battery = true,
    batterysegments = 5,
    title = "@i18n(widgets.dashboard.voltage):upper()@",
    titlepos = "bottom",
    decimals = 1,
    unit = "V",
    valueposition = "center",
    valuealign = CENTER,
    gaugepaddingtop = 6,
    gaugepaddingleft = 4,
    gaugepaddingright = 4,
    gaugepaddingbottom = 5,
    bgcolor = BLACK,
    fillbgcolor = GREY_DEFAULT,
    titlecolor = GREY_DEFAULT,
    textcolor = WHITE,
    min = function(_, state) return cfgValue("bec_min", 3.0, state) end,
    max = function(_, state) return cfgValue("bec_max", 13.0, state) end,
    thresholds = {
      { value = 6.0, fillcolor = RED },
      { value = 8.0, fillcolor = YELLOW },
      { value = 1000, fillcolor = GREEN }
    }
  },

  -- Right: Throttle Arc Gauge
  {
    col = 5,
    colspan = 2,
    row = 1,
    rowspan = 12,
    type = "gauge",
    subtype = "arc",
    source = "throttle_percent",
    arcmax = true,
    title = "@i18n(widgets.dashboard.throttle):upper()@",
    titlepos = "bottom",
    min = 0,
    max = 100,
    unit = "%",
    transform = "floor",
    bgcolor = BLACK,
    titlecolor = GREY_DEFAULT,
    textcolor = WHITE,
    fillbgcolor = GREY_DEFAULT,
    maxtextcolor = YELLOW,
    maxfont = SMLSIZE,
    maxposition = "top",
    maxalign = CENTER,
    maxpaddingtop = 300,
    thresholds = {
      { value = 89, fillcolor = BLUE },
      { value = 100, fillcolor = GREEN }
    }
  }
}

return Theme
