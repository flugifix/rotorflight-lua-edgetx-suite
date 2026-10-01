local HelpView = {}

function HelpView.open(ctx)
  return false
end

-- The help text is a page of its own, built the way the menu pages in ui/home.lua build theirs.
-- A `page` node is always a full-screen EdgeTX page with its own header: it takes no x/y/w/h,
-- paints over anything built before it, and anything built after it sits on top of its body.
-- So the header is the page's own (title, subtitle, icon), the text is its only child, and the
-- sheet is closed by the header's close icon (`backButton`) or EXIT, both of which reach
-- `onBack`, which closes the help while it is open.
function HelpView.build(ctx)
  local i18n = ctx.i18n
  -- The caller names the page the help belongs to; fall back to the generic caption only when
  -- it supplies nothing. Written in the form the package-time resolver recognises.
  local headerTitle = ctx.title or ""
  if headerTitle == "" then
    headerTitle = i18n and i18n.t and i18n.t("app.help.title") or "Help"
  end

  return {
    {
      type = "page",
      title = headerTitle,
      subtitle = ctx.subtitle,
      icon = ctx.icon,
      back = ctx.onBack,
      backButton = true,
      children = {
        -- A label given a width and no height wraps and grows with its text, and the page body
        -- scrolls over it, so nothing here has to estimate how tall the text will be.
        {
          type = "label",
          x = 8,
          y = 8,
          w = math.max(40, (ctx.contentW or LCD_W) - 16),
          text = tostring(ctx.message or ""),
          color = COLOR_THEME_PRIMARY1,
          font = SMLSIZE
        }
      }
    }
  }
end

return HelpView
