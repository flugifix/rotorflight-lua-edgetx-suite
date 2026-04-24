-- Lightweight onconnect tasks runner
local M = {}

local DEFAULT_TASK_TIMEOUT_SECONDS = 25
local MAX_RETRIES = 3
local RETRY_BACKOFF_SECONDS = 1

local BASE_PATH = "tasks/events/onconnect/tasks/"
local MANIFEST_PATH = "tasks/events/onconnect/manifest.lua"

local tasksQueue = {}
local tasksLoaded = false
local queueIndex = 1
local tasksDoneLogged = false

local Log = nil

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local function ensureLog()
  if not Log then Log = loadModule("lib/log.lua") end
end

local function loadManifest()
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. MANIFEST_PATH, "t")
  if type(chunk) ~= "function" then
    ensureLog()
    if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.onconnect", "manifest missing: " .. tostring(MANIFEST_PATH), "debug", true) end
    tasksLoaded = true
    return
  end
  local ok, manifest = pcall(chunk)
  if not ok or type(manifest) ~= "table" then
    ensureLog()
    if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.onconnect", "invalid manifest: " .. tostring(MANIFEST_PATH), "debug", true) end
    tasksLoaded = true
    return
  end

  for _, name in ipairs(manifest) do
    if name then
      tasksQueue[#tasksQueue + 1] = {
        name = name,
        path = BASE_PATH .. name .. ".lua",
        module = nil,
        initialized = false,
        complete = false,
        failed = false,
        attempts = 0,
        nextEligibleAt = 0,
        startTime = nil,
      }
    end
  end

  tasksLoaded = true
end

local function clearTaskEntries()
  for i = #tasksQueue, 1, -1 do tasksQueue[i] = nil end
  queueIndex = 1
  tasksDoneLogged = false
end

local function ensureTaskModule(task)
  if not task or not task.path then return nil, "invalid task" end
  if task.module then return task.module end
  local chunk, err = loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. task.path, "t")
  if type(chunk) ~= "function" then return nil, "load failed: " .. tostring(err) end
  local ok, mod = pcall(chunk)
  if not ok or type(mod) ~= "table" then return nil, "invalid module: " .. tostring(mod) end
  task.module = mod
  return mod
end

local function releaseTaskModule(task, runReset)
  if not task or not task.module then return end
  local mod = task.module
  if runReset and type(mod.reset) == "function" then pcall(mod.reset) end
  task.module = nil
end

local function resetQueuesAndState()
  for i = 1, #tasksQueue do
    local t = tasksQueue[i]
    releaseTaskModule(t, true)
    t.initialized = false
    t.complete = false
    t.failed = false
    t.attempts = 0
    t.nextEligibleAt = 0
    t.startTime = nil
  end
  queueIndex = 1
  tasksDoneLogged = false
end

local function currentTask()
  return tasksQueue[queueIndex]
end

local function advancePastCompletedOrFailed()
  local idx = queueIndex or 1
  while idx <= #tasksQueue do
    local t = tasksQueue[idx]
    if t and not t.complete and not t.failed then break end
    idx = idx + 1
  end
  queueIndex = idx
end

local function isQueueDone()
  advancePastCompletedOrFailed()
  return (queueIndex or 1) > #tasksQueue
end

function M.findTasks()
  if tasksLoaded then return end
  clearTaskEntries()
  loadManifest()
end

function M.resetAllTasks()
  resetQueuesAndState()
end

function M.reset()
  resetQueuesAndState()
end

function M.wakeup()
  ensureLog()
  if not tasksLoaded then M.findTasks() end
  if #tasksQueue == 0 then return end
  if isQueueDone() then
    if not tasksDoneLogged then
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.onconnect", "all onconnect tasks complete", "debug", true) end
      tasksDoneLogged = true
    end
    return
  end

  local task = currentTask()
  if not task then return end
  local now = (type(os) == "table" and type(os.clock) == "function") and os.clock() or 0

  if task.nextEligibleAt and task.nextEligibleAt > now then return end

  if not task.initialized then task.initialized = true; task.startTime = now end

  local module, err = ensureTaskModule(task)
  if not module then
    task.failed = true
    task.startTime = nil
    task.nextEligibleAt = 0
    if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.onconnect", "failed to load task " .. tostring(task.name) .. ": " .. tostring(err or "?"), "info", true) end
    queueIndex = (queueIndex or 1) + 1
    advancePastCompletedOrFailed()
    return
  end

  if type(module.wakeup) == "function" then
    pcall(module.wakeup)
  end

  if module.isComplete and module.isComplete() then
    task.complete = true
    task.startTime = nil
    task.nextEligibleAt = 0
    releaseTaskModule(task, false)
    if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.onconnect", "completed task " .. tostring(task.name), "debug", true) end
    queueIndex = (queueIndex or 1) + 1
    advancePastCompletedOrFailed()
    return
  end

  local timeout = DEFAULT_TASK_TIMEOUT_SECONDS
  if task.startTime and (now - task.startTime) > timeout then
    task.attempts = (task.attempts or 0) + 1
    if task.attempts <= MAX_RETRIES then
      local backoff = RETRY_BACKOFF_SECONDS * (2 ^ (task.attempts - 1))
      task.nextEligibleAt = now + backoff
      task.initialized = false
      task.startTime = nil
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.onconnect", string.format("Task '%s' timed out. Re-queueing (attempt %d/%d) in %.1fs.", task.name, task.attempts, MAX_RETRIES, backoff), "info", true) end
    else
      task.failed = true
      task.startTime = nil
      releaseTaskModule(task, false)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks.onconnect", string.format("Task '%s' failed after %d attempts. Skipping.", task.name, MAX_RETRIES), "info", true) end
      queueIndex = (queueIndex or 1) + 1
      advancePastCompletedOrFailed()
    end
  end
end

function M.active()
  return not isQueueDone()
end

return M
