-- EdgeTX MSP API: mode_ranges (ported from Ethos)

local Api = {
  command = 34,
  simulatorResponse = (function()
    local resp = {1, 0, 216, 40, 0, 0, 80, 120}
    for _ = 1, 18 do
      resp[#resp + 1] = 0
      resp[#resp + 1] = 0
      resp[#resp + 1] = 136
      resp[#resp + 1] = 136
    end
    return resp
  end)()
}

local function to_signed8(v)
  v = tonumber(v) or 0
  if v >= 128 then return v - 256 end
  return v
end

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local i = 1
  local ranges = {}
  while i <= #buf do
    local modeId = buf[i]; if modeId == nil then break end; modeId = tonumber(modeId); i = i + 1
    local auxChannelIndex = tonumber(buf[i]); i = i + 1
    local startStep = to_signed8(buf[i]); i = i + 1
    local endStep = to_signed8(buf[i]); i = i + 1
    if modeId == nil or auxChannelIndex == nil or startStep == nil or endStep == nil then break end
    ranges[#ranges + 1] = {
      id = modeId,
      auxChannelIndex = auxChannelIndex,
      range = { start = 1500 + (startStep * 5), ["end"] = 1500 + (endStep * 5) }
    }
  end
  return {mode_ranges = ranges}
end

return Api
