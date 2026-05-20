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
local missingRenders = {}
local cachedUtils = nil
local cachedThemeCommon = nil

local function getRender(subtype)
  local key = subtype or "telemetry"
  if renders[key] then return renders[key] end
  if missingRenders[key] then return nil end

  -- Decorative background boxes use subtype="text" and do not need a subrenderer.
  if key == "text" then
    missingRenders[key] = true
    return nil
  end
  
  local mod = loadModule(folder .. key .. ".lua", "__rfsuite_text_render_" .. key)
  if mod then
    renders[key] = mod
    return mod
  end
  missingRenders[key] = true
  return nil
end

function Wrapper.render(nodes, rect, box, state)
  local utils = cachedUtils or getUtils()
  if utils then
    cachedUtils = utils
  end

  local themeCommon = cachedThemeCommon or getThemeCommon()
  if themeCommon then
    cachedThemeCommon = themeCommon
  end

  if not utils or not themeCommon then return end
  
  utils.drawContainer(nodes, rect, box, state)
  
  local render = getRender(box and box.subtype)
  if render and type(render.render) == "function" then
    local ok, err = pcall(render.render, nodes, rect, box, state, themeCommon, utils)
    if not ok then
      if type(err) == "string" and string.find(err, "CPU limit", 1, true) then
        return
      end
      error(err)
    end
  end
end

return Wrapper
