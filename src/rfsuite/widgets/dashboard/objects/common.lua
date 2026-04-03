if type(_G) == "table" and type(_G.__rfsuiteObjectsCommonModule) == "table" then
  return _G.__rfsuiteObjectsCommonModule
end

local Utils = {}

local i18nModule = nil
local i18nContext = nil
local i18nLocale = nil
local sensorsModule = nil
local localeModule = nil

local function getLocaleModule()
  if localeModule then
    return localeModule
  end

  if type(_G) == "table" and type(_G.__rfsuiteSystemLocaleModule) == "table" then
    localeModule = _G.__rfsuiteSystemLocaleModule
    return localeModule
  end

  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/system_locale.lua", "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then
      localeModule = mod
      if type(_G) == "table" then
        _G.__rfsuiteSystemLocaleModule = mod
      end
    end
  end

  return localeModule
end

local function resolveLocale()
  local mod = getLocaleModule()
  if mod and type(mod.resolveSystemLanguage) == "function" then
    local ok, locale = pcall(mod.resolveSystemLanguage, "en")
    if ok and type(locale) == "string" and locale ~= "" then
      return locale
    end
  end

  return "en"
end

local function getI18nContext()
  local locale = resolveLocale()
  if i18nContext and i18nLocale == locale then
    return i18nContext
  end

  if not i18nModule then
    local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/i18n/init.lua", "t")
    if chunk then
      local ok, mod = pcall(chunk)
      if ok and type(mod) == "table" and type(mod.new) == "function" then
        i18nModule = mod
      end
    end
  end

  if i18nModule and type(i18nModule.new) == "function" then
    local ok, ctx = pcall(i18nModule.new, locale)
    if ok and type(ctx) == "table" then
      i18nContext = ctx
      i18nLocale = locale
      return i18nContext
    end
  end

  return nil
end

function Utils.clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

function Utils.resolveValue(value, box, state)
  if type(value) == "function" then
    local ok, resolved = pcall(value, box, state)
    if ok then return resolved end
    return nil
  end
  return value
end

function Utils.normalizeTitle(raw)
  if type(raw) ~= "string" or raw == "" then return nil end
  if string.find(raw, "@i18n(", 1, true) then
    local i18n = getI18nContext()
    if i18n and type(i18n.resolve) == "function" then
      local ok, resolved = pcall(i18n.resolve, raw)
      if ok and type(resolved) == "string" and resolved ~= "" then
        return resolved
      end
    end
  end

  local token = string.match(raw, "@i18n%(([^)]+)%)")
  if token then
    local key = string.match(token, "([^.]+)$") or token
    if string.find(raw, ":upper%(", 1, false) then
      return string.upper(key)
    end
    return key
  end
  return raw
end

function Utils.toNumber(value, fallback)
  if type(value) == "number" then return value end
  return fallback
end

function Utils.mapTelemetrySource(source, state)
  if type(source) ~= "string" then return nil end

  -- Fast-path hot dashboard values from runtime state to avoid file/telemetry
  -- lookups in every refresh.
  if source == "pid_profile" then return state and state.profile end
  if source == "rate_profile" then return state and state.rateProfile end
  if source == "battery_profile" then return state and state.batteryProfile end
  if source == "link" then return state and state.lq end
  if source == "voltage" then return state and state.voltage end
  if source == "rpm" then return state and state.rpm end
  if source == "fuel" then return state and state.fuel end
  if source == "governor" then return state and state.gov end
  if source == "esc_temp" then return state and state.temp_esc end
  if source == "mcu_temp" then return state and state.temp_mcu end

  -- Load sensors module lazily
  if not sensorsModule then
    local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/sensors.lua", "t")
    if chunk then
      local ok, mod = pcall(chunk)
      if ok and type(mod) == "table" then
        sensorsModule = mod
      end
    end
  end

  if sensorsModule and type(sensorsModule.getValue) == "function" then
    local value = sensorsModule.getValue(source)
    if type(value) == "number" then return value end
  end

  return nil
end

function Utils.applyTransform(value, transform)
  if value == nil then return value end
  if transform == "floor" and type(value) == "number" then
    return math.floor(value)
  end
  if transform == "ceil" and type(value) == "number" then
    return math.ceil(value)
  end
  if transform == "round" and type(value) == "number" then
    return math.floor(value + 0.5)
  end
  if type(transform) == "number" and type(value) == "number" then
    return value * transform
  end
  return value
end

function Utils.formatDisplayValue(value, decimals)
  if value == nil then return "--" end
  if type(value) == "number" then
    if type(decimals) == "number" then
      return string.format("%." .. tostring(decimals) .. "f", value)
    end
    return tostring(math.floor(value + 0.5))
  end
  return tostring(value)
end

function Utils.appendUnit(valueText, unit)
  if unit == nil or unit == "" then return valueText end
  return valueText .. tostring(unit)
end

function Utils.pushLabel(nodes, x, y, w, text, color, align, font)
  nodes[#nodes + 1] = {
    type = "label",
    x = x,
    y = y,
    w = w,
    text = text,
    color = color,
    align = align,
    font = font
  }
end

function Utils.defaultValueY(rect, box)
  local titlePos = box and box.titlepos or "top"
  local valueY = rect.y + math.max(14, math.floor(rect.h * 0.45))
  if titlePos == "bottom" then
    valueY = rect.y + math.max(8, math.floor(rect.h * 0.35)) - 4
  end
  return valueY
end

function Utils.drawContainer(nodes, rect, box, state)
  nodes[#nodes + 1] = {
    type = "rectangle",
    x = rect.x,
    y = rect.y,
    w = rect.w,
    h = rect.h,
    color = box.bgcolor or WHITE,
    filled = true
  }

  local title = Utils.normalizeTitle(Utils.resolveValue(box.title, box, state))
  if not title then return end

  local titlePos = box.titlepos or "top"
  local titleY = titlePos == "bottom" and (rect.y + rect.h - 24) or (rect.y + 4)
  Utils.pushLabel(
    nodes,
    rect.x + 4,
    titleY,
    rect.w - 8,
    title,
    box.titlecolor or GREY_DEFAULT,
    box.titlealign or CENTER,
    SMLSIZE
  )
end

if type(_G) == "table" then _G.__rfsuiteObjectsCommonModule = Utils end
return Utils
