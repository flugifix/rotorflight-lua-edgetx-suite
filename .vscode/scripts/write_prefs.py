import os

content = r"""local M = {}

-- Preferences stored as a Lua file, loaded via loadScript().
-- io.read(handle, ...) causes "attempt to compare number with nil" in the
-- EdgeTX Lua sandbox regardless of count type, so we avoid it entirely.
local PREF_PATH = "/SCRIPTS/TOOLS/rfsuite.user/preferences.lua"

local function defaultPreferences()
  return {
    general = {
      developer_tools = false,
      iconsize = 2,
      txbatt_type = 0,
      theme_loader = 1,
      hs_loader = 0,
      toolbar_timeout = 10
    }
  }
end

function M.getPath()
  return PREF_PATH
end

function M.load()
  local defaults = defaultPreferences()
  -- loadScript returns nil when the file does not exist or fails to compile.
  local chunk = loadScript(PREF_PATH, "t")
  if not chunk then
    return defaults, false
  end
  -- Run the chunk; on any runtime error fall back to defaults.
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return defaults, false
  end
  -- Merge defaults for any keys missing from the file.
  for section, values in pairs(defaults) do
    if type(result[section]) ~= "table" then
      result[section] = values
    else
      for k, v in pairs(values) do
        if result[section][k] == nil then
          result[section][k] = v
        end
      end
    end
  end
  return result, true
end

local function serializeLuaValue(v)
  local vt = type(v)
  if vt == "boolean" then return v and "true" or "false" end
  if vt == "number" then return tostring(v) end
  if vt == "string" then return string.format("%q", v) end
  return "nil"
end

function M.save(prefs)
  local f, err = io.open(PREF_PATH, "w")
  if not f then return false, err end

  local general = (prefs and prefs.general) or {}
  local content = "return {\n  general = {\n"
    .. "    developer_tools = " .. serializeLuaValue(general.developer_tools == true) .. ",\n"
    .. "    iconsize = "        .. serializeLuaValue(general.iconsize or 2)           .. ",\n"
    .. "    txbatt_type = "     .. serializeLuaValue(general.txbatt_type or 0)        .. ",\n"
    .. "    theme_loader = "    .. serializeLuaValue(general.theme_loader or 1)       .. ",\n"
    .. "    hs_loader = "       .. serializeLuaValue(general.hs_loader or 0)          .. ",\n"
    .. "    toolbar_timeout = " .. serializeLuaValue(general.toolbar_timeout or 10)   .. ",\n"
    .. "  },\n}\n"

  io.write(f, content)
  io.close(f)
  return true
end

return M
"""

target = os.path.join(os.path.dirname(__file__), '..', '..', 'src', 'rfsuite', 'lib', 'preferences.lua')
target = os.path.normpath(target)
with open(target, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)
print("OK:", target)
