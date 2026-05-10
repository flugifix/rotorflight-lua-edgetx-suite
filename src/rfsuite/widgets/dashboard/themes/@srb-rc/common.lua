local Common = {}

local function merge(dst, src)
  if type(src) ~= "table" then return dst end
  for key, value in pairs(src) do
    dst[key] = value
  end
  return dst
end

function Common.batteryBar(source, overrides)
  local box = {
    type = "gauge",
    subtype = "bar",
    source = source or "smartfuel",
    unit = "%",
    min = 0,
    max = 100,
    transform = "floor",
    valuealign = CENTER,
    valuepaddingtop = -22,
    titlecolor = WHITE,
    textcolor = WHITE,
    bgcolor = BLACK,
    fillbgcolor = BLACK,
    thresholds = {
      { value = 10, fillcolor = RED },
      { value = 45, fillcolor = YELLOW },
      { value = 100, fillcolor = GREEN }
    }
  }

  return merge(box, overrides)
end

return Common
