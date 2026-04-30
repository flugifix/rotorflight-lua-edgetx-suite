-- Generic sequential tasks runner for RFSuite events
local M = {}

local DEFAULT_TASK_TIMEOUT_SECONDS = 25
local MAX_RETRIES = 3
local RETRY_BACKOFF_SECONDS = 1

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

function M.new(category)
  local runner = {}
  local BASE_PATH = "tasks/events/" .. category .. "/tasks/"
  local COMMON_PATH = "tasks/events/common/"
  local MANIFEST_PATH = "tasks/events/" .. category .. "/manifest.lua"

  local tasksQueue = {}
  local tasksLoaded = false
  local queueIndex = 1
  local tasksDoneLogged = false

  local Log = nil
  local Env = nil

  local function ensureLog()
    if not Log then Log = loadModule("lib/log.lua") end
  end

  local function ensureEnv()
    if not Env then Env = loadModule("lib/env.lua") end
  end

  local function loadManifest()
    local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. MANIFEST_PATH, "t")
    if type(chunk) ~= "function" then
      ensureLog()
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks." .. category, "manifest missing: " .. tostring(MANIFEST_PATH), "debug", true) end
      tasksLoaded = true
      return
    end
    local ok, manifest = pcall(chunk)
    if not ok or type(manifest) ~= "table" then
      ensureLog()
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks." .. category, "invalid manifest: " .. tostring(MANIFEST_PATH), "debug", true) end
      tasksLoaded = true
      return
    end

    ensureEnv()
    local currentEnv = Env and Env.get() or "tool"

    for _, entry in ipairs(manifest) do
      local name = nil
      local context = "both"
      local isShared = false

      if type(entry) == "table" then
        name = entry.name
        context = entry.context or "both"
        isShared = entry.shared == true
      else
        name = entry
      end

      local eligible = false
      if context == "both" then
        eligible = true
      elseif context == "tool" and currentEnv == "tool" then
        eligible = true
      elseif context == "widget" and currentEnv == "widget" then
        eligible = true
      end

      if name and eligible then
        local path = (isShared or name == "flight_stats") and (COMMON_PATH .. name .. ".lua") or (BASE_PATH .. name .. ".lua")
        tasksQueue[#tasksQueue + 1] = {
          name = name,
          path = path,
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
    if type(chunk) ~= "function" then
      -- Fallback to common path if not already using it and local load failed
      if not string.find(task.path, COMMON_PATH, 1, true) then
        local commonPath = COMMON_PATH .. task.name .. ".lua"
        chunk, err = loadScript("/SCRIPTS/TOOLS/rfsuite-core/" .. commonPath, "t")
      end
    end

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

  function runner.findTasks()
    if tasksLoaded then return end
    clearTaskEntries()
    loadManifest()
  end

  function runner.resetAllTasks()
    resetQueuesAndState()
  end

  function runner.reset()
    resetQueuesAndState()
  end

  function runner.wakeup(args)
    ensureLog()
    if not tasksLoaded then runner.findTasks() end
    if #tasksQueue == 0 then return end
    if isQueueDone() then
      if not tasksDoneLogged then
        if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks." .. category, "all " .. category .. " tasks complete", "debug", true) end
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
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks." .. category, "failed to load task " .. tostring(task.name) .. ": " .. tostring(err or "?"), "info", true) end
      queueIndex = (queueIndex or 1) + 1
      advancePastCompletedOrFailed()
      return
    end

    if type(module.wakeup) == "function" then
      pcall(module.wakeup, args)
    end

    if module.isComplete and module.isComplete() then
      task.complete = true
      task.startTime = nil
      task.nextEligibleAt = 0
      releaseTaskModule(task, false)
      if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks." .. category, "completed task " .. tostring(task.name), "debug", true) end
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
        if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks." .. category, string.format("Task '%s' timed out. Re-queueing (attempt %d/%d) in %.1fs.", task.name, task.attempts, MAX_RETRIES, backoff), "info", true) end
      else
        task.failed = true
        task.startTime = nil
        releaseTaskModule(task, false)
        if Log and type(Log.emit) == "function" then pcall(Log.emit, "rfsuite.tasks." .. category, string.format("Task '%s' failed after %d attempts. Skipping.", task.name, MAX_RETRIES), "info", true) end
        queueIndex = (queueIndex or 1) + 1
        advancePastCompletedOrFailed()
      end
    end
  end

  function runner.active()
    return not isQueueDone()
  end

  return runner
end

return M
