local Theme = {}

Theme.layout = { cols = 20, rows = 8, padding = 1 }

Theme.boxes = function(_, state)
	return {
		{ col = 1, row = 1, colspan = 8, rowspan = 4, type = "image", subtype = "model", bgcolor = BLACK },
		{ col = 1, row = 5, colspan = 4, rowspan = 2, type = "time", subtype = "flight", title = "@i18n(widgets.dashboard.time)@", titlepos = "bottom", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
		{ col = 5, row = 5, colspan = 4, rowspan = 2, type = "text", subtype = "blackbox", title = "@i18n(widgets.dashboard.blackbox)@", titlepos = "bottom", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
		{ col = 5, row = 7, colspan = 2, rowspan = 2, type = "time", subtype = "count", title = "@i18n(widgets.dashboard.flights)@", titlepos = "bottom", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
		{ col = 1, row = 7, colspan = 2, rowspan = 2, type = "text", subtype = "telemetry", source = "pid_profile", title = "@i18n(widgets.dashboard.profile)@", titlepos = "bottom", transform = "floor", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
		{ col = 3, row = 7, colspan = 2, rowspan = 2, type = "text", subtype = "telemetry", source = "rate_profile", title = "@i18n(widgets.dashboard.rates)@", titlepos = "bottom", transform = "floor", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
		{ col = 7, row = 7, colspan = 2, rowspan = 2, type = "text", subtype = "telemetry", source = "link", unit = "%", title = "@i18n(widgets.dashboard.link)@", titlepos = "bottom", transform = "floor", titlecolor = GREY_DEFAULT, textcolor = WHITE, bgcolor = BLACK },
		{
			col = 9,
			row = 1,
			colspan = 12,
			rowspan = 8,
			type = "gauge",
			subtype = "arc",
			source = "RxBt",
			title = "@i18n(widgets.dashboard.voltage)@",
			titlepos = "bottom",
			textcolor = WHITE,
			bgcolor = BLACK,
			min = function(_, runtimeState)
				local cfg = runtimeState and runtimeState.themeConfig or nil
				return tonumber(cfg and cfg.v_min) or 18.0
			end,
			max = function(_, runtimeState)
				local cfg = runtimeState and runtimeState.themeConfig or nil
				return tonumber(cfg and cfg.v_max) or 25.2
			end
		}
	}
end

return Theme
