-- EdgeTX MSP API: BOXIDS
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 119, -- MSP_BOXIDS
  simulatorResponse = {0, 1, 2, 53, 27, 36, 45, 13, 52, 19, 20, 26, 31, 51, 55, 56, 57},
}

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local ids = {}
  for i = 1, #buf do
    ids[#ids + 1] = buf[i]
  end
  return { box_ids = ids }
end

return Api
