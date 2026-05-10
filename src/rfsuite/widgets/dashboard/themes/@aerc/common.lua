if type(_G) == "table" and type(_G.__rfsuiteThemeAercCommonModule) == "table" then
  return _G.__rfsuiteThemeAercCommonModule
end

local Common = {}

local LOGO_FILE = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png"

local i18nModule = nil
local i18nContext = nil
local i18nLocale = nil
local localeModule = nil

local function getLocaleModule()
  if localeModule then
    return localeModule
  end

  if type(_G) == "table" and type(_G.__rfsuite_system_locale_module) == "table" then
    localeModule = _G.__rfsuite_system_locale_module
    return localeModule
  end

  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/system_locale.lua", "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then
      localeModule = mod
      if type(_G) == "table" then
        _G.__rfsuite_system_locale_module = mod
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

local function t(key, fallback)
  local ctx = getI18nContext()
  if ctx and type(ctx.t) == "function" then
    local ok, translated = pcall(ctx.t, key)
    if ok and type(translated) == "string" and translated ~= "" and translated ~= key then
      return translated
    end
  end
  return fallback or key
end

local function append(nodes, extra)
  for index = 1, #extra do
    nodes[#nodes + 1] = extra[index]
  end
end

local function clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function merge(dst, src)
  if type(src) ~= "table" then return dst end
  for key, value in pairs(src) do
    dst[key] = value
  end
  return dst
end

function Common.batteryBar(source, overrides)
  local box = {
    type = "gauge",
    subtype = "bar",
    source = source or "smartfuel",
    unit = "%",
    min = 0,
    max = 100,
    transform = "floor",
    valuealign = LEFT,
    valuepaddingleft = 8,
    valuepaddingtop = -25,
    battadv = true,
    battadvvaluealign = RIGHT,
    battadvpaddingright = 12,
    battadvpaddingtop = 0,
    titlecolor = GREY_DEFAULT,
    textcolor = WHITE,
    bgcolor = BLACK,
    fillbgcolor = GREY_DEFAULT,
    thresholds = {
      { value = 10, fillcolor = RED },
      { value = 45, fillcolor = YELLOW }
    }
  }

  return merge(box, overrides)
end

Common.LOGO_FILE = LOGO_FILE
Common.t = t
Common.append = append
Common.clamp = clamp

if type(_G) == "table" then
  _G.__rfsuiteThemeAercCommonModule = Common
end

return Common
