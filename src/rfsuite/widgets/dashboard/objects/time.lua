local Wrapper = {}

local function loadModule(path, globalKey)
  if globalKey and _G[globalKey] then return _G[globalKey] end

  -- Drosselung: Maximal ein Skript-Load pro Tick im gesamten Dashboard-System
  local now = 0
  if type(getTime) == "function" then now = getTime() / 100 end
  _G.__rfsuite_last_ui_load = _G.__rfsuite_last_ui_load or 0
  if _G.__rfsuite_last_ui_load == now then return nil end

  local chunk = loadScript(path, "t")
  if not chunk then return nil end

  _G.__rfsuite_last_ui_load = now
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

local folder = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/objects/time/"
local renders = {}

local function getRender(subtype)
  local key = subtype or "time"
  if renders[key] then return renders[key] end

  local mod = loadModule(folder .. key .. ".lua", "__rfsuite_time_render_" .. key)
  if mod then
    renders[key] = mod
    return mod
  end
  return nil
end

function Wrapper.render(nodes, rect, box, state)
  local utils = getUtils()
  if not utils then return end

  utils.drawContainer(nodes, rect, box, state)

  local render = getRender(box and box.subtype)
  if render and type(render.render) == "function" then
    local themeCommon = getThemeCommon()
    if themeCommon then
      render.render(nodes, rect, box, state, themeCommon, utils)
    end
  end
end

return Wrapper
