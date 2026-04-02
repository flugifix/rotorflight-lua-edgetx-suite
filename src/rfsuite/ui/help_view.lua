local HelpView = {}

function HelpView.build(ctx)
  local i18n = ctx.i18n
  local contentX = ctx.contentX
  local contentY = ctx.contentY
  local contentW = ctx.contentW
  local lcdH = ctx.lcdH
  local message = ctx.message or ""
  local title = ctx.title or ""
  local subtitle = ctx.subtitle
  local icon = ctx.icon
  local onBack = ctx.onBack
  local header = ctx.header
  local headerLayout = ctx.headerLayout

  local closeLabel = "Close"
  if i18n and i18n.t then
    local key = "app.actions.close"
    local translated = i18n.t(key)
    if translated and translated ~= "" and translated ~= key then
      closeLabel = translated
    end
  end

  local innerHeaderLabel = "Help"
  if i18n and i18n.t then
    local key = "app.help.title"
    local translated = i18n.t(key)
    if translated and translated ~= "" and translated ~= key then
      innerHeaderLabel = translated
    end
  end

  local helpBtnW = 190
  local helpBtnH = 44
  local helpBtnX = contentX + math.floor((contentW - helpBtnW) / 2)
  local helpBtnY = lcdH - helpBtnH - 84

  local panelX = contentX
  local panelY = contentY
  local panelW = contentW
  local panelH = lcdH - contentY - 75
  local innerHeaderH = 34
  local bodyTop = panelY + innerHeaderH + 26
  local bodyBottom = helpBtnY - 20
  local bodyH = math.max(30, bodyBottom - bodyTop)

  local children = {
    {
      type = "rectangle",
      x = panelX,
      y = panelY,
      w = panelW,
      h = panelH,
      color = BLACK,
      filled = true
    },
    {
      type = "rectangle",
      x = panelX,
      y = panelY,
      w = panelW,
      h = innerHeaderH,
      color = COLOR_THEME_SECONDARY1,
      filled = true
    },
    {
      type = "rectangle",
      x = panelX,
      y = panelY + innerHeaderH,
      w = panelW,
      h = panelH - innerHeaderH,
      color = COLOR_THEME_SECONDARY2,
      filled = true
    },
    {
      type = "label",
      x = panelX + 5,
      y = panelY - 2,
      w = panelW - 20,
      text = innerHeaderLabel,
      color = COLOR_THEME_PRIMARY1,
      font = MIDSIZE
    },
    {
      type = "label",
      x = panelX + 10,
      y = bodyTop,
      w = panelW - 20,
      h = bodyH,
      text = message,
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    },
    {
      type = "button",
      x = helpBtnX,
      y = helpBtnY,
      w = helpBtnW,
      h = helpBtnH,
      text = closeLabel,
      press = onBack
    }
  }

  local layout = {
    {
      type = "page",
      title = title,
      subtitle = subtitle,
      icon = icon,
      back = onBack,
      children = children
    }
  }

  header.appendToLayout(layout, {
    actions = { back = true, save = false, reload = false, star = false, help = false },
    i18n = i18n,
    layout = headerLayout,
    onHelp = function() end,
    onStar = function() end,
    onReload = function() end,
    onSave = function() end,
    onBack = onBack
  })

  return layout
end

return HelpView
