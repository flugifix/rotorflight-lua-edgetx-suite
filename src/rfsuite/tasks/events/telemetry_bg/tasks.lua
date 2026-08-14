local M = {}

local RFSensors = nil
local Smart = nil

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

local function decU8(data, pos)
    return data[pos], pos+1
end

local function decU16(data, pos)
    return bit32.lshift(data[pos],8) + data[pos+1], pos+2
end

local CrsfManager = nil

local function crossfirePop()
    local CRSF_FRAME_CUSTOM_TELEM = 0x88
    if not CrsfManager then
      CrsfManager = loadModule("lib/crsf.lua")
    end
    if not CrsfManager then return false end
    
    local data = CrsfManager.popFrame(CRSF_FRAME_CUSTOM_TELEM)
    if data then
        local fid, sid, val
        local ptr = 3
        fid,ptr = decU8(data, ptr)
        local delta = bit32.band(fid - telemetryFrameId, 0xFF)
        if delta > 1 then
            telemetryFrameSkip = telemetryFrameSkip + 1
        end
        telemetryFrameId = fid
        telemetryFrameCount = telemetryFrameCount + 1
        while ptr < #data do
            sid,ptr = decU16(data, ptr)
            local sensor = RFSensors[sid]
            if sensor and type(sensor.dec) == "function" then
                val,ptr = sensor.dec(data, ptr)
                if val then
                    setTelemetryValue(sid, 0, 0, val, sensor.unit or 0, sensor.prec or 0, sensor.name or "")
                end
            else
                break
            end
        end
        setTelemetryValue(0xEE01, 0, 0, telemetryFrameCount, 0, 0, "*Cnt")
        setTelemetryValue(0xEE02, 0, 0, telemetryFrameSkip, 0, 0, "*Skp")
        return true
    end
    return false
end

function M.wakeup()
    if not RFSensors then
        RFSensors = loadModule("lib/rf2tlm_sensors.lua")
        if not RFSensors then return end
    end
    if not Smart then
        Smart = loadModule("tasks/events/telemetry_bg/smart.lua")
    end
    
    local limit = 15
    local processed = 0
    while processed < limit and crossfirePop() do
        processed = processed + 1
    end

    if Smart and type(Smart.wakeup) == "function" then
        Smart.wakeup()
    end
end

function M.reset()
    telemetryFrameId = 0
    telemetryFrameSkip = 0
    telemetryFrameCount = 0
    if Smart and type(Smart.reset) == "function" then
        Smart.reset()
    end
end

return M
