local Theme = {}

Theme.layout = { cols = 2, rows = 2, padding = 2, bgcolor = WHITE }

-- The link quality box's colour steps: amber at the Link Quality announcement's warning level, red
-- at its critical one, read off `state.alerts`, which the host resolves before it builds this
-- theme. Only where the pilot has switched them on in this theme's settings (configure.lua,
-- `link_colors`, off by default) and the announcement itself is on. Each limit is a function of the
-- state, resolved when the box is built; otherwise the box carries no thresholds and draws as it
-- always did.
local function linkThresholds(state)
	local cfg = state and state.themeConfig
	local alerts = state and state.alerts
	local lq = type(alerts) == "table" and alerts.lq or nil
	if not (type(cfg) == "table" and cfg.link_colors == true and type(lq) == "table" and lq.on == true) then
		return nil
	end
	return {
		{ value = function(_, s) local a = s and s.alerts return a and a.lq and a.lq.critical end, textcolor = "red" },
		{ value = function(_, s) local a = s and s.alerts return a and a.lq and a.lq.warn end, textcolor = "orange" },
	}
end

-- A function rather than a table only so the link box can take its steps from the state.
Theme.boxes = function(_, state) return {
	{ col = 1, row = 1, colspan = 1, rowspan = 1, type = "time", subtype = "flight", title = "@i18n(widgets.dashboard.time)@", titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK },
	{ col = 1, row = 2, colspan = 1, rowspan = 1, type = "text", subtype = "telemetry", source = "link", unit = "%", title = "@i18n(widgets.dashboard.link)@", transform = "floor", titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK, thresholds = linkThresholds(state) },
	{
		col = 2,
		row = 1,
		colspan = 1,
		rowspan = 2,
		type = "gauge",
		subtype = "arc",
		source = "voltage",
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
} end

return Theme
