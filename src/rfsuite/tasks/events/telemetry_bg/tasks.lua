local M = {}

local RFSensors = nil
local Smart = nil
local Adjustments = nil

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local telemetryFrameId = 0
local telemetryFrameSkip = 0
local telemetryFrameCount = 0

-- A published sensor stays valid on the radio for TELEMETRY_SENSOR_TIMEOUT_START, so an
-- unchanged value does not have to be re-sent every frame. It matters because every
-- setTelemetryValue() call marks the model dirty, which moves the model file's write
-- deadline forward rather than the write itself: publishing every sensor of every frame
-- starves the flush for as long as telemetry flows, and a setting the pilot changes in
-- that window is not persisted. Publish on change, and refresh an unchanged sensor well
-- inside its timeout. Same contract as publishTelemetryValue() in smart.lua.
local FORCE_REFRESH_INTERVAL = 2.0

local lastPublishedValue = {}
local lastPublishedAt = {}

-- The decoder's own two counters, and they need a publisher of their own rather than the one
-- above. `publishSensorValue` throttles by CHANGE, and the frame count changes in every single
-- frame by construction -- so through that publisher it would go out at the full frame rate and
-- defeat the throttle exactly as it did before this fix. Measured rather than reasoned: over
-- 20 s at 8 frames/s the change-based publisher writes *Cnt 160 times, this one writes it 10.
--
-- So these two are RATE limited instead. The cost is that the reading can be up to
-- FORCE_REFRESH_INTERVAL stale, which is the right trade for a decoder diagnostic.
local lastCounterAt = 0

local function publishCounters(count, skip, now)
    if (now - lastCounterAt) < FORCE_REFRESH_INTERVAL then return end
    lastCounterAt = now
    setTelemetryValue(0xEE01, 0, 0, count, 0, 0, "*Cnt")
    setTelemetryValue(0xEE02, 0, 0, skip, 0, 0, "*Skp")
end

local function nowSeconds()
    if type(getTime) == "function" then
        local ok, v = pcall(getTime)
        if ok and type(v) == "number" then return v / 100 end
    end
    if type(os) == "table" and type(os.clock) == "function" then return os.clock() end
    return 0
end

local function publishSensorValue(sid, value, sensor, now)
    local stale = (now - (lastPublishedAt[sid] or 0)) >= FORCE_REFRESH_INTERVAL
    if lastPublishedValue[sid] == value and not stale then return end
    setTelemetryValue(sid, 0, 0, value, sensor.unit or 0, sensor.prec or 0, sensor.name or "")
    lastPublishedValue[sid] = value
    lastPublishedAt[sid] = now
end

local function decU8(data, pos)
    return data[pos], pos+1
end

local function decU16(data, pos)
    return bit32.lshift(data[pos],8) + data[pos+1], pos+2
end

local CrsfManager = nil

-- Per-pass bounds for the custom-telemetry drain. Popping a frame is a handful of C calls;
-- DECODING one is a Lua walk over every sensor it carries -- the expensive term. So the
-- drain looks at up to POP_CAP frames per wakeup to keep the queue from backing up, but
-- fully decodes only the newest DECODE_CAP of them: telemetry is values, not commands, and
-- the next frame carries the current state, so under a backlog the oldest frames are the
-- right ones to skip. Both are provisional counts, to be calibrated by offline instruction
-- accounting.
local POP_CAP = 15
local DECODE_CAP = 4

-- The cheap half: pop one frame and keep the frame counters honest. The id bookkeeping runs
-- for EVERY popped frame, decoded or not -- `*Skp` means "the link skipped", and a decode
-- the drain chose to skip must never read as a link problem.
local function popAndAccount()
    local CRSF_FRAME_CUSTOM_TELEM = 0x88
    if not CrsfManager then
      CrsfManager = loadModule("lib/crsf.lua")
    end
    if not CrsfManager then return nil end

    local data = CrsfManager.popFrame(CRSF_FRAME_CUSTOM_TELEM)
    if not data then return nil end

    local fid, ptr
    ptr = 3
    fid, ptr = decU8(data, ptr)
    local delta = bit32.band(fid - telemetryFrameId, 0xFF)
    if delta > 1 then
        telemetryFrameSkip = telemetryFrameSkip + 1
    end
    telemetryFrameId = fid
    telemetryFrameCount = telemetryFrameCount + 1
    return data
end

-- The expensive half: the byte walk through the per-sensor decoders. The frame id at byte 3
-- was consumed by popAndAccount, so the walk starts at byte 4.
local function decodeFrame(data, now)
    local sid, val
    local ptr = 4
    while ptr < #data do
        sid,ptr = decU16(data, ptr)
        local sensor = RFSensors[sid]
        if sensor and type(sensor.dec) == "function" then
            val,ptr = sensor.dec(data, ptr)
            if val then
                publishSensorValue(sid, val, sensor, now)
            end
        else
            break
        end
    end
end

function M.wakeup()
    if not RFSensors then
        RFSensors = loadModule("lib/rf2tlm_sensors.lua")
        if not RFSensors then return end
    end
    if not Smart then
        Smart = loadModule("tasks/events/telemetry_bg/smart.lua")
    end
    if not Adjustments then
        Adjustments = loadModule("tasks/events/telemetry_bg/adjustments.lua")
    end

    -- Pop up to POP_CAP, keep the newest DECODE_CAP in arrival order, decode only those --
    -- on a same-sensor conflict the newest value lands last.
    local kept = {}
    local popped = 0
    while popped < POP_CAP do
        local data = popAndAccount()
        if not data then break end
        popped = popped + 1
        kept[#kept + 1] = data
        if #kept > DECODE_CAP then
            table.remove(kept, 1)
        end
    end

    if popped > 0 then
        local now = nowSeconds()
        for i = 1, #kept do
            decodeFrame(kept[i], now)
        end
        -- Published unconditionally, and that is deliberate: the sibling project creates the
        -- same two sensors and treats a missing `*Cnt` as "the pilot deleted the telemetry
        -- sensors", so a radio carrying both suites needs them to keep meaning what they mean.
        -- A pilot who does not want the two rows can delete them on the telemetry page; outside
        -- a discovery window nothing here creates them again. Once per wakeup: the publisher
        -- rate-limits itself, and per-frame publication was redundancy, not information.
        publishCounters(telemetryFrameCount, telemetryFrameSkip, now)
    end

    if Smart and type(Smart.wakeup) == "function" then
        Smart.wakeup()
    end

    -- After the decode, never before it: what the teller reads is what the loop above has just
    -- published, so the other order would announce one pass behind.
    if Adjustments and type(Adjustments.wakeup) == "function" then
        Adjustments.wakeup()
    end
end

function M.reset()
    telemetryFrameId = 0
    telemetryFrameSkip = 0
    telemetryFrameCount = 0
    lastPublishedValue = {}
    lastPublishedAt = {}
    lastCounterAt = 0
    if Smart and type(Smart.reset) == "function" then
        Smart.reset()
    end
    if Adjustments and type(Adjustments.reset) == "function" then
        Adjustments.reset()
    end
end

return M
