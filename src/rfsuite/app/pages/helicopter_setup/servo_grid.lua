-- The servo direction and centre step as one page: a column per servo, so every servo is
-- visible while one is tested and centred. The columns come from steps/servos.lua.
local M = {}
function M.append(all, w, card, width, height, large, controlH, current)
  local L = w.L
  local cols = card.grid
  local n = math.max(1, #cols)
  local tiny = height < 260
  local gap = large and 10 or 4
  local lineH = large and 26 or tiny and 16 or 18
  local top = large and 130 or tiny and 44 or 48
  local cw = math.floor((width - 20 - gap * (n - 1)) / n)
  local function enabled() return w.canEdit == true and current() end
  local function act(fn) return function() if enabled() and w:usable() then fn() end end end
  local function label(x, y, lw, text, font)
    all[#all + 1] = { type = "label", x = x, y = y, w = lw, h = lineH, text = text, font = font or SMLSIZE,
      color = COLOR_THEME_PRIMARY1 }
    return all[#all]
  end
  local function button(x, y, bw, text, press, visible)
    all[#all + 1] = { type = "button", x = x, y = y, w = bw, h = controlH, text = text, press = act(press),
      active = enabled, visible = visible }
    return all[#all]
  end
  for k, c in ipairs(cols) do
    local x = 10 + (k - 1) * (cw + gap)
    local y = top
    if large then
      label(x, y, cw, c.title, MIDSIZE); y = y + 34
      label(x, y, cw, c.role); y = y + lineH
    else
      label(x, y, cw, c.title .. " " .. c.role); y = y + lineH
    end
    label(x, y, cw, c.live); y = y + lineH + 2
    if c.tail then
      label(x, y, cw, L.tailCentreOnly)
    else
      button(x, y, cw, L.servoTestUp, c.test, function() return not c.testing() end)
      local half = math.floor((cw - gap) / 2)
      button(x, y, half, L.answerUp, c.up, c.testing)
      button(x + half + gap, y, cw - half - gap, L.answerDown, c.down, c.testing)
    end
    y = y + controlH + 2
    label(x, y, cw, c.status); y = y + lineH + 2
    -- Centre: the value between nudge buttons; large screens also get the single steps.
    local steps = large and { -10, -1, 1, 10 } or { -10, 10 }
    local valueW = large and math.floor(cw * 0.28) or math.floor(cw * 0.4)
    local bw = math.floor((cw - valueW - gap * #steps) / #steps)
    local bx = x
    for i, delta in ipairs(steps) do
      if i == #steps / 2 + 1 then
        all[#all + 1] = { type = "label", x = bx, y = y + math.floor((controlH - lineH) / 2), w = valueW, h = lineH,
          text = c.centre, font = SMLSIZE, color = COLOR_THEME_PRIMARY1, align = CENTER }
        bx = bx + valueW + gap
      end
      local d = delta
      button(bx, y, bw, (d > 0 and "+" or "") .. d, function() c.nudge(d) end)
      bx = bx + bw + gap
    end
    y = y + controlH + 2
    label(x, y, cw, c.offset)
  end
end
return M
