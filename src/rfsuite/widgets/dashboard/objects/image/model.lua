local Render = {}

local modelImageCache = {}

local function resolveModelImage(fblModelName)
  local cacheKey = tostring(fblModelName or "")
  if model and type(model.getInfo) == "function" then
    local info = model.getInfo()
    if info and info.name then
      cacheKey = cacheKey .. "|" .. tostring(info.name) .. "|" .. tostring(info.bitmap or "")
    end
  end

  if modelImageCache[cacheKey] ~= nil then
    return modelImageCache[cacheKey].imageFile, modelImageCache[cacheKey].modelNameText
  end

  local imageFile = nil
  local modelNameText = fblModelName
  
  -- 1. Try to load image based on FBL model name
  if fblModelName and fblModelName ~= "" then
    local path = "/IMAGES/" .. fblModelName .. ".png"
    local f = io.open(path, "r")
    if f then
      io.close(f)
      imageFile = path
    else
      path = "/IMAGES/" .. fblModelName .. ".PNG"
      f = io.open(path, "r")
      if f then
        io.close(f)
        imageFile = path
      end
    end
  end

  -- 2. Fallback to current EdgeTX model image
  if not imageFile then
    if model and type(model.getInfo) == "function" then
      local info = model.getInfo()
      if info and info.bitmap and info.bitmap ~= "" then
        local path = "/IMAGES/" .. info.bitmap
        local f = io.open(path, "r")
        if f then
          io.close(f)
          imageFile = path
        end
      end
      if not modelNameText or modelNameText == "" then
        modelNameText = info.name
      end
    end
  end

  -- 3. Fallback to logo.png
  if not imageFile then
    imageFile = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png"
  end

  modelImageCache[cacheKey] = { imageFile = imageFile, modelNameText = modelNameText }
  return imageFile, modelNameText
end

function Render.render(nodes, rect, box, state, themeCommon, utils)
  local fblModelName = nil
  if type(_G) == "table" and _G.rfsuite and _G.rfsuite.session then
    fblModelName = _G.rfsuite.session.modelName
  end

  local imageFile, modelNameText = resolveModelImage(fblModelName)

  -- We need space for the text at the bottom
  local textH = 22
  local drawH = math.max(18, rect.h - 8 - textH)
  local drawW = math.max(18, rect.w - 8)

  -- Basic aspect ratio handling (defaulting to logo aspect if we don't know the exact image size)
  -- For custom images we use a square box to fit most custom model images, 
  -- but LVGL image widget handles its own aspect scaling within the given w/h bounds usually.
  local aspect = 1.0
  if imageFile == "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png" then
    aspect = 416 / 84
  end

  local imgH = drawH
  local imgW = math.floor(imgH * aspect)
  if imgW > drawW then
    imgW = drawW
    imgH = math.floor(imgW / aspect)
  end

  nodes[#nodes + 1] = {
    type = "image",
    x = rect.x + math.max(0, math.floor((rect.w - imgW) / 2)),
    y = rect.y + 4 + math.max(0, math.floor((drawH - imgH) / 2)),
    w = imgW,
    h = imgH,
    file = imageFile
  }

  local displayTitle = modelNameText or "Rotorflight"
  
  if utils and type(utils.pushLabel) == "function" then
    utils.pushLabel(
      nodes,
      rect.x + 4,
      rect.y + rect.h - textH,
      rect.w - 8,
      displayTitle,
      box.titlecolor or COLOR_THEME_PRIMARY2,
      CENTER,
      SMLSIZE
    )
  end
end

return Render
