-- A small wireframe driven by decoded MSP_ATTITUDE, never by a native getter.
-- Body axes: forward, right, up. Positive pitch lowers the nose; positive roll
-- lowers the right side, matching the Board Alignment page's attitude labels.
local M = {}
local vertices = {
  {2,0,.1},{.5,0,.8},{1,-.5,0},{1,.5,0},{-.8,-.35,0},{-.8,.35,0},
  {-.7,0,.45},{-2.6,0,.25},{-2.6,0,.8},
  {1.2,-.65,-.55},{-1,-.65,-.55},{1.2,.65,-.55},{-1,.65,-.55},
  {0,0,1.05},{0,0,.6},{0,-2.35,1.05},{0,2.35,1.05},
  {2.2,0,1.05},{-2.2,0,1.05},{-2.6,-.1,.65},{-2.6,-.1,-.15},
  {-2.2,-.1,.25},{-2.95,-.1,.25}
}
local paths = {{1,3,5,7,2,1,4,6,7},{3,2,4,1,3},{5,6,4},{7,8,9,8},
  {15,14},{16,17},{18,19},{3,10,11,5},{4,12,13,6},{20,21},{22,23}}
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<10000 end
function M.new(children,w,x,y,width,height)
  local s={projected={},valid=false,readout=w.L.attitudeWaiting}
  local cx,cy=x+width/2,y+(height-22)/2
  for i=1,#vertices do s.projected[i]={0,0} end
  local function project(roll,pitch)
    local r,p=roll*math.pi/180,pitch*math.pi/180
    local cr,sr,cp,sp=math.cos(r),math.sin(r),math.cos(p),math.sin(p)
    local minX,maxX,minY,maxY=math.huge,-math.huge,math.huge,-math.huge
    for i,v in ipairs(vertices) do
      local yr,zr=v[2]*cr+v[3]*sr,-v[2]*sr+v[3]*cr
      local xp,zp=v[1]*cp+zr*sp,-v[1]*sp+zr*cp
      local out=s.projected[i]
      out[1],out[2]=.94*xp+.34*yr,-.12*xp+.33*yr-.94*zp
      minX,maxX=math.min(minX,out[1]),math.max(maxX,out[1])
      minY,maxY=math.min(minY,out[2]),math.max(maxY,out[2])
    end
    -- Fit the complete helicopter, including steep tilts, into compact displays.
    local scale=math.min((width-12)/(maxX-minX),(height-28)/(maxY-minY))
    local midX,midY=(minX+maxX)/2,(minY+maxY)/2
    for _,out in ipairs(s.projected) do
      out[1]=math.floor(cx+scale*(out[1]-midX)+.5)
      out[2]=math.floor(cy+scale*(out[2]-midY)+.5)
    end
  end
  function s:update(d,at,time,allowed)
    local valid=allowed and d and finite(d.roll) and finite(d.pitch) and at and time>=at and time-at<=200
    self.valid=valid==true
    if not self.valid then self.readout=w.L.attitudeWaiting;return end
    if self.roll~=d.roll or self.pitch~=d.pitch then
      self.roll,self.pitch=d.roll,d.pitch
      project(d.roll,d.pitch)
      self.readout=string.format("%s %.1f°   %s %.1f°",w.L.roll,d.roll,w.L.pitch,d.pitch)
    elseif self.readout==w.L.attitudeWaiting then
      self.readout=string.format("%s %.1f°   %s %.1f°",w.L.roll,d.roll,w.L.pitch,d.pitch)
    end
  end
  -- Even hidden/stale native lines always receive valid, fixed-size point tables.
  project(0,0)
  for i,path in ipairs(paths) do
    local pts={}
    for j,index in ipairs(path) do pts[j]=s.projected[index] end
    children[#children+1]={type="line",pts=function() return pts end,
      visible=function() return s.valid end,thickness=i==2 and 3 or 2,
      color=(i==2 or i==5 or i==6 or i==7) and COLOR_THEME_SECONDARY1 or COLOR_THEME_PRIMARY1}
  end
  children[#children+1]={type="label",x=x,y=y+height-22,w=width,h=22,font=SMLSIZE,
    color=COLOR_THEME_PRIMARY1,text=function() return s.readout end}
  return s
end
return M
