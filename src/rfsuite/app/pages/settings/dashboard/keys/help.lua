return function(ctx)
  local i18n = ctx and ctx.i18n
  local message = i18n and i18n.t and i18n.t("app.pages.settings_dashboard_keys.help_message")
    or "Radio-wide fullscreen shortcuts, including before FC connection. Theme keeps theme/host defaults; "
      .. "Nothing disables a key. Other actions override the theme. Tool and Flight Log keep safety guards. "
      .. "Short RTN stays Back/Close; long RTN leaves fullscreen.\nPAGE >: action for the next-page key.\nPAGE "
      .. "<: action for the previous-page key.\nMDL: action for the model key.\nSYS: action for the system "
      .. "key.\nTELE: action for the telemetry key."
  return { message = message }
end
