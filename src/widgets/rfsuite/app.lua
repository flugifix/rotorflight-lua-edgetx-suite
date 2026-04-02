local zone, options = ...

local runtimeChunk = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/runtime.lua", "t"))
local Runtime = runtimeChunk()

return Runtime.new(zone, options)
