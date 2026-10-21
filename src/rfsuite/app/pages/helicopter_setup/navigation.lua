-- Complete setup and individual steps share one controller and cleanup path.
local M = {}
function M.attach(w, ctx)
  w.overview, w.selectedStep = true, 1
  local menu = ctx and ctx.menu
  local id = menu and menu.getCurrentMenuId and menu.getCurrentMenuId()
  local entry = type(id) == "string" and tonumber(string.match(id,"^helicopter_setup_step_(%d%d)_page$"))
  if id == "helicopter_setup_page" or id == "helicopter_setup_history_page" or entry and entry>=1 and entry<=19 then
    w.returnToSuite, w.overview = true, nil
    w.historyMode = id == "helicopter_setup_history_page"
    w.step, w.selectedStep = entry or 1, entry or 1
    w.singleStep = id ~= "helicopter_setup_page"
  end
  if ctx then
    w.modelPreparationRequired = not w.historyMode
    local info = type(model)=="table" and type(model.getInfo)=="function" and model.getInfo()
    w.activeModelName = type(info)=="table" and type(info.name)=="string" and info.name~="" and info.name or w.L.unknown
  end
  function w:showSteps()
    self:release()
    self.overview, self.singleStep, self.confirmExit, self.exitToSteps = true, nil, nil, nil
    self.cards, self.commit, self.validate, self.onLive, self.buildRequested = nil, nil, nil, nil, nil
    self.checks, self.preparationDone, self.preparationCard = {}, nil, nil
    self.message = self.rebootPending and self.L.pendingReboot or self.L.ready
    self:rebuild()
  end
  function w:requestSteps()
    if not self.ready or self.transition then return end
    self:release()
    if next(self.dirty) then
      self.confirmExit, self.exitToSteps = true, not self.returnToSuite; self:rebuild()
    elseif self.returnToSuite then self:close()
    else self:showSteps() end
  end
  function w:startStep(index, complete)
    if not self:usable() or not index or index < 1 or index > 19 or index % 1 ~= 0 then return end
    if index > 10 and self.rebootPending then self.message = self.L.pendingReboot; return end
    self.overview, self.singleStep, self.selectedStep = nil, not complete, index
    self.checks, self.preparationDone, self.preparationCard = {}, nil, nil
    self:navigate(index, 1)
  end
  function w:standalonePreparation()
    if not self.singleStep then return false end
    return (self.step > 1 and self.step < 10) or (self.step >= 13 and self.step <= 16) or
      (self.step == 17 and not self:motorised()) or self.step == 18
  end
  function w:buildModelPreparation()
    if self.recoveryRequired then
      self.cards={self:cardDef(self.L.recoveryTitle,self.L.recoveryHint,{
        self:check("recoveryPowerCycle",self.L.fcPowerCycled)
      })}
      self.cards[1].summary=self.L.recoveryIntro
      self.card,self.recoveryCard=1,true;return true
    end
    if not self.modelPreparationRequired or self.modelPreparationDone then return false end
    self.cards={self:cardDef(self.L.modelPreparationTitle,self.L.modelPreparationIntro.."\n"..self.L.modelPreparationHint.."\n"..
      self.L.activeModel..": "..self.activeModelName,{
      self:value(self.L.activeModel,function() return self.activeModelName end),
      self:check("modelReady",self.L.modelChecked)
    })}
    self.cards[1].summary=self.L.modelPreparationIntro
    self.card,self.modelPreparationCard=1,true
    return true
  end
  function w:buildPreparation()
    if self:standalonePreparation() and not self.preparationDone then
      local rows = { self:check("blades", self.L.bladesRemoved) }
      rows[2] = self.step < 10 and self:check("unplugged", self.L.servosUnplugged) or
        self:check("servoSettings", self.L.servoSettingsChecked)
      self.cards = {self:cardDef(self.L.prepareStep, self.L.prepareStepHint, rows)}
      self.card, self.preparationCard = 1, true
      return true
    end
    return false
  end
  function w:preparationComplete()
    if self.preparationCard then
      return self:ack("blades") and self:ack(self.step < 10 and "unplugged" or "servoSettings")
    end
    return true
  end
  function w:finishStep()
    local function after()
      if self.singleStep then
        if self.returnToSuite then self:close() else self:showSteps() end
      elseif self.step == 19 then self:close()
      else self:navigate(self.step + 1, 1) end
    end
    if self.rememberStep then self:rememberStep(after) else after() end
  end
  function w:resolveExit(save)
    if self.transition then return end
    local steps,target = self.exitToSteps,self.backTarget
    self.confirmExit, self.exitToSteps,self.backTarget = nil, nil,nil
    local after = target and function() self:navigate(target,1) end or
      steps and function() self:showSteps() end or function() self:close() end
    if save then self:save(after) else self:discard((steps or target) and after or nil) end
  end
end
return M
