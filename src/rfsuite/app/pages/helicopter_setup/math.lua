-- Units and choices follow Configurator setup_wizard/{heli,rates,adjust}.js.
local M = {}
function M.round(v) return math.floor(v + 0.5) end
function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function M.signed(v) if v >= 32768 then return v - 65536 end; return v end
function M.calibrated(rate, measured)
  if measured <= 0 then return nil end
  return (rate < 0 and -1 or 1) * M.round(M.clamp(math.abs(rate) * 9 / measured, 200, 2000))
end
function M.moved(peaks, excluded, minimum)
  local best, second, high = nil, 0, 0
  for i = 1, #peaks do
    if not excluded or not excluded[i] then
      local v = peaks[i]
      if v > high then second, high, best = high, v, i elseif v > second then second = v end
    end
  end
  if high < (minimum or 300) or high < second * 2 then return nil end
  return best
end
function M.switchRange(from, to)
  local half = math.abs(to - from) / 2
  local low, high = M.round((to - half) / 25) * 25, M.round((to + half) / 25) * 25
  if to > 1900 then high = 2100 end
  if to < 1100 then low = 900 end
  return M.clamp(low, 900, 2100), M.clamp(high, 900, 2100)
end
function M.step(v) return M.round((v - 1500) / 5) & 255 end
function M.u16(p, v)
  v = M.round(v) & 65535
  p[#p + 1], p[#p + 2] = v & 255, (v >> 8) & 255
end
function M.adjustPayload(slot, r)
  local p = { slot, r.adjFunction, r.enaChannel, M.step(r.enaRange.start), M.step(r.enaRange["end"]),
    r.adjChannel, M.step(r.adjRange1.start), M.step(r.adjRange1["end"]),
    M.step(r.adjRange2.start), M.step(r.adjRange2["end"]) }
  M.u16(p, r.adjMin); M.u16(p, r.adjMax); p[#p + 1] = r.adjStep
  return p
end
function M.mapped(fn, channel, lo, hi, minimum, maximum)
  return { adjFunction = fn, enaChannel = 255, enaRange = { start = 1500, ["end"] = 1500 },
    adjChannel = channel, adjRange1 = { start = lo, ["end"] = hi },
    adjRange2 = { start = 1500, ["end"] = 1500 }, adjMin = minimum, adjMax = maximum, adjStep = 0 }
end
function M.gain(fn, channel, buttons)
  if not buttons then return M.mapped(fn, channel, 975, 2025, 50, 150) end
  local r = M.mapped(fn, channel, 1500, 1500, 25, 200)
  local base = fn == 83 and 1 or 3
  local function window(i)
    local v = 1500 + (20 + i * 10) * 5.12
    return { start = M.round((v - 25.6) / 5) * 5, ["end"] = M.round((v + 25.6) / 5) * 5 }
  end
  r.adjRange1, r.adjRange2, r.adjStep = window(base), window(base + 1), 5
  return r
end
function M.collective(t)
  if t.rates_type == 6 then return t.rcRates_4 * 0.125 end
  if t.rates_type == 4 then return math.max(t.rcRates_4, t.rates_4) * 0.25 end
end
function M.setCollective(t, degrees)
  if t.rates_type == 6 then t.rcRates_4 = M.round(degrees * 8)
  elseif t.rates_type == 4 then
    t.rates_4 = M.round(degrees * 4); t.rcRates_4 = math.min(t.rcRates_4, t.rates_4)
  else return false end
  return true
end
function M.style(t, index)
  local style = ({ {180,270,40,50}, {250,400,40,50}, {400,600,30,40} })[index]
  local collective = M.collective(t) or 12.5
  t.rates_type = 6
  for i = 1, 3 do
    t["rcRates_" .. i] = M.round(style[i == 3 and 2 or 1] / 5)
    t["rates_" .. i] = 12; t["rcExpo_" .. i] = style[i == 3 and 4 or 3]
  end
  t.rcExpo_4, t.rates_4 = 0, 12
  M.setCollective(t, collective)
end
return M
