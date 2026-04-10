local Helper = {}

function Helper.readU8(buf)
  local offset = buf.offset or 1
  local value = buf[offset] or 0
  buf.offset = offset + 1
  return value
end

function Helper.readU16(buf)
  local offset = buf.offset or 1
  local value = buf[offset] or 0
  value = bit32.bor(value, bit32.lshift(buf[offset + 1] or 0, 8))
  buf.offset = offset + 2
  return value
end

function Helper.readU32(buf)
  local offset = buf.offset or 1
  local value = 0
  for i = 0, 3 do
    value = bit32.bor(value, bit32.lshift(buf[offset + i] or 0, i * 8))
  end
  buf.offset = offset + 4
  return value
end

return Helper
