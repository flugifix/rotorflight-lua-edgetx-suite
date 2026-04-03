local M = {}
local cachedRadioLanguage = nil
local radioLanguageLoaded = false

local function startsWithLangTag(value, tag)
  if value == tag then return true end
  if string.sub(value, 1, #tag + 1) == tag .. "-" then return true end
  if string.sub(value, 1, #tag + 1) == tag .. "_" then return true end
  if string.sub(value, 1, #tag + 1) == tag .. "/" then return true end
  return false
end

local function detectLang(value)
  if type(value) ~= "string" then
    return nil
  end

  local normalized = string.lower(value)
  normalized = string.gsub(normalized, "_", "-")

  if normalized == "de" or normalized == "deutsch" or normalized == "german" then return "de" end
  if normalized == "en" or normalized == "english" or normalized == "englisch" then return "en" end

  if startsWithLangTag(normalized, "de") then return "de" end
  if startsWithLangTag(normalized, "en") then return "en" end

  if string.find(normalized, "/de/", 1, true) or string.find(normalized, "-de", 1, true) then return "de" end
  if string.find(normalized, "/en/", 1, true) or string.find(normalized, "-en", 1, true) then return "en" end

  return nil
end

local function detectLangFromTable(value)
  if type(value) ~= "table" then
    return nil
  end

  local keyed = detectLang(
    value.uiLanguage
    or value.ttsLanguage
    or value.voiceLanguage
    or value.locale
    or value.language
    or value.lang
  )
  if keyed then
    return keyed
  end

  for _, v in pairs(value) do
    local scanned = detectLang(v)
    if scanned then
      return scanned
    end
  end

  return nil
end

local function readRadioYmlLanguage()
  if radioLanguageLoaded then
    return cachedRadioLanguage
  end
  radioLanguageLoaded = true

  local f = io.open("/RADIO/radio.yml", "r")
  if not f then
    return nil
  end

  local content = io.read(f, 8192)
  io.close(f)
  if type(content) ~= "string" or content == "" then
    return nil
  end

  local ui = string.match(content, "uiLanguage:%s*\"([^\"]+)\"")
  local tts = string.match(content, "ttsLanguage:%s*\"([^\"]+)\"")
  local lang = detectLang(ui) or detectLang(tts)
  if lang then
    cachedRadioLanguage = lang
  end
  return cachedRadioLanguage
end

function M.resolveSystemLanguage(defaultLang)
  local fallback = detectLang(defaultLang) or "en"

  if system and type(system.getGeneralSettings) == "function" then
    local ok, settings = pcall(system.getGeneralSettings)
    if ok then
      local lang = detectLangFromTable(settings) or detectLang(settings)
      if lang then
        return lang
      end
    end
  end

  if system and type(system.getLocale) == "function" then
    local ok, locale = pcall(system.getLocale)
    if ok then
      local lang = detectLangFromTable(locale) or detectLang(locale)
      if lang then
        return lang
      end
    end
  end

  if system and type(system.getAudioVoice) == "function" then
    local ok, voice = pcall(system.getAudioVoice)
    if ok then
      local lang = detectLangFromTable(voice) or detectLang(voice)
      if lang then
        return lang
      end
    end
  end

  local radioLang = readRadioYmlLanguage()
  if radioLang then
    return radioLang
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

return M