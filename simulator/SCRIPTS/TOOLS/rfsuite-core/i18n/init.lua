local I18n = {}

local bundles = {
  de = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/i18n/de.lua", "t"))(),
  en = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/i18n/en.lua", "t"))()
}

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
  local lang = locale or "de"
  local active = bundles[lang] or bundles.en

  local ctx = {}

  function ctx.t(key)
    local val = getPathValue(active, key)
    if val ~= nil then
      return val
    end

    local fallback = getPathValue(bundles.en, key)
    if fallback ~= nil then
      return fallback
    end

    return key
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
