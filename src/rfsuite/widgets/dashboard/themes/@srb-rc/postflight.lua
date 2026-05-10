local Theme = {}

Theme.layout = { cols = 3, rows = 7, padding = 1, showstats = false }

Theme.boxes = {
  { col = 1, row = 1, colspan = 3, rowspan = 7, type = "text", subtype = "text", title = "", bgcolor = BLACK },

  { col = 1, row = 1, colspan = 1, rowspan = 2, type = "time", subtype = "flight", title = "FLIGHT DURATION", titlepos = "top", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 1, row = 3, colspan = 1, rowspan = 2, type = "text", subtype = "stats", source = "smartfuel", stattype = "min", title = "FUEL REMAINING", titlepos = "top", unit = "%", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 1, row = 5, colspan = 1, rowspan = 2, type = "time", subtype = "count", title = "FLIGHTS", titlepos = "top", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },

  { col = 2, row = 1, colspan = 1, rowspan = 2, type = "text", subtype = "stats", source = "current", stattype = "max", title = "CURRENT MAX", titlepos = "top", unit = "A", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 2, row = 3, colspan = 1, rowspan = 2, type = "text", subtype = "stats", source = "esc_temp", stattype = "max", title = "ESC TEMP MAX", titlepos = "top", unit = "°C", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 2, row = 5, colspan = 1, rowspan = 2, type = "text", subtype = "stats", source = "link", stattype = "min", title = "LINK MIN", titlepos = "top", unit = "%", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },

  { col = 3, row = 1, colspan = 1, rowspan = 2, type = "text", subtype = "stats", source = "current", stattype = "consumed", title = "CONSUMED", titlepos = "top", unit = "mAh", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 3, row = 3, colspan = 1, rowspan = 2, type = "text", subtype = "stats", source = "voltage", stattype = "last", title = "ENDING VOLTAGE", titlepos = "top", unit = "V", decimals = 2, titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 3, row = 5, colspan = 1, rowspan = 2, type = "text", subtype = "stats", source = "voltage", stattype = "cell", title = "VOLTS/CELL", titlepos = "top", unit = "V", decimals = 2, titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK }
}

return Theme
