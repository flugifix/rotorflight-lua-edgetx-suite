return {
  Viewport = assert(loadScript("/SCRIPTS/TOOLS/rfsuite/rfsuite/core/viewport.lua", "t"))(),
  BorderLayout = assert(loadScript("/SCRIPTS/TOOLS/rfsuite/rfsuite/layouts/border.lua", "t"))(),
  GridLayout = assert(loadScript("/SCRIPTS/TOOLS/rfsuite/rfsuite/layouts/grid.lua", "t"))(),
  FlowLayout = assert(loadScript("/SCRIPTS/TOOLS/rfsuite/rfsuite/layouts/flow.lua", "t"))()
}
