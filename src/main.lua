-- TNS|RFSuite|TNE
if GREY_DEFAULT == nil then
  GREY_DEFAULT = COLOR_THEME_SECONDARY2
end

local originalLoadScript = loadScript
local chunkCache = {}
_G.rfsuite = _G.rfsuite or {}
_G.rfsuite.utils = _G.rfsuite.utils or {}
_G.rfsuite.utils.clearChunkCache = function()
  for k in pairs(chunkCache) do
    chunkCache[k] = nil
  end
  if _G.rfsuite and _G.rfsuite.clearAllModules then
    _G.rfsuite.clearAllModules()
  end
  _G.loadScript = originalLoadScript
end

_G.loadScript = function(path, mode)
  local cached = chunkCache[path]
  if cached then
    return cached
  end
  -- lib/require.lua publishes the load mode the whole suite uses; until it has been
  -- loaded, the mode the caller asked for still applies.
  local chunk, err = originalLoadScript(path, _G.rfsuite.loadMode or mode)
  if chunk then
    chunkCache[path] = chunk
  end
  return chunk, err
end

-- The wrapper above holds on to every chunk it loads, which is what makes a second visit to
-- a page cheap. A bulk pass over the tree wants the opposite and is given the loader that
-- does not cache (see lib/precompile.lua).
_G.rfsuite.utils.loadScriptUncached = originalLoadScript

-- Initialize module require memoizer
local requireChunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/require.lua", "t")
if requireChunk then
  requireChunk()
end

local chunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/ui/home.lua", "t"))
return chunk()


