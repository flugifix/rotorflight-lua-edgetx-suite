local TelemetrySync = {}
TelemetrySync.__index = TelemetrySync

-- ELRS RFMD mapping with mode labels and band family.
local RFMD_MAP = {
  [0] = { rateHz = 25, mode = "25Hz", band = "900Mhz" },
  [1] = { rateHz = 50, mode = "50Hz", band = "900Mhz" },
  [2] = { rateHz = 100, mode = "100Hz", band = "900Mhz" },
  [3] = { rateHz = 100, mode = "100Hz Full", band = "900Mhz" },
  [4] = { rateHz = 150, mode = "150Hz", band = "900Mhz" },
  [5] = { rateHz = 200, mode = "200Hz", band = "900Mhz" },
  [6] = { rateHz = 200, mode = "200Hz Full", band = "900Mhz" },
  [7] = { rateHz = 250, mode = "250Hz", band = "900Mhz" },
  [8] = { rateHz = 333, mode = "333Hz Full", band = "900Mhz" },
  [9] = { rateHz = 500, mode = "500Hz", band = "900Mhz" },
  [10] = { rateHz = 25, mode = "D25", band = "900Mhz" },
  [11] = { rateHz = 500, mode = "K500 Full", band = "900Mhz" },
  -- Observed EdgeTX RFMD encoding for 2.4GHz appears shifted by -1.
  [21] = { rateHz = 50, mode = "50Hz", band = "2.4GHz" },
  [22] = { rateHz = 100, mode = "100Hz", band = "2.4GHz" },
  [23] = { rateHz = 100, mode = "100Hz Full", band = "2.4GHz" },
  [24] = { rateHz = 150, mode = "150Hz", band = "2.4GHz" },
  [25] = { rateHz = 200, mode = "200Hz", band = "2.4GHz" },
  [26] = { rateHz = 200, mode = "200Hz Full", band = "2.4GHz" },
  [27] = { rateHz = 250, mode = "250Hz", band = "2.4GHz" },
  [28] = { rateHz = 333, mode = "333Hz Full", band = "2.4GHz" },
  [29] = { rateHz = 500, mode = "500Hz", band = "2.4GHz" },
  [30] = { rateHz = 250, mode = "D250", band = "2.4GHz" },
  [31] = { rateHz = 500, mode = "D500", band = "2.4GHz" },
  [32] = { rateHz = 500, mode = "F500", band = "2.4GHz" },
  [33] = { rateHz = 1000, mode = "F1000", band = "2.4GHz" },
  [34] = { rateHz = 250, mode = "DK250", band = "2.4GHz" },
  [35] = { rateHz = 500, mode = "DK500", band = "2.4GHz" },
  [36] = { rateHz = 1000, mode = "K1000", band = "2.4GHz" },
  [37] = { rateHz = 1000, mode = "K1000", band = "2.4GHz" },
  [101] = { rateHz = 100, mode = "X100 Full", band = "900MHz" },
  [102] = { rateHz = 150, mode = "X150", band = "900MHz" }
}

local RFMD_SENSOR_CANDIDATES = { "RFMD", "Rfmd" }
function TelemetrySync.new(opts)
  opts = opts or {}
  local self = setmetatable({}, TelemetrySync)
  self.nowSeconds = type(opts.nowSeconds) == "function" and opts.nowSeconds or function() return 0 end
  self.log = type(opts.log) == "function" and opts.log or function() end
  self.fieldIdCache = {}
  self.nextSyncAt = 0
  self.writeInFlight = false
  self.lastDebugAt = 0
  self.syncDone = false
  self.verifyPending = false
  self.lastDesiredRate = nil
  self.txRfmd = nil
  self.txRfMode = nil
  self.txRfBand = nil
  self.txRateHz = nil
  self.txInfo = { rfmd = nil, mode = nil, band = nil, rateHz = nil }
  return self
end

function TelemetrySync:logSync(message, level)
  local lvl = level or "debug"
  local now = self.nowSeconds()
  if lvl == "debug" and (now - (self.lastDebugAt or 0)) < 1.0 then
    return
  end
  self.lastDebugAt = now
  self.log("[telem-sync] " .. tostring(message), lvl)
end

function TelemetrySync:isWriteInFlight()
  return self.writeInFlight == true
end

function TelemetrySync:isSyncDone()
  return self.syncDone == true
end

function TelemetrySync:onConnected(now)
  self.nextSyncAt = (tonumber(now) or self.nowSeconds()) + 3.0
  self.writeInFlight = false
  self.syncDone = false
  self.verifyPending = false
  self.lastDesiredRate = nil
  self.txRfmd = nil
  self.txRfMode = nil
  self.txRfBand = nil
  self.txRateHz = nil
end

function TelemetrySync:onDisconnected()
  self.nextSyncAt = 0
  self.writeInFlight = false
  self.syncDone = false
  self.verifyPending = false
  self.lastDesiredRate = nil
  self.txRfmd = nil
  self.txRfMode = nil
  self.txRfBand = nil
  self.txRateHz = nil
end

function TelemetrySync:getTxInfo()
  local info = self.txInfo
  info.rfmd = self.txRfmd
  info.mode = self.txRfMode
  info.band = self.txRfBand
  info.rateHz = self.txRateHz
  return info
end

