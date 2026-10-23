-- Reload the real runtime across loss of model preferences; EdgeTX/FC answers are stubbed.
-- An optional runtime path runs the same expectations against a pre-fix source.
local Stubs=assert(loadfile("bin/accounting/stubs/edgetx.lua"))()
local FC=assert(loadfile("bin/accounting/stubs/fc.lua"))()
Stubs.install(".")
FC.install(Stubs)
Stubs.reset()
FC.reset()
local Runtime=assert(loadfile(arg[1] or "src/rfsuite/widgets/dashboard/runtime.lua"))()
local w=Runtime.new({x=0,y=0,w=800,h=480},{})
local function upvalue(fn,name)
  for i=1,100 do
    local key,value=debug.getupvalue(fn,i)
    if not key then break end
    if key==name then return value end
  end
  error("missing production upvalue: "..name)
end
local work=upvalue(w.background,"performBackgroundWork")
local note=upvalue(work,"noteModelTheme")
local count=0
local function eq(actual,expected,label)
  count=count+1
  assert(actual==expected,label..": "..tostring(actual).." expected "..tostring(expected))
end
local prefs={dashboard={model_overrides=true,theme_preflight="system/urban",
  cfg_system_urban_scheme="light",cfg_system_urban_slot2="rpm"}}
local first={dashboard={overrides=true,model_theme_preflight="system/urban",
  cfg_system_urban_scheme="dark",cfg_system_urban_slot1="esc_temp"}}
w.preferences=prefs
w.modelPreferences=first
_G.rfsuite.session.modelPreferences=first
note(w,prefs.dashboard,first)
w.flightMode="postflight"
w:reload(false)
eq(w.themePath,"system/urban","connected model theme")
eq(w.state.themeConfig.scheme,"dark","connected model scheme control")
w.modelPreferences=nil
_G.rfsuite.session.modelPreferences=nil
for _,phase in ipairs({"postflight","offline"}) do
  w.flightMode=phase
  w:reload(false)
  eq(w.themePath,"system/urban","kept theme")
  eq(w.state.themeConfig.scheme,"dark","kept model scheme")
  eq(w.state.themeConfig.slot1,"esc_temp","kept model slot")
  eq(w.state.themeConfig.slot2,"rpm","unmodified setting inherits")
end
_G.rfsuite.session.modelPreferences={battery={}}
w:reload(false)
eq(w.state.themeConfig.scheme,"dark","unidentified disconnected preferences do not replace model")
prefs.dashboard.cfg_system_urban_slot2="current"
w:reload(false)
eq(w.state.themeConfig.slot2,"current","standard changes still inherited")
prefs.dashboard.model_overrides=false
w:reload(false)
eq(w.state.themeConfig.scheme,"light","radio switch still disables model values")
prefs.dashboard.model_overrides=true
first.dashboard.model_theme_preflight="nil"
note(w,prefs.dashboard,{dashboard=first.dashboard})
w:reload(false)
eq(w.state.themeConfig.scheme,"dark","same-theme customization also retained")
-- These are the fields the production reconnect edge clears before it reads a new model.
w.modelTheme,w._modelThemePrefs,w._modelThemeDashboard=nil,nil,nil
_G.rfsuite.session.modelPreferences=nil
w.flightMode="preflight"
w:reload(false)
eq(w.state.themeConfig.scheme,"light","new connection cannot inherit old model")
local second={dashboard={overrides=true,model_theme_preflight="system/default",
  cfg_system_default_link_colors=true}}
w.modelPreferences=second
_G.rfsuite.session.modelPreferences=second
note(w,prefs.dashboard,second)
w.flightMode="postflight"
w:reload(false)
eq(w.themePath,"system/default","new model chooses its own theme")
eq(w.state.themeConfig.scheme,nil,"old model scheme does not leak")
eq(w.state.themeConfig.link_colors,true,"new model settings apply")
Stubs.releaseCard()
print(string.format("%d offline theme assertions, 0 failures",count))
