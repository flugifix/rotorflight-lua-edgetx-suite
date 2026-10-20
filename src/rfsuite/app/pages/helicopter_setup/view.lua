-- Compact illustrated tasks use a drawing beside the controls. Large displays
-- have a separate instruction column. The scene is published four objects per pass.
local M = {}
local function label(x, y, width, text, font)
  return { type = "label", x = x, y = y, w = width, text = text, font = font or SMLSIZE, color = COLOR_THEME_PRIMARY1 }
end
function M.new(w, ctx, diagrams)
  local width, height = ctx.w, ctx.h
  local large = width >= 700
  local compact = width < 400 and {
    [w.L.servosUnplugged]=w.L.shortUnplugged,[w.L.cyclicServos]=w.L.shortCyclicServos,
    [w.L.swashType]=w.L.shortSwash, [w.L.rotorDirection]=w.L.shortRotation,
    [w.L.centreOffset]=w.L.shortOffset, [w.L.armCentred]=w.L.shortArm,
    [w.L.servo1Trim]=w.L.shortTrim1, [w.L.servo2Trim]=w.L.shortTrim2, [w.L.servo3Trim]=w.L.shortTrim3
  } or {}
  local controlH = large and 44 or width >= 480 and 32 or 26
  local rowY = large and 108 or height <= 272 and 76 or 88
  local rowH = large and 52 or math.min(controlH+6, math.floor((height-2*controlH-31-rowY)/3))
  local all = {}
  local title = w.L.steps[w.step] or w.L.name
  all[#all + 1] = { type = "rectangle", x = 0, y = 0, w = width, h = height, filled = true, color = COLOR_THEME_PRIMARY3 }
  all[#all + 1] = label(10, 4, width - 54, string.format("%d/19  %s", w.step, title), large and MIDSIZE or SMLSIZE)
  local function button(x, y, bw, text, press, active, kind, release)
    all[#all + 1] = { type = kind or "button", x = x, y = y, w = bw, h = controlH, text = text,
      press = press, release = release, active = active }
  end
  -- Back is deliberately first in focus order.
  button(8, height-controlH-6, math.floor(width * 0.25), w.L.back, function() w:back() end,
    function() return not w.transition end)
  button(width-controlH-6, 2, controlH, "?", function()
    local current = w.cards and w.cards[w.card]
    local message = current and current.detail.."\n\n"..w.L.help or w.L.help
    if w.trialDetails then message=message.."\n"..w.trialDetails end
    if w.openHelp then w.openHelp(message, w.L.name) end
  end)
  local card = w.cards and w.cards[w.card]
  if w.confirmExit then
    all[#all + 1] = label(12, 48, width-24, w.L.exitHint)
    button(12, 100, math.floor(width/2)-18, w.L.saveExit, function() w:save(function() w:close() end) end)
    button(math.floor(width/2)+6, 100, math.floor(width/2)-18, w.L.discardExit, function() w:discard() end)
  elseif w.error then
    all[#all + 1] = label(12, 48, width-24, w.L.failed)
    all[#all + 1] = label(12, 76, width-24, w.error)
    button(12, 116, width-24, w.L.retry, function() w:retry() end)
  elseif card then
    local illustrated = card.art ~= nil
    local formX = large and math.floor(width * 0.43) or illustrated and math.floor(width * 0.35)+4 or 10
    local formW = width-formX-(large and 16 or 10)
    all[#all + 1] = label(10, large and 50 or 27, large and formX-24 or width-20, card.title, large and MIDSIZE or SMLSIZE)
    all[#all + 1] = label(10, large and 94 or 48, large and formX-30 or width-20, card.detail)
    if not large then all[#all].h = rowY - 52 end
    if illustrated then
      local artY = large and 204 or rowY+4
      local artH = large and 174 or height-controlH-35-artY
      diagrams.append(all, w, card, 6, artY, formX-18, artH)
    end
    for i, r in ipairs(card.rows) do
      local y = rowY + (i-1)*rowH
      local function enabled() return w.canEdit == true and (not r.enabled or r.enabled()) end
      if r.kind == "button" or r.kind == "hold" then
        button(formX, y, formW, r.label, function() if enabled() and w:usable() then r.press() end end, enabled,
          r.kind == "hold" and "momentaryButton" or "button", r.release)
      else
        local editW = large and 190 or math.floor(formW * 0.48)
        all[#all + 1] = label(formX, y+3, formW-editW-8, illustrated and compact[r.label] or r.label)
        if r.kind == "value" then
          all[#all + 1] = label(formX+formW-editW, y+3, editW, function() return tostring(r.get() or "--") end)
        elseif r.kind == "choice" then
          all[#all + 1] = { type = "choice", x = formX+formW-editW, y = y, w = editW, h = controlH,
            title = r.label, values = r.values, get = r.get,
            set = function(v) if enabled() and w:usable() then r.set(v) end end, active = enabled }
        else
          all[#all + 1] = { type = "numberEdit", x = formX+formW-editW, y = y, w = editW, h = controlH,
            min = r.min, max = r.max, get = r.get,
            set = function(v) if enabled() and w:usable() then r.set(v) end end,
            display = function(v)
              if r.divisor then return string.format("%.1f", v / r.divisor) end
              return tostring(v)
            end, active = enabled }
        end
      end
    end
    local function nextText() return w.trial and w.trial.success and w.L.saveReboot or w.step == 10 and w.rebootPending and w.L.reboot or w.step == 19 and w.L.finish or
      w.card == #w.cards and w.L.saveNext or w.L.continue end
    button(width-math.floor(width*0.42)-8, height-controlH-6, math.floor(width*0.42), nextText,
      function() w:next() end, function() return w.canNext == true end)
    all[#all + 1] = label(math.floor(width*0.27)+8, height-controlH, math.floor(width*0.28)-20,
      string.format("%d/%d", w.card, #w.cards))
  end
  all[#all + 1] = label(10, height-controlH-(large and 40 or 27), width-20, function() return w.legacyHold and w.L.persistent or w.message or "" end)
  local job = { all = all, children = {}, index = 1 }
  function job:step()
    for _ = 1, 4 do
      local item = self.all[self.index]
      if not item then self.done = true; return true end
      self.children[#self.children + 1] = item; self.index = self.index + 1
    end
    return false
  end
  return job
end
return M
