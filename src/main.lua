-- TNS|RFSuite|TNE
local originalLoadScript = loadScript
local chunkCache = {}
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

local chunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/ui/home.lua", "t"))
return chunk()

