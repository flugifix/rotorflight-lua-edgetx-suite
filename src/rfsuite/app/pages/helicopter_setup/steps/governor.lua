return function(w)
  local L = w.L
  local function mode()
    if (w.data.feature_config.enabledFeatures & (1 << 26)) == 0 then return 0 end
    return w.data.governor_config.gov_mode
  end
  local function setMode(v)
    w:field("governor_config", "gov_mode", v - 1, true)
    w:feature(26, v > 1)
    w.rebootPending = true
    if v < 4 and w.data.governor_config.gov_throttle_type == 1 then
      w:field("governor_config", "gov_throttle_type", 0, true)
    end
  end
  return { w:cardDef(L.governor, L.governorHint, {
    { kind = "choice", label = L.mode, values = { L.off, L.limit, L.direct, L.electric, L.nitro },
      get = function() return mode() + 1 end, set = setMode },
    { kind = "choice", label = L.throttleType, values = { L.normal, L.switch, L.functionMode },
      get = function() return w.data.governor_config.gov_throttle_type + 1 end,
      set = function(v)
        if mode()==0 then return end
        if v == 2 and mode() < 3 then w.message = L.governorSwitch; return end
        w:field("governor_config", "gov_throttle_type", v - 1, true)
      end,enabled=function() return mode()>0 end },
    w:value(L.fastRpm, function() return w:fastRpm() and L.available or L.rpmMissing end)
  }) }
end
