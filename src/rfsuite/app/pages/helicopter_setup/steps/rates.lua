return function(w)
  local L = w.L
  w.rateStyles = w.rateStyles or {}
  w.rateProfile = w.rateProfile or w.data.status.current_control_rate_profile_index
  w.commit = function()
    if not next(w.rateStyles) then return end
    w:profileLoop("rates", w.data.status.control_rate_profile_count, function(d, i)
      if w.rateStyles[i] then w.math.style(d, w.rateStyles[i]) end
    end)
  end
  return { w:cardDef(L.rates, L.ratesHint, {
    { kind = "number", label = L.rateProfile, min = 1, max = w.data.status.control_rate_profile_count,
      get = function() return w.rateProfile + 1 end, set = function(v) w.rateProfile = v - 1 end },
    { kind = "choice", label = L.flyingStyle, values = { L.keep, L.trainerRates, L.sportRates, L.threeDRates },
      get = function() return (w.rateStyles[w.rateProfile] or 0) + 1 end,
      set = function(v) w.rateStyles[w.rateProfile] = v > 1 and v - 1 or nil; w:touch("rc_tuning") end },
    w:button(L.suggest, function()
      for i = 0, math.min(w.data.status.control_rate_profile_count, 3) - 1 do w.rateStyles[i] = i + 1 end
      w:touch("rc_tuning")
    end),
    w:value(L.collective, function() return w.math.collective(w.data.rc_tuning) or "--" end)
  }, nil, "pitch") }
end
