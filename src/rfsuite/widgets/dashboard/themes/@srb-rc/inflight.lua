local Theme = {}
local OLIVE = (lcd and lcd.RGB and lcd.RGB(0x808000)) or YELLOW

local function loadSrbCommon()
  if type(_G) == "table" and type(_G.__rfsuiteThemeSrbCommonModule) == "table" then
    return _G.__rfsuiteThemeSrbCommonModule
  end

  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/@srb-rc/common.lua", "t")
  if not chunk then return nil end
  local ok, mod = pcall(chunk)
  if ok and type(mod) == "table" then
    if type(_G) == "table" then
      _G.__rfsuiteThemeSrbCommonModule = mod
    end
    return mod
  end
  return nil
end

local SrbCommon = loadSrbCommon()

local function cfgValue(key, fallback, state)
  local cfg = state and state.themeConfig or nil
  local value = cfg and cfg[key] or nil
  if type(value) == "number" then
    return value
  end
  return fallback
end

Theme.layout = { cols = 13, rows = 10, padding = 1 }

Theme.boxes = {
  { col = 1, row = 1, colspan = 13, rowspan = 10, type = "text", subtype = "text", title = "", bgcolor = BLACK },

  { col = 1, row = 1, colspan = 4, rowspan = 3, type = "text", subtype = "governor", title = "GOVERNOR", titlepos = "top", titlealign = CENTER, titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, warningcolor = WHITE, activecolor = WHITE, bgcolor = OLIVE },

  { col = 1, row = 4, colspan = 2, rowspan = 3, type = "text", subtype = "telemetry", source = "pid_profile", title = "PROFILE", titlepos = "top", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 3, row = 4, colspan = 2, rowspan = 3, type = "text", subtype = "telemetry", source = "rate_profile", title = "RATE", titlepos = "top", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },

  { col = 5, row = 1, colspan = 3, rowspan = 3, type = "text", subtype = "telemetry", source = "bec_voltage", title = "BEC", titlepos = "top", decimals = 1, unit = "V", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK, thresholds = { { value = function(_, state) return cfgValue("bec_warn", 6.5, state) end, textcolor = RED } } },
  { col = 5, row = 4, colspan = 3, rowspan = 3, type = "text", subtype = "telemetry", source = "esc_temp", title = "ESC TEMP", titlepos = "top", unit = "°C", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },

  { col = 8, row = 1, colspan = 3, rowspan = 3, type = "text", subtype = "telemetry", source = "link", title = "LQ", titlepos = "top", unit = "dB", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },
  { col = 8, row = 4, colspan = 3, rowspan = 3, type = "text", subtype = "telemetry", source = "current", title = "CURRENT", titlepos = "top", unit = "A", transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },

  { col = 11, row = 1, colspan = 3, rowspan = 3, type = "text", subtype = "telemetry", source = "rpm", title = "RPM", titlepos = "top", titlealign = CENTER, transform = "floor", titlefont = SMLSIZE, font = DBLSIZE, textcolor = BLACK, titlecolor = BLACK, bgcolor = WHITE },
  { col = 11, row = 4, colspan = 3, rowspan = 3, type = "time", subtype = "flight", title = "TIMER", titlepos = "top", titlefont = SMLSIZE, font = DBLSIZE, textcolor = WHITE, titlecolor = WHITE, bgcolor = BLACK },

  SrbCommon and SrbCommon.batteryBar and SrbCommon.batteryBar("smartfuel", {
    col = 1,
    row = 7,
    colspan = 13,
    rowspan = 4,
    title = "FLIGHT BATTERY",
    titlepos = "top",
    titlefont = SMLSIZE,
    font = DBLSIZE
  })
}

return Theme
