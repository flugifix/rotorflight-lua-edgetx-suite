return function(ctx)
  local i18n = ctx and ctx.i18n or nil
  local keyPrefix = "app.pages.tools_copy_profiles"
  
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

  local title = tr("help_title", "Copy Profile")
  local p1 = tr("help_p1", "Copy settings between profiles.")
  local p2 = tr("help_p2", "Select the type (PID or Rate) and the source/destination profiles.")

  return {
    title = title,
    message = p1 .. "\n\n" .. p2
  }
end
