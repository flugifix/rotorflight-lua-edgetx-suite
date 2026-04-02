local Theme = {}

Theme.layout = { cols = 2, rows = 2, padding = 2 }

Theme.boxes = {
	{ col = 1, row = 1, colspan = 1, rowspan = 1, type = "time", subtype = "flight", title = "@i18n(widgets.dashboard.last_flight)@", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
	{ col = 2, row = 1, colspan = 1, rowspan = 1, type = "time", subtype = "total", title = "@i18n(widgets.dashboard.total_time)@", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
	{ col = 1, row = 2, colspan = 1, rowspan = 1, type = "text", subtype = "stats", source = "min_voltage_cell", title = "@i18n(widgets.dashboard.min_cell)@", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
	{ col = 2, row = 2, colspan = 1, rowspan = 1, type = "text", subtype = "stats", source = "min_link", title = "@i18n(widgets.dashboard.min_link)@", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK }
}

return Theme
