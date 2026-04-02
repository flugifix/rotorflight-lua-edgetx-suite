local Wrapper = {}

local utils = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/common.lua", "t"))()
local themeCommon = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/default/common.lua", "t"))()

local folder = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/dial/"
local renders = {}

local function getRender(subtype)
  local key = subtype or "image"
  if renders[key] then return renders[key] end
  local chunk = loadScript(folder .. key .. ".lua", "t")
  if not chunk then return nil end
  local ok, render = pcall(chunk)
  if not ok or type(render) ~= "table" then return nil end
  renders[key] = render
  return render
end

function Wrapper.render(nodes, rect, box, state)
  utils.drawContainer(nodes, rect, box, state)
  local render = getRender(box and box.subtype)
  if render and type(render.render) == "function" then
    render.render(nodes, rect, box, state, themeCommon, utils)
  end
end

return Wrapper
