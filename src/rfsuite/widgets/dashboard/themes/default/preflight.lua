local Theme = {}

local function autoFont(box, state)
  return (state and (state.zoneW or 0) <= 480) and SMLSIZE or MIDSIZE
end

Theme.layout = { cols = 20, rows = 8, padding = 1, bgcolor = WHITE }

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

Theme.boxes = function(_, state)
	-- autoFont answers from state.zoneW alone, and the zone size is part of the render key
	-- (Engine.renderKey in widgets/dashboard/engine.lua), so a zone that changes size tears this
	-- scene down and builds the next one from the size it then has. Resolved here, each of these
	-- boxes hands lvgl a number instead of a reference the firmware calls once per box on every
	-- foreground pass.
	local valueFont = autoFont(nil, state)
	return {
		{ col = 1, row = 1, colspan = 12, rowspan = 4, type = "image", subtype = "model", bgcolor = BLACK, textcolor = WHITE, titlecolor = COLOR_THEME_DISABLED },
		{ col = 1, row = 5, colspan = 6, rowspan = 2, type = "time", subtype = "flight", font = valueFont, title = "@i18n(widgets.dashboard.time)@", titlepos = "bottom", titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK },
		{ col = 7, row = 5, colspan = 6, rowspan = 2, type = "text", subtype = "blackbox", font = valueFont, title = "@i18n(widgets.dashboard.blackbox)@", titlepos = "bottom", titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK, autosize_chars = 12 },
		{ col = 1, row = 7, colspan = 3, rowspan = 2, type = "text", subtype = "telemetry", font = valueFont, source = "pid_profile", title = "@i18n(widgets.dashboard.profile)@", titlepos = "bottom", transform = "floor", titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK },
		{ col = 4, row = 7, colspan = 3, rowspan = 2, type = "text", subtype = "telemetry", font = valueFont, source = "rate_profile", title = "@i18n(widgets.dashboard.rates)@", titlepos = "bottom", transform = "floor", titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK },
		{ col = 7, row = 7, colspan = 3, rowspan = 2, type = "time", subtype = "count", font = valueFont, title = "@i18n(widgets.dashboard.flights)@", titlepos = "bottom", titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK },
		{ col = 10, row = 7, colspan = 3, rowspan = 2, type = "text", subtype = "telemetry", font = valueFont, source = "link", unit = "%", title = "@i18n(widgets.dashboard.link)@", titlepos = "bottom", transform = "floor", autosize_chars = 3, titlecolor = COLOR_THEME_DISABLED, textcolor = WHITE, bgcolor = BLACK, thresholds = linkThresholds(state) },
		{
			col = 13,
			row = 1,
			colspan = 8,
			rowspan = 8,
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
	}
end

return Theme
