local M = {}

local DEBUG_PREFIX = "[dashboard.lib] "
local INDEX_PATH = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/settings/dashboard/theme_index.lua"

local function debugLog(message)
  if type(print) == "function" then
    print(DEBUG_PREFIX .. tostring(message))
  end
end

local SYSTEM_THEMES_LIST_PATH = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes"
local USER_THEMES_LIST_PATH = "/SCRIPTS/TOOLS/rfsuite.user/dashboard"
local SYSTEM_THEMES_LOAD_PATH = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/"
local USER_THEMES_LOAD_PATH = "/SCRIPTS/TOOLS/rfsuite.user/dashboard/"

local function normalizePath(path)
  if type(path) ~= "string" then return nil end
  if path == "" then return nil end
  return path
end

local function sanitizeThemeKey(path)
  if type(path) ~= "string" then return nil end
  if path == "" then return nil end
  return string.gsub(path, "[^%w]", "_")
end

local function themeConfigKey(path, key)
  local prefix = sanitizeThemeKey(path)
  if not prefix or type(key) ~= "string" or key == "" then return nil end
  return "cfg_" .. prefix .. "_" .. key
end

local function asThemePath(source, folder)
  if type(source) ~= "string" or type(folder) ~= "string" then
    return nil
  end
  if source == "" or folder == "" then
    return nil
  end
  return source .. "/" .. folder
end

local function appendTheme(themes, nextId, entry, loadBasePath)
  if type(entry) ~= "table" then return nextId end
  if type(entry.name) ~= "string" or entry.name == "" then return nextId end
  if type(entry.folder) ~= "string" or entry.folder == "" then return nextId end

  local configurePath = nil
  if type(entry.configure) == "string" and entry.configure ~= "" then
    configurePath = loadBasePath .. entry.folder .. "/" .. entry.configure
  end

  themes[#themes + 1] = {
    id = nextId,
    name = entry.name,
    source = entry.source,
    folder = entry.folder,
    path = asThemePath(entry.source, entry.folder),
    configure = entry.configure,
    configurePath = configurePath,
    iconPath = loadBasePath .. entry.folder .. "/icon.png",
    standalone = entry.standalone == true
  }
  return nextId + 1
end

