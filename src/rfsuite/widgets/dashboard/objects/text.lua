local Wrapper = {}

local utils = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/common.lua", "t"))()
local themeCommon = assert(loadScript("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/default/common.lua", "t"))()

local folder = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/text/"
local renders = {}

local function getRender(subtype)
  local key = subtype or "telemetry"
  local cached = renders[key]
  if cached ~= nil then
    return cached ~= false and cached or nil
  end
  local chunk = loadScript(folder .. key .. ".lua", "t")
  if not chunk then
    renders[key] = false
    return nil
  end
  local ok, render = pcall(chunk)
  if not ok or type(render) ~= "table" then
    renders[key] = false
    return nil
  end
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
