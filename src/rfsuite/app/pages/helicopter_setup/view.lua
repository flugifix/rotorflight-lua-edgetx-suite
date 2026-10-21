-- Compact illustrated tasks use a drawing beside the controls. Large displays
-- have a separate instruction column. The scene is published four objects per pass.
local M = {}
local function label(x, y, width, text, font)
  return { type = "label", x = x, y = y, w = width, text = text, font = font or SMLSIZE, color = COLOR_THEME_PRIMARY1 }
end
function M.new(w, ctx, diagrams)
  local width, height = ctx.w, ctx.h
  local large = width >= 700
  if w.attitudeView then w.attitudeView.valid=false;w.attitudeView=nil end
  local card = w.cards and w.cards[w.card]
  local attitudeCard=card and card.art=="attitude"
  local compact = width < 400 and {
    [w.L.servosUnplugged]=w.L.shortUnplugged,[w.L.cyclicServos]=w.L.shortCyclicServos,
    [w.L.swashType]=w.L.shortSwash, [w.L.rotorDirection]=w.L.shortRotation,
    [w.L.measuredDegrees]=w.L.shortMeasured, [w.L.ratePercent]=w.L.shortRate,
    [w.L.centreOffset]=w.L.shortOffset, [w.L.armCentred]=w.L.shortArm,
    [w.L.servo1Trim]=w.L.shortTrim1, [w.L.servo2Trim]=w.L.shortTrim2, [w.L.servo3Trim]=w.L.shortTrim3
  } or {}
  local controlH = large and 44 or width >= 480 and 32 or 26
  local rowY = large and 108 or height <= 272 and 76 or 88
  local rowH = large and 52 or math.min(controlH+6, math.floor((height-2*controlH-31-rowY)/3))
  local all = {}
  local title = w.historyMode and w.L.historyTitle or (w.overview or w.modelPreparationCard or w.recoveryCard) and w.L.name or string.format("%d/19  %s", w.step, w.L.steps[w.step] or w.L.name)
  if attitudeCard then title=string.format("%d/19  %s",w.step,card.title) end
  all[#all + 1] = { type = "rectangle", x = 0, y = 0, w = width, h = height, filled = true, color = COLOR_THEME_PRIMARY2 }
  if w.historyMode or w.overview or w.confirmExit or not w.requestSteps then
    all[#all + 1] = label(10, 4, width - 54, title, large and MIDSIZE or SMLSIZE)
  end
  local function button(x, y, bw, text, press, active, kind, release)
    all[#all + 1] = { type = kind or "button", x = x, y = y, w = bw, h = controlH, text = text,
      press = press, release = release, active = active }
  end
  -- Back is deliberately first in focus order.
  button(8, height-controlH-6, math.floor(width * 0.25), w.L.back, function() w:back() end,
    function() return not w.transition end)
  if not w.historyMode and not w.overview and not w.confirmExit and w.requestSteps then
    button(8, 2, width-controlH-20, title, function() w:requestSteps() end,
      function() return w.canEdit == true end)
    all[#all].h, all[#all].font = large and 44 or 24, large and MIDSIZE or SMLSIZE
  end
  button(width-controlH-6, 2, controlH, "?", function()
    local current = w.cards and w.cards[w.card]
    local detail = w.overview and w.L.stepMenuHint or current and current.detail
    local focused = w.modelPreparationCard or w.historyMode
    local message = detail and (focused and detail or detail.."\n\n"..w.L.help) or w.L.help
    if w.trialDetails then message=message.."\n"..w.trialDetails end
    if not focused and w.historyHint then message=message.."\n\n"..w.historyHint end
    if not focused and w.prerequisiteDetails then message=message.."\n\n"..w.prerequisiteDetails end
    if w.openHelp then w.openHelp(message, w.L.name) end
  end)
  if w.disconnectExit then
    all[#all+1]=label(12,48,width-24,w.L.disconnectedExitHint);all[#all].h=100
    button(12,160,width-24,w.L.powerOffLeave,function() w:leaveDisconnected() end)
  elseif w.confirmExit then
    local leavingStep=w.exitToSteps or w.backTarget
    all[#all + 1] = label(12, 48, width-24, leavingStep and w.L.leaveStepHint or w.L.exitHint)
    button(12, 100, math.floor(width/2)-18, leavingStep and w.L.saveChanges or w.L.saveExit,
      function() if w.resolveExit then w:resolveExit(true) else w:save(function() w:close() end) end end)
    button(math.floor(width/2)+6, 100, math.floor(width/2)-18, leavingStep and w.L.discardChanges or w.L.discardExit,
      function() if w.resolveExit then w:resolveExit(false) else w:discard() end end)
  elseif w.error then
    all[#all + 1] = label(12, 48, width-24, w.statusFailure and w.L.statusUnavailable or next(w.dirty) and w.L.failed or w.L.failedClean)
    all[#all].h=36
    all[#all + 1] = label(12, 88, width-24, w.error)
    if w.statusFailure then
      all[#all+1]=label(12,116,width-24,w.L.statusWaitHint);all[#all].h=50
    end
    button(12, w.statusFailure and 172 or 132, width-24, w.L.retry, function() w:retry() end)
  elseif w.historyFailure then
    all[#all+1]=label(12,48,width-24,w.L.historySaveFailed)
    button(12,100,width-24,w.L.retry,function() w.historyRetry() end)
    button(12,100+rowH,width-24,w.historyAllowSkip and w.L.historyContinue or w.L.back,function() w.historySkip() end)
  elseif w.overview then
    all[#all + 1] = label(10, large and 55 or 30, width-20, w.L.chooseStep, large and MIDSIZE or SMLSIZE)
    all[#all + 1] = label(10, large and 94 or 48, large and math.floor(width*0.4)-24 or width-20, w.L.stepMenuHint)
    if not large then all[#all].h = rowY-52 end
    local x = large and math.floor(width*0.43) or 10
    local bw = width-x-10
    all[#all+1] = { type="choice",x=x,y=rowY,w=bw,h=controlH,title=w.L.chooseStep,
      values=w.L.steps,get=function() return w.selectedStep end,
      set=function(v) if w:usable() and v>=1 and v<=19 then w.selectedStep=v end end,
      active=function() return w.canEdit == true end }
    button(x,rowY+rowH,bw,w.L.startStep,function() w:startStep(w.selectedStep) end,
      function() return w.canEdit == true end)
    button(x,rowY+2*rowH,bw,w.L.completeSetup,function() w:startStep(1,true) end,
      function() return w.canEdit == true end)
    button(x,rowY+3*rowH,bw,w.L.saveReboot,function() if w:usable() then w:reboot() end end,
      function() return w.canEdit == true and w.rebootPending == true end)
    all[#all].visible=function() return w.rebootPending == true end
  elseif card then
    -- Native LVGL keeps sweeping this tree while its replacement is staged.
    -- Navigation clears w.cards before the next scene can be published.
    local cards, cardIndex, step = w.cards, w.card, w.step
    local finalCard = cardIndex == #cards
    local simpleNext = w.modelPreparationCard or w.preparationCard or w.recoveryCard
    local restartNext = w.entryRebootGate
    local function current()
      return w.cards == cards and w.card == cardIndex and not w.confirmExit and not w.overview
        and not w.historyFailure and not w.error and not w.disconnectExit
    end
    local illustrated = card.art ~= nil
    local formX = large and math.floor(width * 0.43) or illustrated and math.floor(width * 0.35)+4 or 10
    if attitudeCard then formX=large and math.floor(width*.64) or 10;rowY=large and 166 or height-3*controlH-10 end
    local formW = width-formX-(large and 16 or 10)
    if attitudeCard then
      all[#all+1]=label(10,large and 58 or 30,width-20,w.L.orientationModelHint)
      all[#all].h=large and 32 or 23
      diagrams.append(all,w,card,10,large and 108 or 56,
        large and formX-26 or width-20,large and height-controlH-168 or rowY-68)
    else
    all[#all + 1] = label(10, large and 50 or 27, large and formX-24 or width-20, card.title, large and MIDSIZE or SMLSIZE)
    all[#all + 1] = label(10, large and 94 or 48, large and formX-30 or width-20, card.summary or card.detail)
    all[#all].h = large and (illustrated and 98 or height-controlH-154) or rowY-52
    if illustrated then
      local artY = large and 204 or rowY+4
      local artH = large and 174 or height-controlH-35-artY
      diagrams.append(all, w, card, 6, artY, formX-18, artH)
    end
    end
    for i, r in ipairs(card.rows) do
      local y = rowY + (i-1)*rowH
      local function enabled() return w.canEdit == true and current() and (not r.enabled or r.enabled()) end
      if r.kind == "button" or r.kind == "hold" then
        button(formX, y, formW, r.label, function() if enabled() and w:usable() then r.press() end end, enabled,
          r.kind == "hold" and "momentaryButton" or "button", r.release)
      else
        local editW = large and 190 or math.floor(formW * 0.48)
        if attitudeCard and large then
          all[#all+1]=label(formX,y-34,formW,r.label)
          editW=formW
        else
        all[#all + 1] = label(formX, y+3, formW-editW-8, illustrated and compact[r.label] or r.label)
        end
        if r.kind == "value" then
          all[#all + 1] = label(formX+formW-editW, y+3, editW, function() return tostring(r.get() or "--") end)
          all[#all].h=controlH
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
    local function nextText() return simpleNext and w.L.continue or restartNext and w.L.reboot or w.trial and w.trial.success and w.L.saveReboot or step == 10 and w.rebootPending and w.L.reboot or step == 19 and not w.singleStep and w.L.finish or
      finalCard and (w.singleStep and (next(w.dirty) and w.L.saveStep or (w.returnToSuite and w.L.backToSuite or w.L.backToSteps)) or w.L.saveNext) or w.L.continue end
    if not w.historyMode then
    button(width-math.floor(width*0.42)-8, height-controlH-6, math.floor(width*0.42), nextText,
      function() if current() then w:next() end end, function() return w.canNext == true and current() end)
    all[#all + 1] = label(math.floor(width*0.27)+8, height-controlH, math.floor(width*0.28)-20,
      string.format("%d/%d", w.card, #w.cards))
    end
  end
  all[#all + 1] = label(10, height-controlH-(large and 40 or 27), width-20,
    function() return w.feedbackText and w:feedbackText() or w.legacyHold and w.L.persistent or w.message or "" end)
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
