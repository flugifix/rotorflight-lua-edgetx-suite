local zone, options = ...

local runtimeChunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/service/runtime.lua", "t"))
local Runtime = runtimeChunk()

return Runtime.new(zone, options)
