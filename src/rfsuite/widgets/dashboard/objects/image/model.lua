local Render = {}

function Render.render(nodes, rect)
  local logoFile = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png"
  local logoAspect = 416 / 84
  local availW = math.max(18, rect.w - 8)
  local availH = math.max(18, rect.h - 8)

  local drawW = availW
  local drawH = math.floor(drawW / logoAspect)
  if drawH > availH then
    drawH = availH
    drawW = math.floor(drawH * logoAspect)
  end

  nodes[#nodes + 1] = {
    type = "image",
    x = rect.x + math.max(0, math.floor((rect.w - drawW) / 2)),
    y = rect.y + math.max(0, math.floor((rect.h - drawH) / 2)),
    w = drawW,
    h = drawH,
    file = logoFile
  }
end

return Render
