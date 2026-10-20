-- Small, labelled mechanical sketches. Geometry is prepared at build time;
-- reactive lines select fixed-size, non-negative point tables from cached state.
local M = {}
function M.append(children, w, card, x, y, width, height)
  local ink, accent = COLOR_THEME_PRIMARY1, COLOR_THEME_SECONDARY1
  local kind,L=card.art,w.L
  local scale = math.min(width / 220, height / 160)
  x, y = x + math.floor((width - 220*scale)/2), y + math.floor((height - 160*scale)/2)
  local function px(v) return math.floor(x + v*scale + 0.5) end
  local function py(v) return math.floor(y + v*scale + 0.5) end
  local function points(p)
    local out = {}
    for i,v in ipairs(p) do
      local a,b=v[1],v[2]
      if kind=="heliLift" then
        local dx,dy=a-38,b-128
        a,b=15+(38+dx*0.939693+dy*0.342020)*0.9,10+(128-dx*0.342020+dy*0.939693)*0.9
      end
      out[i]={px(a),py(b)}
    end
    return out
  end
  local function line(p, color, thick)
    local item = { type = "line", pts = points(p), color = color or ink, thickness = thick or 2 }
    children[#children+1] = item
    return item
  end
  local function rect(a,b,c,d,color)
    local item = { type = "rectangle", x = px(a), y = py(b),
      w = px(a+c)-px(a), h = py(b+d)-py(b), color = color or ink, thickness = 2 }
    children[#children+1] = item
    return item
  end
  local function text(a,b,c,value)
    local item = { type = "label", x = px(a), y = py(b), w = px(a+c)-px(a),
      text = value, color = ink, font = SMLSIZE }
    children[#children+1] = item
    return item
  end
  local function arrow(a,b,c,d,color)
    local dx, dy = c-a, d-b
    local length = math.sqrt(dx*dx + dy*dy)
    local ux, uy = dx/length, dy/length
    return line({{a,b},{c,d},{c-ux*9-uy*5,d-uy*9+ux*5},{c,d},{c-ux*9+uy*5,d-uy*9-ux*5}},color or accent,3)
  end
  local function meter(a,b,c,get)
    line({{a,b},{a+c,b}},ink,1)
    line({{a+c/2,b-4},{a+c/2,b+4}},ink,1)
    local pts=points({{a+c/2,b-6},{a+c/2,b+6}})
    local item=line({{a+c/2,b-6},{a+c/2,b+6}},accent,3)
    local last
    item.pts=function()
      local value=math.max(-1,math.min(1,get() or 0))
      if value~=last then
        local pos=px(a+c*(value+1)/2)
        pts[1][1],pts[2][1],last=pos,pos,value
      end
      return pts
    end
  end
  if kind == "throttle" then
    text(5,0,210,L.throttle)
    rect(28,35,164,55);line({{45,62},{175,62}})
    line({{45,49},{45,75}});line({{175,49},{175,75}})
    arrow(63,111,157,111)
    meter(10,132,196,function()
      local map=w.data.rx_map.throttle or 4
      local raw=w.data.rx_channels and w.data.rx_channels.channels[map+1]
      return raw and (raw-w.data.rc_config.rc_center)/math.max(1,w.data.rc_config.rc_deflection) or 0
    end)
    text(5,141,210,L.testOutput)
  elseif kind == "sticks" then
    text(5,0,210,L.checkSticks)
    local keys={"aileron","elevator","rudder","collective"}
    for i,key in ipairs(keys) do
      local k=key
      text(5,21+(i-1)*31,72,({L.roll,L.pitch,L.yaw,L.collective})[i])
      meter(80,31+(i-1)*31,125,function()
        local channel=w.data.rx_map[k] or 0
        local value=w.data.rx_channels and w.data.rx_channels.channels[channel+1]
        return value and (value-w.data.rc_config.rc_center)/w.data.rc_config.rc_deflection or 0
      end)
    end
    line({{5,149},{210,149}},ink,1)
  elseif kind == "rates" then
    text(5,0,210,L.rateCurve)
    line({{22,26},{22,128},{207,128}})
    line({{22,77},{207,77}},ink,1)
    local prepared={}
    for i,style in ipairs({{180,0.4},{250,0.4},{400,0.3}}) do
      local p={}
      for n=0,24 do
        local v=n/24
        p[#p+1]={22+185*v,128-100*style[1]/400*(v*(1-style[2])+v^2.75*style[2])}
      end
      prepared[i]=points(p)
    end
    local curve=line({{22,128},{207,28}},accent,3)
    curve.pts=function()
      local style=w.rateStyles[w.rateProfile] or (w.rateMatched or {})[w.rateProfile]
      return prepared[style or 2]
    end
    text(5,140,210,L.artExample)
    line({{22,128},{22,132}});line({{207,128},{207,132}})
  elseif kind == "pulses" then
    text(5,0,210,L.pulseTrain)
    local prepared,windows={},{}
    local initial=w.data.servo_configurations.servos[0] or {rate=50,mid=1520}
    local specs={{math.max(1,initial.rate),initial.mid},{50,1520},{333,1520},{560,760}}
    local captions={initial.rate.." Hz / "..initial.mid.." us","50 Hz / 1520 us","333 Hz / 1520 us","560 Hz / 760 us"}
    for i,spec in ipairs(specs) do
      local pts={}
      local period=1000/spec[1]
      local window=math.min(20,period*12)
      windows[i]=string.format("%.1f ms",window)
      -- Fixed 50 points per variant: pad the last point for LVGL's live pts.
      local time=0
      while time<window and #pts<48 do
        local a,b=math.min(time,window),math.min(time+spec[2]/1000,window)
        pts[#pts+1]={10+a*200/window,112};pts[#pts+1]={10+a*200/window,64}
        pts[#pts+1]={10+b*200/window,64};pts[#pts+1]={10+b*200/window,112}
        time=time+period
      end
      pts[#pts+1]={210,112}
      while #pts<50 do pts[#pts+1]={210,112} end
      prepared[i]=points(pts)
    end
    local function mode()
      local s=w.data.servo_configurations.servos[0]
      return s and s.rate==560 and 4 or s and s.rate==333 and 3 or s and s.rate==50 and 2 or 1
    end
    local wave=line({{10,112},{210,112}},accent,2)
    wave.pts=function() return prepared[mode()] end
    text(5,29,210,function() return captions[mode()] end)
    text(5,140,210,function() return windows[mode()] end)
    line({{10,120},{210,120}});line({{10,117},{10,124}});line({{210,117},{210,124}})
  elseif kind == "switch" then
    text(5,0,210,L.move)
    rect(72,71,75,66);rect(88,86,43,10,accent)
    local p={points({{109,89},{79,39}}),points({{109,89},{139,39}})}
    local lever=line({{109,89},{79,39}},accent,4)
    lever.pts=function() return p[(w.animationFrame or 0)+1] end
    arrow(65,42,145,42);text(5,141,210,L.artExample)
    line({{109,96},{109,123}});line({{92,123},{126,123}})
  elseif kind == "tail" or kind == "tailMotor" or kind == "tail22" then
    text(5,0,210,L.artTop)
    line({{199,72},{48,70},{48,87},{199,90},{199,72}},ink,3)
    rect(34,62,27,32,accent);line({{48,94},{48,127}},ink,3)
    line({{16,128},{81,128}},accent,4)
    if kind=="tailMotor" then
      arrow(93,108,93,142)
      if w.data.mixer_config.tail_rotor_mode==2 then arrow(9,142,9,108) end
    else
      rect(38,105,20,9,accent);line({{58,110},{74,110},{74,98},{194,98}})
      rect(178,104,26,19);arrow(16,113,16,88)
    end
    text(5,141,210,kind=="tail22" and "22°" or L.tail)
  elseif kind == "swash" then
    -- Configurator swash.js: nose up, servo 1 at the front; 90L/90V use two servos.
    local layouts = { {0,120,240}, {0,-120,120}, {0,-135,135}, {0,-140,140}, {0,-90}, {-45,45} }
    local prepared = {}
    for mode, angles in ipairs(layouts) do
      local geometry = {}
      for i=1,3 do
        local rad = (angles[i] or 0)*math.pi/180
        local a,b = 108+math.sin(rad)*68, 88-math.cos(rad)*48
        geometry[i] = { pts=points({{108,88},{a,b}}), pos={px(a-6),py(b-8)} }
        if mode==1 then
          geometry[i] = { pts=points({{35,49+(i-1)*30},{75,49+(i-1)*30}}), pos={px(9),py(41+(i-1)*30)} }
        end
      end
      prepared[mode] = geometry
    end
    for mode=2,4 do
      local geometry={}
      for i=1,3 do
        local rad=layouts[mode][i]*math.pi/180
        local a,b=108+math.sin(rad)*68,88+math.cos(rad)*48
        geometry[i]={pts=points({{108,88},{a,b}}),pos={px(a-6),py(b-8)}}
      end
      prepared[mode+6]=geometry
    end
    local function mode() return math.max(1, math.min(6, w.data.mixer_config.swash_type or 1)) end
    local function variant()
      local s=mode();return w.swashRear and s>=2 and s<=4 and s+6 or s
    end
    local captions={L.direct,"120","135","140","90L","90V"}
    local function geometric() return mode() > 1 end
    text(5,0,210,function() return mode()==1 and L.artServoRoles or width<180 and L.artFront or L.artTop end)
    arrow(184,58,184,29).visible=geometric
    text(125,8,92,L.artFront).visible=function() return geometric() and width>=180 end
    line({{108,62},{139,76},{139,100},{108,115},{77,100},{77,76},{108,62}}).visible=geometric
    rect(103,83,10,10,accent).visible=geometric
    for i=1,3 do
      local index = i
      local item = line({{108,88},{108,40}},accent,3)
      item.pts = function() return prepared[variant()][index].pts end
      item.visible = function() return mode() <= 4 or index <= 2 end
      local number = { type="label", text=tostring(i), font=SMLSIZE, color=ink,
        pos=function()
          local p=prepared[variant()][index].pos
          return p[1],p[2]
        end, visible=item.visible }
      children[#children+1] = number
      text(88,41+(i-1)*30,130,({L.pitch,L.roll,L.collective})[i]).visible=function() return mode()==1 end
    end
    text(5,138,210,function() return captions[mode()] end)
    text(102,121,22,"4").visible=function() return not w:motorised() and mode()>1 end
    local cw=points({{170,111},{194,111},{194,93},{188,99},{194,93},{200,99}})
    local ccw=points({{194,111},{170,111},{170,93},{164,99},{170,93},{176,99}})
    local rotation=line({{170,111},{194,111}},accent,2)
    rotation.pts=function() return w.data.mixer_config.main_rotor_dir==0 and cw or ccw end
  elseif kind == "swashRoll" or kind == "swashPitch" or kind == "swashLift" or kind == "level" then
    local tilt = (kind=="swashRoll" or kind=="swashPitch") and 13 or 0
    local lift = kind=="swashLift" and 17 or 0
    local left,right = 73-lift-tilt,73-lift+tilt
    text(5,0,210,kind=="swashPitch" and L.artSide or L.artRear)
    line({{110,29},{110,131}},ink,3)
    rect(91,26,38,9); rect(49,128,122,11)
    line({{63,73},{91,73}}); line({{129,73},{157,73}})
    line({{65,left},{155,right}},accent,4)
    line({{65,left+5},{65,119},{48,119}})
    line({{155,right+5},{155,119},{172,119}})
    if kind=="level" then
      rect(130,32,61,16,accent); rect(155,36,10,8,accent)
      text(5,141,210,L.artLevel)
    elseif kind=="swashLift" then
      arrow(187,109,187,66); text(5,141,210,L.collective)
    else
      arrow(185,58,185,100)
      text(5,141,210,kind=="swashRoll" and L.roll or L.pitch)
      if kind=="swashPitch" then arrow(144,135,204,135) end
    end
  elseif kind == "servo" or kind == "servoMove" or kind == "servoCentre" then
    text(5,0,210,L.servo)
    rect(35,74,115,58); rect(22,91,13,12); rect(150,91,13,12)
    rect(43,65,30,9); rect(51,48,11,11,accent)
    line({{57,53},{143,53}},accent,4)
    rect(79,94,55,23,accent)
    line({{150,115},{175,115},{185,136},{211,136}})
    line({{150,120},{170,120},{181,141},{211,141}},accent)
    line({{150,125},{165,125},{178,146},{211,146}})
    line({{57,50},{57,56}},ink)
    if kind=="servoMove" then
      line({{143,53},{143,30}},accent); arrow(177,75,177,30)
      text(5,141,160,L.movesUp)
    elseif kind=="servoCentre" then
      line({{143,53},{143,21}}); line({{133,53},{133,43},{143,43}},accent)
      text(5,141,200,L.artNeutral)
    end
  elseif kind == "pitch" then
    text(5,0,210,L.artSide)
    -- Blade section against a horizontal reference, with a pitch gauge below.
    line({{22,78},{198,78}})
    line({{25,83},{184,56},{198,59},{40,88},{25,83}},accent,3)
    line({{81,88},{81,115},{143,115},{143,76}})
    rect(77,115,70,22); text(84,117,62,"9°")
    line({{154,78},{154,70},{152,64}},accent)
    text(5,141,210,L.artReference)
  elseif kind == "board" then
    text(5,0,210,L.artTop)
    line({{110,30},{81,63},{82,104},{101,116},{105,139},{115,139},{119,116},{138,104},{139,63},{110,30}},ink,3)
    line({{29,81},{191,81}},ink,3)
    rect(93,69,34,34,accent); rect(103,79,14,14)
    line({{99,74},{99,98},{121,98},{121,74}},accent)
    arrow(165,63,165,30); text(119,8,98,L.artFront)
    text(5,141,210,L.orientation)
  elseif kind == "gyroRoll" or kind == "gyroPitch" or kind == "gyroYaw" then
    text(5,0,210,kind=="gyroPitch" and L.artSide or kind=="gyroYaw" and L.artTop or L.artRear)
    if kind=="gyroYaw" then
      line({{110,33},{91,66},{95,93},{106,103},{106,136},{115,136},{115,103},{127,93},{131,66},{110,33}})
      line({{47,76},{173,76}},ink,3)
      arrow(47,126,47,63,ink); arrow(173,63,173,126)
    else
      line({{110,43},{110,115}})
      line({{68,115},{153,115},{164,134},{57,134},{68,115}})
      line({{43,59},{174,81}},ink,3)
      line({{65,93},{155,77}},accent,4)
      arrow(190,42,190,88,ink); arrow(28,120,28,76)
    end
    text(5,141,210,L.artAgainst)
  else
    -- Recognisable side silhouette with head, canopy, boom, tail rotor and skids.
    text(5,0,210,L.artSide)
    line({{19,105},{28,77},{49,65},{90,69},{106,100},{91,111},{35,111},{19,105}},ink,3)
    line({{31,78},{55,75},{67,96},{24,96}},accent)
    line({{98,83},{187,71},{193,80},{104,100}},ink,3)
    line({{190,73},{190,49},{203,76},{196,94},{190,80}})
    line({{64,68},{64,47}},ink,3)
    line({{15,45},{131,45}},accent,4)
    if w.step==1 or w.step==9 or w.step==11 then
      line({{84,33},{102,57}},accent,3);line({{102,33},{84,57}},accent,3)
    end
    line({{184,55},{203,90}},accent,3); line({{179,82},{207,63}},accent,3)
    line({{38,111},{34,128},{101,128},{96,111}}); line({{20,128},{116,128}},ink,3)
    arrow(70,145,24,145); text(89,137,125,kind=="heliLift" and "20°" or L.artFront)
  end
  if card.meter then meter(10,132,196,card.meter) end
end
return M
