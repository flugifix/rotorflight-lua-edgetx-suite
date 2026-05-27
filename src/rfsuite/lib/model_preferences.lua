local M = {}

local USER_ROOT = "/SCRIPTS/TOOLS/rfsuite.user"
local TOOLS_ROOT = "/SCRIPTS/TOOLS"

local function trim(s)
  local asString = tostring(s or "")
  asString = string.gsub(asString, "^%s+", "")
  asString = string.gsub(asString, "%s+$", "")
  return asString
end

local function parseValue(v)
  local t = trim(v)
  local lower = string.lower(t)
  if lower == "true" then return true end
  if lower == "false" then return false end
  local n = tonumber(t)
  if n ~= nil then return n end
  return t
end

local function serializeValue(v)
  local vt = type(v)
  if vt == "boolean" then
    return v and "true" or "false"
  end
  if vt == "number" then
    return tostring(v)
  end
  return tostring(v)
end

local function deepCopyTable(src)
  if type(src) ~= "table" then return src end
  local out = {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      out[k] = deepCopyTable(v)
    else
      out[k] = v
    end
  end
  return out
end

local function deepMerge(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      deepMerge(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

local function tablesEqual(a, b)
  if a == b then return true end
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end

  for k, v in pairs(a) do
    if not tablesEqual(v, b[k]) then
      return false
    end
  end
  for k, v in pairs(b) do
    if not tablesEqual(v, a[k]) then
      return false
    end
  end
  return true
end

local function loadFileAsString(path)
  local f = io.open(path, "r")
  if not f then return nil end

  local content = io.read(f, 2048)
  io.close(f)

  if content == nil or content == "" then return nil end
  return content
end

local function parseIni(content)
  local result = {}
  local section = nil

  if type(content) ~= "string" or content == "" then
    return result
  end

  for line in string.gmatch(content, "[^\r\n]+") do
    local normalized = trim(line)
    if normalized ~= "" and string.sub(normalized, 1, 1) ~= ";" and string.sub(normalized, 1, 1) ~= "#" then
      local sec = string.match(normalized, "^%[(.-)%]$")
      if sec then
        section = trim(sec)
        if result[section] == nil then
          result[section] = {}
        end
      else
        local k, v = string.match(normalized, "^([^=]+)=(.*)$")
        if k and v and section then
          result[section][trim(k)] = parseValue(v)
        end
      end
    end
  end

  return result
end

local function saveIni(path, data)
  local f, err = io.open(path, "w")
  if not f then return false, err end

  for section, values in pairs(data or {}) do
    if type(values) == "table" then
      io.write(f, "[" .. tostring(section) .. "]\n")
      for k, v in pairs(values) do
        io.write(f, tostring(k) .. "=" .. serializeValue(v) .. "\n")
      end
    end
  end

  io.close(f)
  return true
end

local function defaultModelPreferences()
  return {
    battery = {
      consumption_warning_percentage = 35
    },
    dashboard = {
      model_override = false,
      model_theme_preflight = "nil",
      model_theme_inflight = "nil",
      model_theme_postflight = "nil"
    },
    widgets = {}
  }
end

local function ensureDirs()
  if type(os) == "table" and type(os.mkdir) == "function" then
    pcall(os.mkdir, TOOLS_ROOT)
    pcall(os.mkdir, USER_ROOT)
  end
end

local function normalizeMcuId(mcuId)
  if mcuId == nil then return nil end
  local id = trim(tostring(mcuId))
  if id == "" then return nil end
  -- Keep filename safe even if an unexpected UID format appears.
  id = string.gsub(id, "[^%w_-]", "_")
  if id == "" then return nil end
  return id
end

local function ensureFileExists(path)
  local f = io.open(path, "r")
  if f then
    io.close(f)
    return true
  end

  local newFile, err = io.open(path, "w")
  if not newFile then return false, err end
  io.close(newFile)
  return true
end

function M.buildPath(mcuId)
  local safeId = normalizeMcuId(mcuId)
  if not safeId then return nil end
  return USER_ROOT .. "/" .. safeId .. ".ini"
end

function M.loadByMcuId(mcuId)
  local path = M.buildPath(mcuId)
  if not path then return nil, nil end

  ensureDirs()

  -- Ensure first-time setups always have a physical file on disk.
  local _ = ensureFileExists(path)

  local defaults = defaultModelPreferences()
  local onDisk = parseIni(loadFileAsString(path))
  local merged = deepCopyTable(onDisk)
  deepMerge(merged, defaults)

  if not tablesEqual(onDisk, merged) then
    local ok = saveIni(path, merged)
    if not ok then
      -- Save errors are non-fatal; caller still gets usable defaults+loaded values.
    end
  end

  return merged, path
end

function M.saveByMcuId(mcuId, prefs)
  local path = M.buildPath(mcuId)
  if not path then return false, "missing_mcu_id" end

  ensureDirs()

  local okTouch, touchErr = ensureFileExists(path)
  if not okTouch then
    return false, touchErr
  end

  local data = deepCopyTable(prefs or {})
  deepMerge(data, defaultModelPreferences())
  return saveIni(path, data)
end

return M
