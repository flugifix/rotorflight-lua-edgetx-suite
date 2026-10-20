return function(w)
  local L = w.L
  w.validate = function()
    if w.data.governor_config.gov_throttle_type == 1 and w.data.governor_config.gov_mode < 3 then
      w.message = L.governorSwitch; return false
    end
    return true
  end
  w.commit = function() w:feature(26, w.data.governor_config.gov_mode > 0) end
  return { w:cardDef(L.governor, L.governorHint, {
    w:c("governor_config", "gov_mode", L.mode, { L.off, L.limit, L.direct, L.electric, L.nitro }, true),
    w:c("governor_config", "gov_throttle_type", L.throttleType, { L.normal, L.switch, L.functionMode }, true),
    w:value(L.fastRpm, function() return w:fastRpm() and L.available or L.rpmMissing end)
  }) }
end