local function loadThemeIndex()
  local ok, chunk = pcall(loadScript, INDEX_PATH, "t")
  if not ok or type(chunk) ~= "function" then
    debugLog("theme index missing path=" .. tostring(INDEX_PATH))
    return nil
  end

  local loadedOk, index = pcall(chunk)
  if not loadedOk or type(index) ~= "table" then
    debugLog("theme index invalid path=" .. tostring(INDEX_PATH))
    return nil
  end

  debugLog("theme index loaded entries=" .. tostring(#index))
  return index
end

local function loadIndexedThemes(themes, nextId)
  local index = loadThemeIndex()
  if type(index) ~= "table" then
    return nextId
  end

  for i = 1, #index do
    local entry = index[i]
    local source = entry and entry.source or nil
    local loadBasePath = nil
    if source == "system" then
      loadBasePath = SYSTEM_THEMES_LOAD_PATH
    elseif source == "user" then
      loadBasePath = USER_THEMES_LOAD_PATH
    end

    if loadBasePath then
      nextId = appendTheme(themes, nextId, entry, loadBasePath)
      debugLog("indexed theme name=" .. tostring(entry.name) .. " source=" .. tostring(entry.source) .. " folder=" .. tostring(entry.folder))
    end
  end

  return nextId
end

local function collectDirectoryEntries(listBasePath)
  if type(dir) == "function" then
    local iterator = dir(listBasePath)
    if type(iterator) ~= "function" then
      debugLog("dir unavailable for path=" .. tostring(listBasePath))
      return nil
    end

    local entries = {}
    for name in iterator do
      entries[#entries + 1] = name
    end
    debugLog("dir entries=" .. tostring(#entries) .. " path=" .. tostring(listBasePath))
    return entries
  end

  if system and system.listFiles then
    local entries = system.listFiles(listBasePath)
    debugLog("listFiles fallback type=" .. tostring(type(entries)) .. " path=" .. tostring(listBasePath))
    return entries
  end

  debugLog("no directory enumeration API available for path=" .. tostring(listBasePath))
  return nil
end

local function scanThemes(listBasePath, loadBasePath, source, themes, nextId)
  debugLog("scan start source=" .. tostring(source) .. " list=" .. tostring(listBasePath) .. " load=" .. tostring(loadBasePath))
  local entries = collectDirectoryEntries(listBasePath)
  if type(entries) ~= "table" then
    debugLog("directory enumeration returned " .. type(entries) .. " for source=" .. tostring(source))
    return nextId
  end

  debugLog("directory entries=" .. tostring(#entries) .. " for source=" .. tostring(source))

  for i = 1, #entries do
    local rawEntry = entries[i]
    if type(rawEntry) == "string" and rawEntry ~= "" then
      local trimmed = string.gsub(rawEntry, "[/\\]+$", "")
      local folder = string.match(trimmed, "([^/\\]+)$") or trimmed
      debugLog("entry raw=" .. tostring(rawEntry) .. " folder=" .. tostring(folder))
      if folder ~= "." and folder ~= ".." and folder ~= "" and not string.match(folder, "%.%a+$") then
        local initPath = loadBasePath .. folder .. "/init.lua"
        local ok, chunk = pcall(loadScript, initPath, "t")
        if ok and chunk then
          local initOk, initTable = pcall(chunk)
          if initOk and type(initTable) == "table" and type(initTable.name) == "string" then
            local configurePath = nil
            local configExists = false
            if type(initTable.configure) == "string" and initTable.configure ~= "" then
              configurePath = loadBasePath .. folder .. "/" .. initTable.configure
              -- Check if configure file exists
              local configOk, configChunk = pcall(loadScript, configurePath, "t")
              configExists = (configOk and configChunk ~= nil)
              if not configExists then
                debugLog("configure missing for theme=" .. tostring(folder) .. " path=" .. tostring(configurePath))
                configurePath = nil
              end
            end

            themes[#themes + 1] = {
              id = nextId,
              name = initTable.name,
              source = source,
              folder = folder,
              path = asThemePath(source, folder),
              configure = initTable.configure,
              configurePath = configurePath,
              iconPath = loadBasePath .. folder .. "/icon.png",
              standalone = initTable.standalone == true
            }
            debugLog("accepted theme name=" .. tostring(initTable.name) .. " path=" .. tostring(source) .. "/" .. tostring(folder) .. " configure=" .. tostring(initTable.configure) .. " configurePath=" .. tostring(configurePath))
            nextId = nextId + 1
          else
            debugLog("init invalid for folder=" .. tostring(folder) .. " initOk=" .. tostring(initOk) .. " type=" .. type(initTable))
          end
        else
          debugLog("loadScript failed for initPath=" .. tostring(initPath))
        end
      end
    end
  end

  return nextId
end

function M.listThemes()
  local themes = {}
  local nextId = 1

  debugLog("listThemes begin")
  nextId = scanThemes(SYSTEM_THEMES_LIST_PATH, SYSTEM_THEMES_LOAD_PATH, "system", themes, nextId)
  nextId = scanThemes(USER_THEMES_LIST_PATH, USER_THEMES_LOAD_PATH, "user", themes, nextId)

  if #themes == 0 then
    debugLog("runtime scan found no themes, using theme index")
    nextId = loadIndexedThemes(themes, nextId)
  end

  -- Fallback: ensure at least the default theme is available
  if #themes == 0 then
    debugLog("no themes found, entering default fallback")
    local defaultPath = "system/default"
    local initPath = SYSTEM_THEMES_LOAD_PATH .. "default/init.lua"
    local ok, chunk = pcall(loadScript, initPath, "t")
    if ok and chunk then
      local initOk, initTable = pcall(chunk)
      if initOk and type(initTable) == "table" and type(initTable.name) == "string" then
        local configurePath = nil
        if type(initTable.configure) == "string" and initTable.configure ~= "" then
          configurePath = SYSTEM_THEMES_LOAD_PATH .. "default/" .. initTable.configure
          local configOk, configChunk = pcall(loadScript, configurePath, "t")
          if not (configOk and configChunk) then
            configurePath = nil
          end
        end
        themes[#themes + 1] = {
          id = 1,
          name = initTable.name,
          source = "system",
          folder = "default",
          path = defaultPath,
          configure = initTable.configure,
          configurePath = configurePath,
          iconPath = SYSTEM_THEMES_LOAD_PATH .. "default/icon.png",
          standalone = initTable.standalone == true
        }
        debugLog("fallback default accepted")
      end
    else
      debugLog("fallback default init failed path=" .. tostring(initPath))
    end
  end

  for i = 1, #themes do
    local theme = themes[i]
    debugLog("theme[" .. tostring(i) .. "] name=" .. tostring(theme.name) .. " path=" .. tostring(theme.path) .. " configurePath=" .. tostring(theme.configurePath))
  end
  debugLog("listThemes end count=" .. tostring(#themes))

  return themes
end

function M.getDefaultThemePath(themes)
  if type(themes) == "table" and #themes > 0 then
    return themes[1].path
  end
  return nil
end

function M.getThemeById(themes, id)
  if type(themes) ~= "table" then return nil end
  local wanted = tonumber(id)
  if not wanted then return nil end
  for i = 1, #themes do
    if themes[i].id == wanted then
      return themes[i]
    end
  end
  return nil
end

function M.getThemeByPath(themes, path)
  if type(themes) ~= "table" then return nil end
  local wanted = normalizePath(path)
  if not wanted then return nil end
  for i = 1, #themes do
    if themes[i].path == wanted then
      return themes[i]
    end
  end
  return nil
end

function M.getThemeIdByPath(themes, path, fallbackId)
  local theme = M.getThemeByPath(themes, path)
  if theme then return theme.id end
  return fallbackId
end

function M.buildThemeOptions(themes)
  local options = {}
  if type(themes) ~= "table" then return options end
  for i = 1, #themes do
    local t = themes[i]
    options[#options + 1] = { value = t.id, label = t.name }
  end
  return options
end

function M.buildModelThemeOptions(themes, disabledLabel)
  local options = {
    { value = 0, label = disabledLabel or "Disabled" }
  }
  if type(themes) ~= "table" then return options end
  for i = 1, #themes do
    local t = themes[i]
    options[#options + 1] = { value = t.id, label = t.name }
  end
  return options
end

function M.getConfigurableThemes(themes)
  local configurable = {}
  if type(themes) ~= "table" then return configurable end
  for i = 1, #themes do
    local t = themes[i]
    if t.standalone ~= true and type(t.configurePath) == "string" and t.configurePath ~= "" then
      configurable[#configurable + 1] = t
      debugLog("configurable theme=" .. tostring(t.name) .. " path=" .. tostring(t.path))
    else
      debugLog("skipped configurable theme=" .. tostring(t and t.name) .. " standalone=" .. tostring(t and t.standalone) .. " configurePath=" .. tostring(t and t.configurePath))
    end
  end
  debugLog("getConfigurableThemes count=" .. tostring(#configurable))
  return configurable
end

function M.getThemeConfig(prefs, path, defaults)
  local out = {}
  local source = defaults or {}
  for k, v in pairs(source) do
    out[k] = v
  end

  local dashboard = prefs and prefs.dashboard
  if type(dashboard) ~= "table" then
    return out
  end

  for k in pairs(source) do
    local key = themeConfigKey(path, k)
    if key and dashboard[key] ~= nil then
      out[k] = dashboard[key]
    end
  end

  return out
end

function M.setThemeConfig(prefs, path, values)
  if type(prefs) ~= "table" then return end
  if type(values) ~= "table" then return end

  prefs.dashboard = prefs.dashboard or {}
  local dashboard = prefs.dashboard
  if type(dashboard) ~= "table" then return end

  for k, v in pairs(values) do
    local key = themeConfigKey(path, k)
    if key then
      dashboard[key] = v
    end
  end
end

return M
