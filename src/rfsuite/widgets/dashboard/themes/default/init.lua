local init = {
  name = "Default",
  preflight = "preflight.lua",
  inflight = "inflight.lua",
  postflight = "postflight.lua",
  configure = "configure.lua",
  standalone = false,
  fullscreen = "theme",
  keys = { sys = "openTool", tele = "openView:menu", mdl = "none" },
}

return init
