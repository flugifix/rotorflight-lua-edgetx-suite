if type(_G) == "table" and type(_G.__rfsuite_system_locale_module) == "table" then
  return _G.__rfsuite_system_locale_module
end

local M = {}

local function trace(message)
  -- Silenced to reduce log spam in production
  -- if type(print) == "function" then
  --   print("[system_locale] " .. tostring(message))
  -- end
end

local function normalizeLanguage(value)
  local text = string.lower(tostring(value or ""))
  if text == "de" then return "de" end
  if text == "en" then return "en" end
  return nil
end

function M.resolveSystemLanguage(defaultLang)
  local fallback = normalizeLanguage(defaultLang) or "en"
  trace("resolveSystemLanguage(): fallback=" .. tostring(fallback))

  local root = _G and _G.rfsuite
  local prefs = root and root.preferences
  local general = prefs and prefs.general
  local configured = general and general.language
  local resolved = normalizeLanguage(configured)

  if resolved then
    trace("resolved from prefs.general.language=" .. tostring(configured))
    return resolved
  end

  if configured ~= nil then
    trace("unsupported prefs.general.language=" .. tostring(configured) .. ", using fallback")
  else
    trace("prefs.general.language not set, using fallback")
  end

  return fallback
end

function M.resolveAudioFolder(defaultFolder)
  local lang = M.resolveSystemLanguage(defaultFolder or "en")
  if lang ~= "de" and lang ~= "en" then
    return "en"
  end
  return lang
end

if type(_G) == "table" then
  _G.__rfsuite_system_locale_module = M
end

return M