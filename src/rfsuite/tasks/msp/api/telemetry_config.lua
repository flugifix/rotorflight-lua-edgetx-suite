local Api = {
  readCommand = 73,
  writeCommand = 74,
  simulatorResponse = {
    0,
    1,
    0, 0, 0, 0,
    0,
    0,
    250, 0,
    8, 0,
    3, 4, 5, 6, 8, 8, 89, 90, 91, 99,
    95, 96, 60, 15, 42, 93, 50, 51, 52, 17,
    18, 19, 23, 22, 36,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0,
    0, 0, 0, 0, 0
  }
}

local function copyBuffer(buf)
  local out = {}
  if type(buf) ~= "table" then
    return out
  end
  for i = 1, #buf do
    out[i] = tonumber(buf[i]) or 0
  end
  return out
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 6 then
    return nil
  end

  local function u8(idx)
    return tonumber(buf[idx]) or 0
  end

  local function u16(idx)
    local lo = tonumber(buf[idx]) or 0
    local hi = tonumber(buf[idx + 1]) or 0
    return lo + hi * 256
  end

  local function u32(idx)
    local b1 = tonumber(buf[idx]) or 0
    local b2 = tonumber(buf[idx + 1]) or 0
    local b3 = tonumber(buf[idx + 2]) or 0
    local b4 = tonumber(buf[idx + 3]) or 0
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
  end

  local parsed = {
    telemetry_inverted = u8(1),
    halfDuplex = u8(2),
    enableSensors = u32(3),
    buffer = copyBuffer(buf)
  }

  if #buf >= 12 then
    parsed.pinSwap = u8(7)
    parsed.crsf_telemetry_mode = u8(8)
    parsed.crsf_telemetry_link_rate = u16(9)
    parsed.crsf_telemetry_link_ratio = u16(11)

    local slotBase = 13
    for i = 1, 40 do
      local idx = slotBase + i - 1
      local byte = tonumber(buf[idx])
      if byte == nil then
        break
      end
      parsed["telem_sensor_slot_" .. tostring(i)] = byte
    end
  end

  return parsed
end

function Api.buildWritePayload(existingBuffer, updates)
  local payload = copyBuffer(existingBuffer)
  if #payload < 12 then
    payload = copyBuffer(Api.simulatorResponse)
  end

  updates = updates or {}
  local rate = tonumber(updates.crsf_telemetry_link_rate)
  local ratio = tonumber(updates.crsf_telemetry_link_ratio)

  if rate and rate >= 0 and rate <= 65535 then
    local r = math.floor(rate + 0.5)
    payload[9] = r % 256
    payload[10] = math.floor(r / 256)
  end

  if ratio and ratio >= 0 and ratio <= 65535 then
    local q = math.floor(ratio + 0.5)
    payload[11] = q % 256
    payload[12] = math.floor(q / 256)
  end

  return payload
end

return Api