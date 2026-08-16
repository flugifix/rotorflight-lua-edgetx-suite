-- TNS|RFSuite|TNE
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
  local chunk, err = originalLoadScript(path, mode)
  if chunk then
    chunkCache[path] = chunk
  end
  return chunk, err
end

-- Initialize module require memoizer
local requireChunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/require.lua", "t")
if requireChunk then
  requireChunk()
end

local chunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/ui/home.lua", "t"))
return chunk()


