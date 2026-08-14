-- EdgeTX MSP API: BOXNAMES
-- Ported to EdgeTX schema (Api table + parse)

local Api = {
  command = 116, -- MSP_BOXNAMES
  simulatorResponse = {},
}

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  local names = {}
  local chars = {}
  local function flushName()
    if #chars == 0 then return end
    names[#names + 1] = table.concat(chars)
    chars = {}
  end
  for i = 1, #buf do
    local b = buf[i]
    if b == 59 or b == 0 then -- semicolon or NUL
      flushName()
    elseif b >= 32 and b <= 126 then
      chars[#chars + 1] = string.char(b)
    end
  end
  flushName()
  return { box_names = names }
end

return Api
