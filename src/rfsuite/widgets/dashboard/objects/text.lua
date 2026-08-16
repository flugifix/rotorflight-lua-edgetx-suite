local Wrapper = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require) or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local chunk = loadScript(fullPath, "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local utils = requireModule("widgets/dashboard/objects/common.lua")
local themeCommon = requireModule("widgets/dashboard/themes/default/common.lua")

local folder = "widgets/dashboard/objects/text/"
local renders = {}
local missingRenders = {}

local function getRender(subtype)
  local key = subtype or "telemetry"
  if renders[key] then return renders[key] end
  if missingRenders[key] then return nil end

  -- Decorative background boxes use subtype="text" and do not need a subrenderer.
  if key == "text" then
    missingRenders[key] = true
    return nil
  end

  local mod = requireModule(folder .. key .. ".lua")
  if mod then
    renders[key] = mod
    return mod
  end
  missingRenders[key] = true
  return nil
end

function Wrapper.render(nodes, rect, box, state)
  if not utils then
    utils = requireModule("widgets/dashboard/objects/common.lua")
  end
  if not utils then return end

  utils.drawContainer(nodes, rect, box, state)

  local render = getRender(box and box.subtype)
  if render and type(render.render) == "function" then
    if not themeCommon then
      themeCommon = requireModule("widgets/dashboard/themes/default/common.lua")
    end
    if themeCommon then
      render.render(nodes, rect, box, state, themeCommon, utils)
    end
  else
    local title = box and box.title or ""
    local val = box and box.value or "--"
    local color = (box and box.textcolor) or (themeCommon and themeCommon.resolveThemeColor("textcolor", box and box.textcolor)) or WHITE
    local align = (box and box.valuealign) or (box and box.titlealign) or CENTER
    local font = (box and box.font) or MIDSIZE
    if type(font) == "function" then
      font = font(box, state)
    end
    utils.pushLabel(nodes, rect.x + 4, utils.defaultValueY(rect, box), rect.w - 8, tostring(val), color, align, font)
  end
end

return Wrapper
