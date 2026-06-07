return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local keyPrefix = "app.pages.diagnostics_profile_select"
  
  local function tr(key, fallback)
    if i18n and type(i18n.t) == "function" then
        local fullKey = keyPrefix .. "." .. key
        local translated = i18n.t(fullKey)
        if translated and translated ~= fullKey and translated ~= "" then
            return translated
        end
    end
    return fallback
  end

  local title = tr("help_title", "Select Profile")
  local p1 = tr("help_p1", "Switch active PID and Rate profiles.")
  local p2 = tr("help_p2", "The display updates automatically on external changes.")

  return {
    title = title,
    message = p1 .. "\n\n" .. p2
  }
end
