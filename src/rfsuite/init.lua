return {
  Viewport = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/core/viewport.lua", "t"))(),
  BorderLayout = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/layouts/border.lua", "t"))(),
  GridLayout = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/layouts/grid.lua", "t"))(),
  FlowLayout = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/layouts/flow.lua", "t"))()
}
