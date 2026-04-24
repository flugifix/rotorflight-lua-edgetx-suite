local Queue = {}
Queue.__index = Queue

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, ticks = pcall(getTime)
    if ok and type(ticks) == "number" then
      return ticks / 100
    end
  end
  if type(os) == "table" and type(os.clock) == "function" then
    return os.clock()
  end
  return 0
end

local DEFAULT_RETRY_BACKOFF_SECONDS = 1.0
local DEFAULT_TIMEOUT_SECONDS = 2.0
local DEFAULT_COMMAND_INTERVAL_SECONDS = 0.25
local DEFAULT_DRAIN_AFTER_REPLY_SECONDS = 0.03
local DEFAULT_DRAIN_MAX_POLLS = 6
local QUEUE_COMPACT_THRESHOLD = 64

local function newQueue()
  return { first = 1, last = 0, data = {} }
end

local function qcount(q)
  return q.last - q.first + 1
end

local function qpush(q, v)
  q.last = q.last + 1
  q.data[q.last] = v
end

local function qreset(q)
  if not q then return end
  local data = q.data
  for i = q.first, q.last do
    data[i] = nil
  end
  q.first = 1
  q.last = 0
end

local function qcompact(q)
  local first = q.first
  local last = q.last
  if first <= 1 or first > last then return end

  local data = q.data
  local write = 1
  for read = first, last do
    data[write] = data[read]
    if write ~= read then
      data[read] = nil
    end
    write = write + 1
  end

  q.first = 1
  q.last = write - 1
end

local function qpop(q)
  if q.first > q.last then return nil end
  local idx = q.first
  local v = q.data[idx]
  q.data[idx] = nil
  idx = idx + 1

  if idx > q.last then
    q.first = 1
    q.last = 0
  else
    q.first = idx
    local active = q.last - q.first + 1
    if q.first > QUEUE_COMPACT_THRESHOLD and q.first > active then
      qcompact(q)
    end
  end

  return v
end

