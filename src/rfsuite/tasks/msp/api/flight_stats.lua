-- EdgeTX MSP API: FLIGHT_STATS (ported from Ethos)
-- Self-contained, no core/Ethos dependencies

local Api = {
  command = 14, -- MSP_API_CMD_READ
  writeCommand = 15, -- MSP_API_CMD_WRITE
  simulatorResponse = {
    123, 1, 0, 0, -- flightcount (U32)
    0, 1, 2, 0,   -- totalflighttime (U32)
    0, 0, 0, 0,   -- totaldistance (U32)
    15            -- minarmedtime (S8)
  }
}

local function parseU32(b1, b2, b3, b4)
  local n1 = tonumber(b1) or 0
  local n2 = tonumber(b2) or 0
  local n3 = tonumber(b3) or 0
  local n4 = tonumber(b4) or 0
  return n1 | (n2 << 8) | (n3 << 16) | (n4 << 24)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 13 then return nil end
  return {
    flightcount = parseU32(buf[1], buf[2], buf[3], buf[4]),
    totalflighttime = parseU32(buf[5], buf[6], buf[7], buf[8]),
    totaldistance = parseU32(buf[9], buf[10], buf[11], buf[12]),
    minarmedtime = tonumber(buf[13]) or 0
  }
end

function Api.buildWritePayload(data)
  local function toU32(val)
    val = math.floor(tonumber(val) or 0)
    return val & 0xFF, (val >> 8) & 0xFF, (val >> 16) & 0xFF, (val >> 24) & 0xFF
  end
  local payload = {}
  local lo, hi, h2, h3 = toU32(data.flightcount)
  payload[#payload+1] = lo; payload[#payload+1] = hi; payload[#payload+1] = h2; payload[#payload+1] = h3
  lo, hi, h2, h3 = toU32(data.totalflighttime)
  payload[#payload+1] = lo; payload[#payload+1] = hi; payload[#payload+1] = h2; payload[#payload+1] = h3
  lo, hi, h2, h3 = toU32(data.totaldistance)
  payload[#payload+1] = lo; payload[#payload+1] = hi; payload[#payload+1] = h2; payload[#payload+1] = h3
  payload[#payload+1] = tonumber(data.minarmedtime) or 0
  return payload
end

return Api
