local Api = {
  command = 4, -- MSP_BOARD_INFO
  simulatorResponse = {
    82, 70, 76, 84, -- board_identifier_1..4 ("RFLT")
    0, 0,           -- hardware_revision
    0,              -- fc_type
    0,              -- target_capabilities
    0,              -- target_name_length
    -- target_name_1..32
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0,              -- board_name_length
    -- board_name_1..20
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0,              -- board_design_length
    -- board_design_1..12
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0,              -- manufacturer_id_length
    -- manufacturer_id_1..4
    0, 0, 0, 0,
    -- signature_1..32
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, -- mcu_type_id
    0, -- configuration_state
    0, 0, -- gyro_sample_rate_hz
    0, 0, 0, 0, -- configuration_problems
    0, -- spi_device_count
    0  -- i2c_device_count
  }
}

local function parseString(buf, startIdx, len)
  local out = ""
  for i = 0, len - 1 do
    local b = tonumber(buf[startIdx + i]) or 0
    if b == 0 then break end
    out = out .. string.char(b)
  end
  return out
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 20 then return nil end
  local idx = 1
  local board_identifier = string.char(buf[idx] or 0, buf[idx+1] or 0, buf[idx+2] or 0, buf[idx+3] or 0)
  idx = idx + 4
  local hardware_revision = (buf[idx] or 0) + ((buf[idx+1] or 0) * 256)
  idx = idx + 2
  local fc_type = buf[idx] or 0
  idx = idx + 1
  local target_capabilities = buf[idx] or 0
  idx = idx + 1
  local target_name_length = buf[idx] or 0
  idx = idx + 1
  local target_name = parseString(buf, idx, target_name_length)
  idx = idx + 32
  local board_name_length = buf[idx] or 0
  idx = idx + 1
  local board_name = parseString(buf, idx, board_name_length)
  idx = idx + 20
  local board_design_length = buf[idx] or 0
  idx = idx + 1
  local board_design = parseString(buf, idx, board_design_length)
  idx = idx + 12
  local manufacturer_id_length = buf[idx] or 0
  idx = idx + 1
  local manufacturer_id = parseString(buf, idx, manufacturer_id_length)
  idx = idx + 4
  -- signature, mcu_type_id, etc. können bei Bedarf ergänzt werden
  return {
    board_identifier = board_identifier,
    hardware_revision = hardware_revision,
    fc_type = fc_type,
    target_capabilities = target_capabilities,
    target_name = target_name,
    board_name = board_name,
    board_design = board_design,
    manufacturer_id = manufacturer_id
  }
end

return Api