function TelemetrySync:onReadSuccess(fcRate, fcRatio)
  self:logSync("FC config read rate=" .. tostring(fcRate) .. " ratio=" .. tostring(fcRatio), "debug")
  if self.verifyPending then
    local liveRate = tonumber(fcRate)
    if liveRate and self.lastDesiredRate and liveRate == self.lastDesiredRate then
      self:logSync("FC config verified after write (rate=" .. tostring(liveRate) .. ")", "info")
    else
      self:logSync(
        "FC verify mismatch after write (fcRate=" .. tostring(fcRate) .. ", expected=" .. tostring(self.lastDesiredRate) .. ")",
        "warn"
      )
    end
    self.verifyPending = false
    self.syncDone = true
  end
end

function TelemetrySync:onWriteQueued(now, desiredRate, desiredRatio)
  self.writeInFlight = true
  self.nextSyncAt = (tonumber(now) or self.nowSeconds()) + 10.0
  self.lastDesiredRate = tonumber(desiredRate)
  self:logSync("Mismatch detected; enqueue write rate=" .. tostring(desiredRate) .. " ratio=" .. tostring(desiredRatio), "info")
end

function TelemetrySync:onWriteSuccess(now)
  self.writeInFlight = false
  self.verifyPending = true
  self.nextSyncAt = (tonumber(now) or self.nowSeconds()) + 1.0
  self:logSync("FC config write success", "info")
end

function TelemetrySync:onWriteError(now)
  self.writeInFlight = false
  self.verifyPending = false
  self.syncDone = true
  self.nextSyncAt = (tonumber(now) or self.nowSeconds()) + 10.0
  self:logSync("FC config write failed", "warn")
end

function TelemetrySync:setRetryDelay(now, delaySeconds, reason)
  self.nextSyncAt = (tonumber(now) or self.nowSeconds()) + (tonumber(delaySeconds) or 2.5)
  if reason then
    self:logSync(reason, "debug")
  end
end

function TelemetrySync:readNumericSensor(candidates)
  if type(candidates) ~= "table" or type(getValue) ~= "function" then
    return nil, nil
  end

  for i = 1, #candidates do
    local name = candidates[i]
    if type(name) == "string" and name ~= "" then
      local cached = self.fieldIdCache[name]
      if cached == nil and type(getFieldInfo) == "function" then
        local okInfo, info = pcall(getFieldInfo, name)
        if okInfo and type(info) == "table" and info.id ~= nil then
          cached = info.id
        else
          cached = 0
        end
        self.fieldIdCache[name] = cached
      end

      local ok, value
      if type(cached) == "number" and cached ~= 0 then
        ok, value = pcall(getValue, cached)
      else
        ok, value = pcall(getValue, name)
      end

      if ok and type(value) == "number" then
        return value, name
      end
    end
  end

  for i = 1, #candidates do
    local name = candidates[i]
    local ok, value = pcall(getValue, name)
    if ok and type(value) == "number" then
      return value, name
    end
  end

  return nil, nil
end

function TelemetrySync:readDesiredTelemetryFromTx()
  local rfmd, rfmdSource = self:readNumericSensor(RFMD_SENSOR_CANDIDATES)
  if type(rfmd) ~= "number" then
    self:logSync("RFMD unavailable", "debug")
    return nil
  end

  local rfmdIndex = math.floor(rfmd + 0.5)
  self.txRfmd = rfmdIndex

  local rfmdInfo = RFMD_MAP[rfmdIndex]
  if type(rfmdInfo) ~= "table" or type(rfmdInfo.rateHz) ~= "number" then
    self.txRfMode = nil
    self.txRfBand = nil
    self.txRateHz = nil
    self:logSync("RFMD=" .. tostring(rfmdIndex) .. " has no known rate mapping", "info")
    return nil
  end

  local rateHz = rfmdInfo.rateHz
  self.txRfMode = rfmdInfo.mode
  self.txRfBand = rfmdInfo.band
  self.txRateHz = rateHz

  self:logSync(
    "TX rfmd=" .. tostring(rfmdIndex) ..
    "(" .. tostring(rfmdInfo.mode) .. ", " .. tostring(rateHz) .. "Hz, " .. tostring(rfmdInfo.band) .. ")" ..
    " via " .. tostring(rfmdSource or "?"),
    "debug"
  )

  return rateHz
end

function TelemetrySync:evaluate(now, enabled, fcRate, fcRatio)
  if enabled ~= true then
    return { action = "idle" }
  end
  if self.syncDone == true then
    return { action = "idle" }
  end
  if self.writeInFlight == true then
    return { action = "wait" }
  end
  if (tonumber(now) or 0) < (self.nextSyncAt or 0) then
    return { action = "wait" }
  end

  local liveFcRate = tonumber(fcRate)
  local liveFcRatio = tonumber(fcRatio)

  if not liveFcRate then
    self:setRetryDelay(now, 2.5, "FC telemetry config missing; scheduling read")
    return { action = "read" }
  end

  local desiredRate = self:readDesiredTelemetryFromTx()
  if not desiredRate then
    self:logSync("No desired TX rate available; skip sync for this connection", "warn")
    self.syncDone = true
    return { action = "idle" }
  end

  local rateMismatch = (liveFcRate ~= desiredRate)

  if not rateMismatch then
    self.nextSyncAt = (tonumber(now) or self.nowSeconds()) + 5.0
    self:logSync("FC already in sync (rate=" .. tostring(liveFcRate) .. ")", "info")
    self.syncDone = true
    return { action = "idle" }
  end

  return {
    action = "write",
    desiredRate = desiredRate,
    desiredRatio = nil
  }
end

return TelemetrySync