local function isWriteMessage(msg)
  if msg == nil then return false end
  if msg.isWrite ~= nil then
    return msg.isWrite == true
  end
  return msg.write == true or (type(msg.payload) == "table" and #msg.payload > 0)
end

local function formatMspState(msg)
  if not msg then return "MSP" end
  local rw = isWriteMessage(msg) and "WRITE" or "READ"
  return "MSP " .. rw .. " cmd=" .. tostring(msg.command)
end

local function detectSimulatorRuntime()
  if type(system) == "table" and type(system.getVersion) == "function" then
    local ok, info = pcall(system.getVersion)
    if ok and type(info) == "table" then
      local sim = info.simulation
      if sim ~= nil and sim ~= false and sim ~= 0 then
        return true
      end
    end
  end

  if type(getVersion) == "function" then
    local ok, _, fw = pcall(getVersion)
    if ok and type(fw) == "string" then
      local fwl = string.lower(fw)
      if string.find(fwl, "simu", 1, true) ~= nil then
        return true
      end
    end
  end

  return false
end

local function drainAfterSuccess(self, cmd)
  if cmd == nil or self.isSimulator then return end
  if not self.common or type(self.common.pollReply) ~= "function" then return end

  local deadline = nowSeconds() + (self.drainAfterReplySeconds or 0)
  local pollsLeft = self.drainMaxPolls or 0
  if pollsLeft <= 0 then return end

  while pollsLeft > 0 and nowSeconds() < deadline do
    local ok, rcmd, _, rerr = pcall(self.common.pollReply)
    if not ok or not rcmd then
      break
    end
    if rcmd ~= cmd or rerr then
      break
    end
    pollsLeft = pollsLeft - 1
  end
end

function Queue.new(common, opts)
  local self = setmetatable({}, Queue)
  opts = opts or {}

  self.common = common
  self.log = opts.log or function() end
  self.isSimulator = opts.isSimulator == true

  self.queue = newQueue()
  self.currentMessage = nil
  self.currentMessageStartTime = nil
  self.lastTimeCommandSent = nil

  self.retryCount = 0
  self.maxRetries = tonumber(opts.maxRetries) or 3
  self.timeout = tonumber(opts.timeout) or DEFAULT_TIMEOUT_SECONDS
  self.retryBackoff = tonumber(opts.retryBackoff) or DEFAULT_RETRY_BACKOFF_SECONDS
  self.commandInterval = tonumber(opts.commandInterval) or DEFAULT_COMMAND_INTERVAL_SECONDS
  self.interMessageDelay = tonumber(opts.interMessageDelay) or 0

  self.drainAfterReplySeconds = tonumber(opts.drainAfterReplySeconds) or DEFAULT_DRAIN_AFTER_REPLY_SECONDS
  self.drainMaxPolls = tonumber(opts.drainMaxPolls) or DEFAULT_DRAIN_MAX_POLLS
  self._nextMessageAt = 0

  return self
end

function Queue:isProcessed()
  return self.currentMessage == nil and qcount(self.queue) == 0
end

function Queue:add(message)
  if message == nil then
    return self
  end
  qpush(self.queue, message)
  return self
end

function Queue:clear()
  qreset(self.queue)
  self.currentMessage = nil
  self.currentMessageStartTime = nil
  self.lastTimeCommandSent = nil
  self.retryCount = 0
  self._nextMessageAt = 0
  if self.common and self.common.clearTxBuf then
    self.common.clearTxBuf()
  end
end

function Queue:processQueue(now)
  now = tonumber(now) or nowSeconds()
  local simulatorMode = self.isSimulator or detectSimulatorRuntime()
  if simulatorMode and not self.isSimulator then
    self.isSimulator = true
  end

  if self:isProcessed() then
    return
  end

  if not self.currentMessage then
    if self.interMessageDelay > 0 and now < self._nextMessageAt then
      return
    end
    self.currentMessage = qpop(self.queue)
    self.currentMessageStartTime = nil
    self.lastTimeCommandSent = nil
    self.retryCount = 0
  end

  local msg = self.currentMessage
  if not msg then return end

  local retryDelay = tonumber(msg.retryBackoff) or tonumber(msg.retryDelay) or self.retryBackoff
  local timeoutSeconds = tonumber(msg.timeout) or self.timeout
  local commandInterval = tonumber(msg.commandInterval) or self.commandInterval

  if simulatorMode then
    if not msg.simulatorResponse then
      self.log("No simulator response for cmd " .. tostring(msg.command), "warn")
      self.currentMessage = nil
      self.currentMessageStartTime = nil
      self.lastTimeCommandSent = nil
      return
    end

    if not self.lastTimeCommandSent or (self.lastTimeCommandSent + retryDelay < now) then
      self.lastTimeCommandSent = now
      self.retryCount = self.retryCount + 1
      msg.__retryCount = self.retryCount
      msg.buf = msg.simulatorResponse
      if type(msg.processReply) == "function" then
        msg.processReply(msg, msg.buf)
      end
      self.currentMessage = nil
      self.currentMessageStartTime = nil
      self.lastTimeCommandSent = nil
      if self.interMessageDelay > 0 then
        self._nextMessageAt = now + self.interMessageDelay
      end
    end
    return
  end

  -- Flush any pending TX fragments before checking for replies.
  if self.common and type(self.common.processTxQ) == "function" then
    self.common.processTxQ()
  end

  local pollOk, cmd, buf, err = pcall(function()
    if self.common and type(self.common.pollReply) == "function" then
      return self.common.pollReply()
    end
    return nil, nil, nil
  end)

  if not pollOk then
    self.log(formatMspState(msg) .. " poll error", "warn")
    return
  end

  if cmd then
    self.lastTimeCommandSent = nil
  end

  if cmd == msg.command and err and msg.retryOnErrorReply == true then
    self.lastTimeCommandSent = now
    return
  end

  local success = (cmd == msg.command and not err)
    or (cmd == msg.command and err and msg.completeOnErrorReplyAttempt and self.retryCount >= msg.completeOnErrorReplyAttempt)
    or (msg.command == 68 and self.retryCount == 2)

  if success then
    msg.buf = buf
    if type(msg.processReply) == "function" then
      msg.__retryCount = self.retryCount
      msg.processReply(msg, msg.buf)
    end
    if not simulatorMode then
      drainAfterSuccess(self, msg.command)
    end
    self.currentMessage = nil
    self.currentMessageStartTime = nil
    self.lastTimeCommandSent = nil
    if self.interMessageDelay > 0 then
      self._nextMessageAt = now + self.interMessageDelay
    end
    return
  end


  -- Patch: Ein neuer Request (Retry) darf erst nach Ablauf von timeout gesendet werden
  local canSendByInterval = not self.lastTimeCommandSent or (self.lastTimeCommandSent + commandInterval < now)
  local canSendByTimeout = (self.currentMessageStartTime == nil) or ((now - self.currentMessageStartTime) >= timeoutSeconds)

  if canSendByInterval and canSendByTimeout and self.retryCount <= self.maxRetries then
    local payload = msg.payload or {}
    local okSend = self.common and type(self.common.sendRequest) == "function"
      and self.common.sendRequest(msg.command, payload, { write = isWriteMessage(msg) })
    if okSend then
      self.lastTimeCommandSent = now
      self.currentMessageStartTime = now -- Timeout-Fenster für jeden Retry neu setzen
      self.retryCount = self.retryCount + 1
      if self.retryCount > 1 then
        self.log(formatMspState(msg) .. " retry=" .. tostring(self.retryCount) .. "/" .. tostring(self.maxRetries + 1), "debug")
      else
        self.log(formatMspState(msg) .. " send", "debug")
      end

      if self.common and type(self.common.processTxQ) == "function" then
        self.common.processTxQ()
      end
    end
  end

  -- Only give up after all retries have been versucht
  if self.retryCount > self.maxRetries then
    msg.__retryCount = self.retryCount
    if type(msg.errorHandler) == "function" then
      msg.errorHandler(msg, "max_retries")
    end
    if type(msg.setErrorHandler) == "function" then
      msg.setErrorHandler(msg)
    end
    self.log(formatMspState(msg) .. " max retries", "warn")
    self:clear()
    return
  end

  -- Timeout: nur abbrechen, wenn keine weiteren Retries mehr erlaubt sind
  if self.currentMessage and self.currentMessageStartTime and (now - self.currentMessageStartTime) > timeoutSeconds then
    if self.retryCount < self.maxRetries + 1 then
      -- Noch ein Retry erlaubt, warte auf Retry-Logik oben
      return
    end
    msg.__retryCount = self.retryCount
    if type(msg.errorHandler) == "function" then
      msg.errorHandler(msg, "timeout")
    end
    if type(msg.setErrorHandler) == "function" then
      msg.setErrorHandler(msg)
    end
    self.log(formatMspState(msg) .. " timeout", "warn")
    self.currentMessage = nil
    self.currentMessageStartTime = nil
    self.lastTimeCommandSent = nil
    if self.interMessageDelay > 0 then
      self._nextMessageAt = now + self.interMessageDelay
    end
    return
  end
end

return Queue
