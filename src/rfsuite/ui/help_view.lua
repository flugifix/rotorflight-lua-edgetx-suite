local HelpView = {}

local function safeTextSize(text)
  local fn = lcd and lcd.getTextSize
  if type(fn) == "function" then
    local ok, w, h = pcall(fn, text)
    if ok then
      return tonumber(w) or 0, tonumber(h) or 0
    end
  end

  local str = tostring(text or "")
  return (#str * 8), 16
end

local function splitLines(text)
  local lines = {}
  if type(text) ~= "string" or text == "" then
    return lines
  end

  local pos = 1
  while true do
    local nextPos = string.find(text, "\n", pos)
    if not nextPos then
      lines[#lines + 1] = string.sub(text, pos)
      break
    end
    lines[#lines + 1] = string.sub(text, pos, nextPos - 1)
    pos = nextPos + 1
  end

  return lines
end

local function estimateWrappedTextHeight(text, width)
  local lines = splitLines(text)
  if #lines == 0 then
    return 0
  end

  local _, lineH = safeTextSize("Ag")
  lineH = tonumber(lineH) or 16
  if lineH < 12 then lineH = 12 end

  local spaceW = safeTextSize(" ")
  if not spaceW or spaceW <= 0 then
    spaceW = 4
  end

  local totalH = 0
  for i = 1, #lines do
    local paragraph = lines[i]
    local currentLine = ""
    local paragraphLines = 1

    for word in string.gmatch(paragraph, "%S+") do
      local candidate = currentLine == "" and word or (currentLine .. " " .. word)
      local candidateW = safeTextSize(candidate)
      if candidateW > width and currentLine ~= "" then
        paragraphLines = paragraphLines + 1
        currentLine = word
      else
        currentLine = candidate
      end
    end

    totalH = totalH + (paragraphLines * lineH)
    if i < #lines then
      totalH = totalH + lineH
    end
  end

  return totalH
end

function HelpView.open(ctx)
  return false
end

function HelpView.build(ctx)
  local i18n = ctx.i18n
  local contentX = ctx.contentX
  local contentY = ctx.contentY
  local contentW = ctx.contentW
  local lcdH = ctx.lcdH
  local message = ctx.message or ""
  local title = ctx.title or ""
  local subtitle = ctx.subtitle
  local state = ctx.state
  local requestRebuild = ctx.requestRebuild

  local closeLabel = "Close"
  if i18n and i18n.t then
    local key = "app.actions.close"
    local translated = i18n.t(key)
    if translated and translated ~= "" and translated ~= key then
      closeLabel = translated
    end
  end

  local helpBtnW = 190
  local helpBtnH = 44
  local helpBtnX = math.floor((LCD_W - helpBtnW) / 2)
  local helpBtnY = lcdH - helpBtnH - 16

  local headerH = 52
  local panelX = 0
  local panelY = 0
  local panelW = LCD_W
  local panelH = lcdH
  local logoW = 72
  local logoH = 30
  local bodyTop = headerH + 10
  local bodyBottom = helpBtnY - 20
  local bodyH = math.max(30, bodyBottom - bodyTop)
  local bodyText = tostring(message or "")
  local bodyTextW = math.max(40, contentW - 20)
  local bodyTextH = estimateWrappedTextHeight(bodyText, bodyTextW)

  local layout = {
    {
      type = "rectangle",
      x = panelX,
      y = panelY,
      w = panelW,
      h = panelH,
      color = COLOR_THEME_PRIMARY2,
      filled = true
    },
    {
      type = "rectangle",
      x = panelX,
      y = panelY,
      w = panelW,
      h = headerH,
      color = COLOR_THEME_SECONDARY1,
      filled = true
    },
    {
      type = "image",
      x = 4,
      y = 4,
      w = logoW,
      h = logoH,
      file = "/SCRIPTS/TOOLS/rfsuite-core/widgets/dashboard/gfx/logo.png"
    },
    {
      type = "label",
      x = 82,
      y = 5,
      w = math.max(40, contentW - 90),
      text = "Hilfe",
      color = COLOR_THEME_PRIMARY1,
      font = MIDSIZE
    },
    subtitle and subtitle ~= "" and {
      type = "label",
      x = 82,
      y = 26,
      w = math.max(40, contentW - 90),
      text = subtitle,
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    } or nil,
    {
      type = "page",
      x = contentX,
      y = bodyTop,
      w = contentW,
      h = bodyH,
      active = function()
        return true
      end,
      children = {
        {
          type = "label",
          x = 8,
          y = 0,
          w = bodyTextW,
          h = bodyTextH + 20,
          text = bodyText,
          color = COLOR_THEME_PRIMARY1,
          font = SMLSIZE
        }
      }
    }
  }

  layout[#layout + 1] = {
    type = "button",
    x = helpBtnX,
    y = helpBtnY,
    w = helpBtnW,
    h = helpBtnH,
    text = closeLabel,
    press = function()
      if type(state) == "table" then
        state.helpContent = nil
        state.helpPageTitle = nil
        state.helpPageSubtitle = nil
      end
      if type(requestRebuild) == "function" then
        requestRebuild()
      elseif type(scheduleBuildUI) == "function" then
        scheduleBuildUI(false)
      end
    end
  }

  return layout
end

return HelpView
