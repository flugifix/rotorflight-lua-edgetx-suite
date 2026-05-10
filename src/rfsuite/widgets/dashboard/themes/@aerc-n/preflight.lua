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
  -- Left column: Text info
  { col = 1, colspan = 2, row = 1, rowspan = 3, type = "text", subtype = "telemetry", source = "throttle_percent", unit = "%", title = "@i18n(widgets.dashboard.throttle):upper()@", titlepos = "bottom", transform = "floor", bgcolor = BLACK, titlecolor = GREY_DEFAULT, textcolor = "orange", thresholds = {{value = 20, textcolor = "orange"}, {value = 80, textcolor = "yellow"}, {value = 100, textcolor = "red"}} },
  { col = 1, colspan = 2, row = 4, rowspan = 3, type = "text", subtype = "telemetry", source = "rpm", title = "@i18n(widgets.dashboard.headspeed):upper()@", titlepos = "bottom", unit = " rpm", transform = "floor", bgcolor = BLACK, titlecolor = GREY_DEFAULT, textcolor = "orange" },
  { col = 1, colspan = 2, row = 7, rowspan = 3, type = "text", subtype = "blackbox", title = "@i18n(widgets.dashboard.blackbox):upper()@", titlepos = "bottom", decimals = 0, bgcolor = BLACK, titlecolor = GREY_DEFAULT, textcolor = "orange", transform = "floor", thresholds = {{value = 80, textcolor = "orange"}, {value = 90, textcolor = "yellow"}, {value = 100, textcolor = "red"}} },
  { col = 1, colspan = 2, row = 10, rowspan = 3, type = "text", subtype = "governor", title = "@i18n(widgets.dashboard.governor):upper()@", titlepos = "bottom", bgcolor = BLACK, titlecolor = GREY_DEFAULT, thresholds = {{value = "@i18n(widgets.governor.DISARMED)@", textcolor = "red"}, {value = "@i18n(widgets.governor.OFF)@", textcolor = "red"}, {value = "@i18n(widgets.governor.IDLE)@", textcolor = "blue"}, {value = "@i18n(widgets.governor.SPOOLUP)@", textcolor = "blue"}, {value = "@i18n(widgets.governor.RECOVERY)@", textcolor = "yellow"}, {value = "@i18n(widgets.governor.ACTIVE)@", textcolor = "green"}, {value = "@i18n(widgets.governor.THR-OFF)@", textcolor = "red"}} },

  -- Center: Model image
  { col = 3, colspan = 3, row = 1, rowspan = 9, type = "image", subtype = "model", bgcolor = BLACK },

  -- Bottom center: Rates, Profile, Flights
  { col = 3, colspan = 1, row = 10, rowspan = 3, type = "text", subtype = "telemetry", source = "rate_profile", title = "@i18n(widgets.dashboard.rates):upper()@", titlepos = "bottom", transform = "floor", bgcolor = BLACK, titlecolor = GREY_DEFAULT, textcolor = "orange" },
  { col = 4, colspan = 1, row = 10, rowspan = 3, type = "text", subtype = "telemetry", source = "pid_profile", title = "@i18n(widgets.dashboard.profile):upper()@", titlepos = "bottom", transform = "floor", bgcolor = BLACK, titlecolor = GREY_DEFAULT, textcolor = "orange" },
  { col = 5, colspan = 1, row = 10, rowspan = 3, type = "time", subtype = "count", title = "@i18n(widgets.dashboard.flights):upper()@", titlepos = "bottom", bgcolor = BLACK, titlecolor = GREY_DEFAULT, textcolor = "orange" },

  -- Right: BEC Voltage vertical
  { col = 6, colspan = 1, row = 1, rowspan = 12, type = "gauge", subtype = "bar", source = "bec_voltage", gaugeorientation = "vertical", battery = true, batterysegments = 5, title = "@i18n(widgets.dashboard.voltage):upper()@", titlepos = "bottom", decimals = 1, unit = "V", valueposition = "center", valuealign = CENTER, gaugepaddingtop = 6, gaugepaddingleft = 4, gaugepaddingright = 4, gaugepaddingbottom = 5, bgcolor = BLACK, fillbgcolor = GREY_DEFAULT, titlecolor = GREY_DEFAULT, textcolor = WHITE, min = function(_, state) return cfgValue("bec_min", 3.0, state) end, max = function(_, state) return cfgValue("bec_max", 13.0, state) end, thresholds = {{value = 6.0, fillcolor = RED}, {value = 8.0, fillcolor = YELLOW}, {value = 1000, fillcolor = GREEN}} }
}

return Theme
