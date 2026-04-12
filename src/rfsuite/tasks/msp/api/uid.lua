local Api = {
  command = 160,
  simulatorResponse = {
    43, 0, 34, 0,
    9, 81, 51, 52,
    52, 56, 53, 49
  }
}

local function u32LeToHex(b1, b2, b3, b4)
  return string.format("%02x%02x%02x%02x", b1, b2, b3, b4)
end

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 12 then return nil end

  local function byteAt(i)
    local v = tonumber(buf[i]) or 0
    if v < 0 then v = 0 end
    if v > 255 then v = 255 end
    return v
  end

  local uid = u32LeToHex(byteAt(1), byteAt(2), byteAt(3), byteAt(4))
    .. u32LeToHex(byteAt(5), byteAt(6), byteAt(7), byteAt(8))
    .. u32LeToHex(byteAt(9), byteAt(10), byteAt(11), byteAt(12))

  return {
    mcuId = uid
  }
end

return Api
