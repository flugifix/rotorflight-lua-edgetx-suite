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
  -- What a profile will hold: its current rates, or the chosen style applied to a copy of them.
  -- The copy is made once per choice, not per frame.
  local previews={}
  local function shown(index)
    local t=w.rateTunings and w.rateTunings[index]
    if not t then return nil end
    local s=w.rateStyles[index]
    if not s then return t end
    local p=previews[index]
    if not p or p.style~=s or p.base~=t then
      local copy={};for k,v in pairs(t) do copy[k]=v end
      H.style(copy,s,ratesType);p={style=s,base=t,tuning=copy};previews[index]=p
    end
    return p.tuning
  end
  -- A text built from a profile's shown rates, formatted again only when they change.
  local function memo(index,format)
    -- false, not nil: a profile not read yet must still produce its placeholder once.
    local last,text=false,nil
    return function()
      local t=shown(index)
      if t~=last then last,text=t,t and format(t) or "--" end
      return text
    end
  end
  local function number(v) return v and tostring(v) or "--" end
  local function caption(t)
    local c,y,ce,ye=H.rateValues(t)
    return string.format(L.rateLine,L.cyclic,number(c),L.expo,number(ce)).."\n"..
      string.format(L.rateLine,L.yaw,number(y),L.expo,number(ye)).."\n"..
      L.collective.." "..string.format(L.degreeValue,number(H.collective(t)))
  end
  local function short(t)
    local c,y=H.rateValues(t)
    return string.format(L.rateShort,number(c),number(y),number(H.collective(t)))
  end
  local switched=H.profileMode(w.data.adjustment_ranges.adjustment_ranges)==1
    and H.rangeOf(w.data.adjustment_ranges.adjustment_ranges,1)~=nil
  local styles={L.styleCustom,L.styleTrainer,L.styleSport,L.style3d}
  local cards={}
  for position,id in ipairs(profiles) do
    local index=id
    local function style()
      return w.rateStyles and w.rateStyles[index] or w.rateMatched and w.rateMatched[index]
    end
    local rows={}
    if switched and position==1 then
      rows[#rows+1]=w:button(L.suggest,function()
        for i,profile in ipairs(profiles) do w.rateStyles[profile]=i end;w:touch("rc_tuning")
      end,function() return #profiles==3 end)
    end
    -- One tile per style; Custom keeps the profile's own rates and is marked while none matches.
    for n,name in ipairs(styles) do
      local choice=n>1 and n-1 or nil
      rows[#rows+1]={ kind="tile",label=name,
        selected=function() return style()==choice end,
        press=function() w.rateStyles[index]=choice;w:touch("rc_tuning") end }
    end
    local title=switched and string.format(L.switchRateProfile,position,index+1) or string.format(L.rateProfileTitle,index+1)
    local card=w:cardDef(title,L.ratesHint.."\n"..L.rateNoMatch,rows,enter,"rates")
    card.rateStyle=style
    card.summary=function() return style() and L.ratesHint or L.rateNoMatchShort end
    card.caption,card.captionShort=memo(index,caption),memo(index,short)
    card.wideText,card.dense=true,#rows>4
    cards[#cards+1]=card
  end
  -- The step closes on a table: a column per profile, a row per axis, as Save & next will write them.
  local columns,cyclicRow,yawRow,collectiveRow={},{},{},{}
  for _,id in ipairs(profiles) do
    columns[#columns+1]=string.format(L.rateProfileTitle,id+1)
    cyclicRow[#cyclicRow+1]=memo(id,function(t)
      local c,_,ce=H.rateValues(t);return string.format(L.rateCell,number(c),number(ce))
    end)
    yawRow[#yawRow+1]=memo(id,function(t)
      local _,y,_,ye=H.rateValues(t);return string.format(L.rateCell,number(y),number(ye))
    end)
    collectiveRow[#collectiveRow+1]=memo(id,function(t) return string.format(L.degreeValue,number(H.collective(t))) end)
  end
  local done=w:cardDef(L.ratesSet,L.ratesHint.."\n"..L.rateNoMatch,{},enter)
  done.summary=function() return next(w.rateStyles) and L.stepChanged or L.stepUnchanged end
  done.table={columns=columns,rows={{label=L.cyclic,cells=cyclicRow},{label=L.yaw,cells=yawRow},
    {label=L.collective,cells=collectiveRow}},legend=L.rateLegend}
  done.wideText=true
  cards[#cards+1]=done
  return cards
end
