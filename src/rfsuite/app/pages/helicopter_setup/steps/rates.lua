return function(w)
  local L,H = w.L,w.math
  w.rateStyles = w.rateStyles or {}
  w.rateProfiles = H.rateProfiles(w.data.adjustment_ranges.adjustment_ranges,
    w.data.status.current_control_rate_profile_index,w.data.status.control_rate_profile_count)
  local profiles=w.rateProfiles
  if not w.rateProfile or not w.rateTunings or not w.rateTunings[w.rateProfile] then w.rateProfile=profiles[1] end
  local ratesType=w:apiAtLeast(9) and 6 or 4
  w.commit = function()
    local chosen={}
    for _,i in ipairs(profiles) do if w.rateStyles[i] then chosen[#chosen+1]=i end end
    if #chosen==0 then return end
    w:profileLoop("rates", #chosen, function(d,i)
      H.style(d,w.rateStyles[i],ratesType); w.rateTunings[i]=d
    end,chosen)
    w:run(function() w.rateStyles={} end)
  end
  local function enter()
    if w.rateLoaded then return end
    w.rateLoaded,w.transition,w.rateTunings,w.rateMatched=true,true,{},{}
    local original=w.data.status.current_control_rate_profile_index+128
    w.restoreProfile=original
    for _,id in ipairs(profiles) do
      local index=id
      w:action("set_pid_profile",{index+128})
      w:read("rc_tuning",function(d) w.rateTunings[index]=d; w.rateMatched[index]=H.matchStyle(d,ratesType) end)
    end
    w:action("set_pid_profile",{original},function() w.restoreProfile=nil end)
    w:read("rc_tuning",function(d) w.data.rc_tuning=d end)
    w:run(function() w.transition=nil end)
  end
  local values={};for i,id in ipairs(profiles) do values[i]=tostring(id+1) end
  return { w:cardDef(L.rates, L.ratesHint, {
    { kind="choice",label=L.rateProfile,values=values,
      get=function() for i,id in ipairs(profiles) do if id==w.rateProfile then return i end end; return 1 end,
      set=function(v) w.rateProfile=profiles[v] or profiles[1] end },
    { kind="choice",label=L.flyingStyle,values={L.keep,L.trainerRates,L.sportRates,L.threeDRates},
      get=function() return (w.rateStyles and w.rateStyles[w.rateProfile] or w.rateMatched and w.rateMatched[w.rateProfile] or 0)+1 end,
      set=function(v) w.rateStyles[w.rateProfile]=v>1 and v-1 or nil;w:touch("rc_tuning") end },
    w:button(L.suggest,function()
      for i,id in ipairs(profiles) do w.rateStyles[id]=i end;w:touch("rc_tuning")
    end,function() return #profiles==3 end),
    w:value(L.collective,function() return H.collective((w.rateTunings or {})[w.rateProfile] or w.data.rc_tuning) or "--" end)
  },enter,"rates") }
end
