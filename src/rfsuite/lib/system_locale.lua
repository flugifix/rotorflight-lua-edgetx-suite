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

  -- Try to get from internal preferences
  local root = _G and _G.rfsuite
  local prefs = root and root.preferences
  local general = prefs and prefs.general
  local configured = normalizeLanguage(general and general.language)

  if configured then
    return configured
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