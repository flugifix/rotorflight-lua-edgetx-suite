-- lib/require.lua
-- Module and singleton memoizer for EdgeTX RFSuite.
--
-- Prevents repeated disk reads, bytecode compilation, and redundant
-- module execution of shared libraries and singletons across the suite.

local BASE_PATH = "/SCRIPTS/TOOLS/rfsuite-core/"

_G.rfsuite = _G.rfsuite or {}
_G.rfsuite.modules = _G.rfsuite.modules or {}

-- Load mode for every script the suite loads.
--
-- EdgeTX compiles a source file to a .luac next to it whenever it loads one that is newer
-- than its bytecode, and it reads that bytecode back only when the mode allows binary ("b").
-- Every call site in the suite asks for "t", so each source is compiled and written out once
-- and the .luac is then never loaded again: the cost of the write without the benefit of the
-- cache. "x" turns the write off.
_G.rfsuite.loadMode = "tx"

local modules = _G.rfsuite.modules

local function normalizePath(path)
  if type(path) ~= "string" or path == "" then
    return path
  end
  if string.sub(path, 1, #BASE_PATH) == BASE_PATH then
    return path
  end
  if string.sub(path, 1, 1) == "/" then
    return path
  end
  return BASE_PATH .. path
end

local function requireModule(path, forceReload)
  local fullPath = normalizePath(path)
  if not fullPath then return nil end

  if not forceReload and modules[fullPath] ~= nil then
    return modules[fullPath]
  end

  local chunk, err = loadScript(fullPath, _G.rfsuite.loadMode)
  if not chunk then
    if type(err) == "string" then
      print("[require] Failed to load " .. tostring(fullPath) .. ": " .. err)
    end
    return nil, err
  end

  local ok, result = pcall(chunk)
  if not ok then
    print("[require] Error executing " .. tostring(fullPath) .. ": " .. tostring(result))
    return nil, result
  end

  -- If module returns nothing/nil, store true as sentinel
  local instance = (result == nil) and true or result
  modules[fullPath] = instance

  return instance
end

local function clearModule(path)
  local fullPath = normalizePath(path)
  if fullPath then
    modules[fullPath] = nil
  end
end

local function clearAllModules()
  for k in pairs(modules) do
    modules[k] = nil
  end
end

_G.rfsuite.require = requireModule
_G.rfsuite.clearModule = clearModule
_G.rfsuite.clearAllModules = clearAllModules

return requireModule
