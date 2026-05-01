local Wrapper = {}

local function loadModule(path, globalKey)
  if globalKey and _G[globalKey] then return _G[globalKey] end
  
  local chunk = loadScript(path, "t")
  if not chunk then return nil end
  
  local ok, mod = pcall(chunk)
  if ok and type(mod) == "table" then
    if globalKey then _G[globalKey] = mod end
    return mod
  end
  return nil
end

local function getUtils()
  return loadModule("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/common.lua", "__rfsuiteObjectsCommonModule")
end

local function getThemeCommon()
  return loadModule("/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/themes/default/common.lua", "__rfsuiteThemeDefaultCommonModule")
end

local folder = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/text/"
local renders = {}

local function getRender(subtype)
  local key = subtype or "telemetry"
  if renders[key] then return renders[key] end
  
  local mod = loadModule(folder .. key .. ".lua", "__rfsuite_text_render_" .. key)
  if mod then
    renders[key] = mod
    return mod
  end
  return nil
end

function Wrapper.render(nodes, rect, box, state)
  local utils = getUtils()
  local themeCommon = getThemeCommon()
  if not utils or not themeCommon then return end
  
  utils.drawContainer(nodes, rect, box, state)
  
  local render = getRender(box and box.subtype)
  if render and type(render.render) == "function" then
    render.render(nodes, rect, box, state, themeCommon, utils)
  end
end

return Wrapper
