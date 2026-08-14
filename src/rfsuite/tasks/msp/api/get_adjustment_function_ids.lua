-- EdgeTX MSP API: GET_ADJUSTMENT_FUNCTION_IDS (ported from Ethos)
-- Self-contained, no core/Ethos dependencies

local Api = {
  command = 167, -- MSP_GET_ADJUSTMENT_FUNCTION_IDS
  simulatorResponse = {
    1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  }
}

local ADJUSTMENT_RANGE_MAX = 42

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 1 then return nil end
  local functions = {}
  for i = 1, ADJUSTMENT_RANGE_MAX do
    functions[i] = tonumber(buf[i]) or 0
  end
  return { adjustment_function_ids = functions }
end

return Api
