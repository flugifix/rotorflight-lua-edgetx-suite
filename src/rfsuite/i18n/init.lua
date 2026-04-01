local I18n = {}

local BASE_PATH = "/SCRIPTS/TOOLS/rfsuite-core/i18n/"
local bundleCache = {}

local function normalizeLocale(locale)
  if type(locale) ~= "string" or locale == "" then return "de" end
  local lower = string.lower(locale)
  lower = string.gsub(lower, "_", "-")
  return lower
end

local function loadBundle(locale)
  local normalized = normalizeLocale(locale)
  local candidates = {normalized}
  local dash = string.find(normalized, "-", 1, true)
  if dash and dash > 1 then
    candidates[#candidates + 1] = string.sub(normalized, 1, dash - 1)
  end

  for i = 1, #candidates do
    local lang = candidates[i]
    if lang and lang ~= "" then
      local cached = bundleCache[lang]
      if cached ~= nil then
        if cached ~= false then
          return cached, lang
        end
      else
        local chunk = loadScript(BASE_PATH .. lang .. ".lua", "t")
        if chunk then
          local ok, bundle = pcall(chunk)
          if ok and type(bundle) == "table" then
            bundleCache[lang] = bundle
            return bundle, lang
          end
        end
        bundleCache[lang] = false
      end
    end
  end

  return nil, normalized
end

local function getPathValue(root, key)
  local node = root
  for part in string.gmatch(key, "[^.]+") do
    if type(node) ~= "table" then
      return nil
    end
    node = node[part]
  end
  return node
end

function I18n.new(locale)
  local activeLang = normalizeLocale(locale)
  local active = loadBundle(activeLang)
  if type(active) ~= "table" then
    active = loadBundle("en") or {}
    activeLang = "en"
  end

  local ctx = {}

  function ctx.t(key)
    local val = getPathValue(active, key)
    if val ~= nil then
      return val
    end

    if activeLang ~= "en" then
      local fallbackBundle = loadBundle("en")
      if type(fallbackBundle) == "table" then
        local fallback = getPathValue(fallbackBundle, key)
        if fallback ~= nil then
          return fallback
        end
      end
    end

    return key
  end

  function ctx.setLocale(nextLocale)
    local lang = normalizeLocale(nextLocale)
    local nextBundle = loadBundle(lang)
    if type(nextBundle) == "table" then
      active = nextBundle
      activeLang = lang
      return true
    end
    return false
  end

  function ctx.getLocale()
    return activeLang
  end

  function ctx.resolve(value)
    if type(value) ~= "string" then
      return value
    end

    local text = value
    text = string.gsub(text, "@i18n%(([^)]+)%)%:upper%(%)%@", function(k)
      return string.upper(ctx.t(k))
    end)
    text = string.gsub(text, "@i18n%(([^)]+)%)%@", function(k)
      return ctx.t(k)
    end)

    return text
  end

  return ctx
end

return I18n
