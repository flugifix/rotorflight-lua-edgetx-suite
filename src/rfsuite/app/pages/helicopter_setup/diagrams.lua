-- Small, labelled mechanical sketches. Geometry is prepared at build time;
-- reactive lines select fixed-size, non-negative point tables from cached state.
local M = {}
function M.append(children, w, card, x, y, width, height)
  local ink, accent = COLOR_THEME_PRIMARY1, COLOR_THEME_SECONDARY1
  local scale = math.min(width / 220, height / 160)
  x, y = x + math.floor((width - 220*scale)/2), y + math.floor((height - 160*scale)/2)
  local function px(v) return math.floor(x + v*scale + 0.5) end
  local function py(v) return math.floor(y + v*scale + 0.5) end
  local function points(p)
    local out = {}
    for i, v in ipairs(p) do out[i] = { px(v[1]), py(v[2]) } end
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
  local kind, L = card.art, w.L
  if kind == "swash" then
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
    local function mode() return math.max(1, math.min(6, w.data.mixer_config.swash_type or 1)) end
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
      item.pts = function() return prepared[mode()][index].pts end
      item.visible = function() return mode() <= 4 or index <= 2 end
      local number = { type="label", text=tostring(i), font=SMLSIZE, color=ink,
        pos=function()
          local p=prepared[mode()][index].pos
          return p[1],p[2]
        end, visible=item.visible }
      children[#children+1] = number
      text(88,41+(i-1)*30,130,({L.pitch,L.roll,L.collective})[i]).visible=function() return mode()==1 end
    end
    text(5,138,210,function() return captions[mode()] end)
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
    line({{184,55},{203,90}},accent,3); line({{179,82},{207,63}},accent,3)
    line({{38,111},{34,128},{101,128},{96,111}}); line({{20,128},{116,128}},ink,3)
    arrow(70,145,24,145); text(89,137,125,L.artFront)
  end
end
return M
