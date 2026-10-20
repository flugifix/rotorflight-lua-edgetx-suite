-- Lazy, visit-local dependencies: opening from a widget never loads the wizard in one call.
local M = { hideSuiteFrame = true, handlesDisconnect = true }
local BASE = "/SCRIPTS/TOOLS/rfsuite-core/"
local PATH = "app/pages/helicopter_setup/"
local modules, stage, w, context, viewJob, scene, sceneKey = {}, 1
local deps = { "tasks/msp/runtime.lua", PATH .. "transport.lua", PATH .. "math.lua", PATH .. "labels.lua",
  PATH .. "controller.lua", PATH .. "forms.lua", PATH .. "workflow.lua", PATH .. "view.lua", "lib/armed.lua" }
local keys = { "sensors", "receiver", "modes", "profiles", "rates", "swash", "servoType", "governor", "motor",
  "connect", "throttle", "escTelemetry", "servos", "direction", "level", "pitch", "tail", "gyro", "finish" }
local function key()
  if not w then return "loading" end
  return tostring(w.step) .. ":" .. tostring(w.card) .. ":" .. tostring(w.cards) .. ":" .. tostring(w.confirmExit)
    .. ":" .. tostring(w.error) .. ":" .. tostring(context.w) .. ":" .. tostring(context.h)
end
function M.build(ctx)
  context = ctx
  if w then w.requestClose, w.requestRebuild = ctx.requestClose, ctx.requestRebuild end
  if w then w.openHelp = ctx.openHelp end
  if w and ctx.armed then
    w.canEdit, w.canNext, w.message = false, false, w.L.disconnected
    w:release()
  end
  if scene and sceneKey == key() then
    table.move(scene, 1, #scene, #ctx.children+1, ctx.children)
  else
    ctx.children[#ctx.children+1] = { type = "label", x = 12, y = 30, w = ctx.w-24,
      text = "@i18n(helicopter.loading)@", color = COLOR_THEME_PRIMARY1, font = SMLSIZE }
  end
end
function M.wakeup(ctx)
  if not context then return end
  if ctx and ctx.requestRebuild then context.requestRebuild = ctx.requestRebuild end
  if deps[stage] then
    modules[stage] = assert(loadScript(BASE .. deps[stage], "t"))(); stage = stage + 1; return
  end
  if not w then
    w = modules[5].new(modules[1], modules[2], modules[3], modules[4])
    modules[6].attach(w); modules[7].attach(w)
    w.requestClose, w.requestRebuild = context.requestClose, context.requestRebuild
    w.armedEpoch = modules[9].changeCount()
    w:load(); return
  end
  if modules[9].changeCount() ~= w.armedEpoch then
    w.armedEpoch = modules[9].changeCount(); w.bus:cancel(); w:release(); w.error = "arming"; w:rebuild(); return
  end
  w.stepKey = keys[w.step]
  if viewJob then
    if viewJob:step() then scene, sceneKey = viewJob.children, viewJob.key; viewJob = nil; w:rebuild() end
    return
  end
  if (w.cards or w.error or w.confirmExit) and sceneKey ~= key() then
    viewJob = modules[8].new(w, context); viewJob.key = key(); return
  end
  w:tick()
  w.canEdit = w:usable()
  w.canNext = w.canEdit and w.cards ~= nil
end
function M.onBack()
  if w then w:back() elseif context and context.requestClose then context.requestClose() end
  return true
end
function M.onClose()
  if w then
    w.bus:cancel(); w:release()
    local q, api = w.bus:queue(), w.bus.apis.arming_disable
    if q and api and w:allowed() then
      q:add({ command = api.writeCommand, payload = api.buildWritePayload({ disabled = false }),
        isWrite = true, client = "helicopter-cleanup" })
    end
    w.active = false
  end
  modules, stage, w, context, viewJob, scene, sceneKey = {}, 1, nil, nil, nil, nil, nil
end
function M.getHeaderActions() return { save = false, reload = false, help = false } end
return M
