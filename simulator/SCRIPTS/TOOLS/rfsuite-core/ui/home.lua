local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local GridLayout   = loadModule("layouts/grid.lua")
local I18n         = loadModule("i18n/init.lua")
local manifest     = loadModule("app/manifest.lua")
local MenuRegistry = loadModule("app/menu_registry.lua")

local ICON_ROOT = "/SCRIPTS/TOOLS/rfsuite-core/assets/icons/"
local APP_ICON  = "/SCRIPTS/TOOLS/rfsuite-core/assets/icon.png"

local CONTENT_PAD   = 6
local LABEL_INDENT  = 6    -- extra left padding for section title labels
local TILE_GAP      = 12
local GROUP_TITLE_H  = 24  -- height reserved for section heading text
local GROUP_DIV_H    = 3   -- divider line height
local GROUP_GAP_AFTER = 10 -- gap between divider bottom and first tile row
local GROUP_HEADER_H  = GROUP_TITLE_H + GROUP_DIV_H + GROUP_GAP_AFTER

local TOP_BUTTON_W_SMALL = 45
local TOP_BUTTON_W_ACTION = 45
local TOP_BUTTON_H = 45
local TOP_BUTTON_GAP = 4
local TOP_BUTTON_Y = 8
local TOP_BUTTON_BORDER = 2

local M = {}

local state = {
  shouldExit   = false,
  cards        = {},
  groupedCards = {},
  i18n         = nil,
  menu         = nil,
  cardHandlers = {},
  focusIndex   = 0,
  headerActions = {
    defaults = {
      root = {
        star = false,
        reload = false,
        save = false,
        help = false
      },
      menu = {
        star = false,
        reload = false,
        save = false,
        help = false
      }
    },
    byEntryId = {
      -- Example:
      -- pids = { reload = true, save = true, star = true }
    }
  }
}

-- ── Handlers ─────────────────────────────────────────────────────────────────

local function onBack()
  if state.menu and state.menu.goBack() then
    state.focusIndex = 0
    M.buildUI()
    return
  end
  state.shouldExit = true
end

local function onHelp()
  if lvgl and lvgl.alert and state.i18n then
    lvgl.alert({
      title   = state.i18n.t("app.help.title"),
      message = state.i18n.t("app.help.layout")
    })
  end
end

local function onStar()
  if lvgl and lvgl.alert and state.i18n then
    lvgl.alert({
      title = state.i18n.t("app.help.title"),
      message = "Star action is reserved for standard functions."
    })
  end
end

local function onReload()
  if lvgl and lvgl.alert then
    lvgl.alert({
      title = "Reload",
      message = "Reload from FBL is not wired yet."
    })
  end
end

local function onSave()
  if lvgl and lvgl.alert then
    lvgl.alert({
      title = "Save",
      message = "Save to FBL is not wired yet."
    })
  end
end

local function getCardPressHandler(cardId)
  if state.cardHandlers[cardId] then return state.cardHandlers[cardId] end
  local fn = function()
    if state.menu then
      state.menu.openEntry(cardId)
      state.focusIndex = 0
      M.buildUI()
    end
  end
  state.cardHandlers[cardId] = fn
  return fn
end

local function getRootCardPressHandler(sectionId, cardId)
  local key = sectionId .. ":" .. cardId
  if state.cardHandlers[key] then return state.cardHandlers[key] end
  local fn = function()
    if state.menu then
      state.menu.openRootEntry(sectionId, cardId)
      state.focusIndex = 0
      M.buildUI()
    end
  end
  state.cardHandlers[key] = fn
  return fn
end

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function computeColumns(width, minCardWidth, maxColumns)
  local cols = math.floor(width / minCardWidth)
  if cols < 1 then cols = 1 end
  if cols > maxColumns then cols = maxColumns end
  return cols
end

local function flattenRootCards(groups)
  local flat = {}
  for i = 1, #groups do
    local cards = groups[i].cards or {}
    for j = 1, #cards do flat[#flat + 1] = cards[j] end
  end
  return flat
end

local function formatTileText(text)
  if type(text) ~= "string" then return "" end
  local len = string.len(text)
  if len <= 11 then return text end
  local bestSpace, mid = nil, math.floor(len / 2)
  for i = 1, len do
    if string.sub(text, i, i) == " " then
      if bestSpace == nil or math.abs(i - mid) < math.abs(bestSpace - mid) then
        bestSpace = i
      end
    end
  end
  if bestSpace then
    return string.sub(text, 1, bestSpace - 1) .. "\n" .. string.sub(text, bestSpace + 1)
  end
  return string.sub(text, 1, mid) .. "\n" .. string.sub(text, mid + 1)
end

local function resolveHeaderActions()
  local defaults = state.headerActions.defaults
  local rootDefaults = defaults.root or {}
  local menuDefaults = defaults.menu or {}
  local isRoot = not state.menu or state.menu.isRoot()
  local base = isRoot and rootDefaults or menuDefaults
  local actions = {
    back = true,
    save = base.save == true,
    reload = base.reload == true,
    star = base.star == true,
    help = base.help ~= false
  }

  if state.menu and not isRoot then
    local entryId = state.menu.getCurrentEntryId and state.menu.getCurrentEntryId() or nil
    if entryId then
      local override = state.headerActions.byEntryId[entryId]
      if type(override) == "table" then
        if override.save ~= nil then actions.save = override.save == true end
        if override.reload ~= nil then actions.reload = override.reload == true end
        if override.star ~= nil then actions.star = override.star == true end
        if override.help ~= nil then actions.help = override.help == true end
      end
    end
  end

  return actions
end

local function appendTopActionButton(layout, x, w, text, enabled, pressHandler)
  if enabled then
    -- Enabled buttons keep native button rendering to preserve icon glyph support.
    layout[#layout + 1] = {
      type  = "button",
      x = x,
      y = TOP_BUTTON_Y,
      w = w,
      h = TOP_BUTTON_H,
      text  = text,
      press = pressHandler
    }
  else
    -- Disabled buttons are plain placeholders: white fill + gray text, no button widget,
    -- so they are truly non-interactive and cannot receive touch focus styling.
    layout[#layout + 1] = {
      type = "rectangle",
      x = x + 1,
      y = TOP_BUTTON_Y + 1,
      w = w - 2,
      h = TOP_BUTTON_H - 2,
      color = GREY_DEFAULT,
      filled = true
    }

    layout[#layout + 1] = {
      type = "label",
      x = x,
      y = TOP_BUTTON_Y + 10,
      w = w,
      text = text,
      color = COLOR_THEME_PRIMARY2,
      align = CENTER,
      font = SMLSIZE
    }
  end

  -- Thin border drawn on top of the button (same color as icon for visual coherence).
  local borderColor = enabled and COLOR_THEME_PRIMARY1 or GREY_DEFAULT
  for i = 0, TOP_BUTTON_BORDER - 1 do
    layout[#layout + 1] = {
      type = "rectangle",
      x = x + i,
      y = TOP_BUTTON_Y + i,
      w = w - (i * 2),
      h = 1,
      color = borderColor,
      filled = true
    }
    layout[#layout + 1] = {
      type = "rectangle",
      x = x + i,
      y = TOP_BUTTON_Y + TOP_BUTTON_H - 1 - i,
      w = w - (i * 2),
      h = 1,
      color = borderColor,
      filled = true
    }
    layout[#layout + 1] = {
      type = "rectangle",
      x = x + i,
      y = TOP_BUTTON_Y + i,
      w = 1,
      h = TOP_BUTTON_H - (i * 2),
      color = borderColor,
      filled = true
    }
    layout[#layout + 1] = {
      type = "rectangle",
      x = x + w - 1 - i,
      y = TOP_BUTTON_Y + i,
      w = 1,
      h = TOP_BUTTON_H - (i * 2),
      color = borderColor,
      filled = true
    }
  end
end

local function tAction(key, fallback)
  if state.i18n and state.i18n.t then
    return state.i18n.t("app.actions." .. key)
  end
  return fallback
end

-- Append tile widgets into the children table (no pg: calls)
local function appendTile(children, x, y, size, iconFile, text, focused, pressHandler, enabled)
  local isEnabled = enabled ~= false

  children[#children + 1] = {
    type  = "button",
    x = x, y = y, w = size, h = size,
    text  = "",
    press = isEnabled and pressHandler or nil
  }

  if focused and isEnabled then
    children[#children + 1] = {
      type = "rectangle", x = x, y = y, w = size, h = 3,
      color = COLOR_THEME_SECONDARY1, filled = true
    }
  end

  if not isEnabled then
    children[#children + 1] = {
      type = "rectangle", x = x + 1, y = y + 1, w = size - 2, h = size - 2,
      color = GREY_DEFAULT, filled = true
    }
  end

  if iconFile then
    local iconSize = math.max(16, math.floor(size * 0.36))
    children[#children + 1] = {
      type = "image",
      x = x + math.floor((size - iconSize) / 2),
      y = y + math.max(5, math.floor(size * 0.08)),
      w = iconSize, h = iconSize,
      file = iconFile
    }
  end

  children[#children + 1] = {
    type  = "label",
    x = x + 4,
    y = y + math.floor(size * 0.56),
    w = size - 8,
    text  = formatTileText(text),
    font  = SMLSIZE,
    color = isEnabled and BLACK or WHITE,
    align = CENTER
  }
end

-- ── Main UI build ─────────────────────────────────────────────────────────────

function M.buildUI()
  if lvgl == nil then return end
  lvgl.clear()

  local breadcrumb = ""
  if not state.menu.isRoot() then
    breadcrumb = state.menu.getHeaderBreadcrumb()
    if breadcrumb == "" then breadcrumb = state.menu.getBreadcrumb() end
  end

  local pageTitle = state.menu.isRoot() and "Rotorflight" or state.menu.getHeaderTitle()

  -- Build children list for the page
  local children = {}

  local contentX = CONTENT_PAD
  local contentY = TILE_GAP
  local contentW = LCD_W - CONTENT_PAD * 2

  if state.menu.isRoot() then
    local groups    = state.menu.getRootGroups(ICON_ROOT)
    state.groupedCards = groups
    local flatCards = flattenRootCards(groups)
    state.cards     = flatCards
    state.focusIndex = math.max(0, math.min(state.focusIndex, #flatCards))

    local cursorY   = contentY
    local flatIndex = 0

    for i = 1, #groups do
      local group   = groups[i]
      local columns = computeColumns(contentW, 72, 6)

      -- Section heading label (indented from left edge)
      children[#children + 1] = {
        type  = "label",
        x = contentX + LABEL_INDENT, y = cursorY,
        text  = group.title,
        color = COLOR_THEME_PRIMARY1,
        font  = SMLSIZE
      }
      -- Divider line
      children[#children + 1] = {
        type   = "rectangle",
        x = contentX, y = cursorY + GROUP_TITLE_H,
        w = contentW, h = GROUP_DIV_H,
        color  = COLOR_THEME_SECONDARY1,
        filled = true
      }
      cursorY = cursorY + GROUP_HEADER_H

      local groupCards = GridLayout.layout(
        { x = contentX, y = cursorY, w = contentW, h = 120 },
        { rows = 1, cols = columns, gap = TILE_GAP, padding = 0, items = group.cards },
        {}
      )

      local groupBottom = cursorY
      for j = 1, #groupCards do
        local card     = groupCards[j]
        flatIndex      = flatIndex + 1
        local tileSize = math.max(80, math.min(card.w, 112))
        local tileX    = card.x + math.floor((card.w - tileSize) / 2)
        local tileY    = card.y

        appendTile(
          children, tileX, tileY, tileSize,
          card.data.icon, card.data.text,
          flatIndex == state.focusIndex,
          getRootCardPressHandler(group.id, card.id),
          card.data.enabled
        )

        local bottom = tileY + tileSize
        if bottom > groupBottom then groupBottom = bottom end
      end

      cursorY = groupBottom + 16
    end

  else
    local gridItems = state.menu.getCards(ICON_ROOT)
    local columns   = computeColumns(contentW, 72, 6)
    local rows      = math.max(1, math.ceil(#gridItems / columns))
    local cards     = GridLayout.layout(
      { x = contentX, y = contentY, w = contentW, h = LCD_H },
      { rows = rows, cols = columns, gap = TILE_GAP, padding = 2, items = gridItems },
      state.cards
    )
    state.cards = cards
    state.focusIndex = math.max(0, math.min(state.focusIndex, #cards))

    for i = 1, #cards do
      local card     = cards[i]
      local tileSize = math.max(80, math.min(card.w, 112))
      local tileX    = card.x + math.floor((card.w - tileSize) / 2)
      local tileY    = card.y

      appendTile(
        children, tileX, tileY, tileSize,
        card.data.icon, card.data.text,
        i == state.focusIndex,
        getCardPressHandler(card.id),
        card.data.enabled
      )
    end
  end

  -- Build layout: page + children table, then "?" button as sibling (same as Save in page.lua)
  local lyt = {
    {
      type     = "page",
      title    = pageTitle,
      subtitle = breadcrumb ~= "" and breadcrumb or nil,
      icon     = APP_ICON,
      back     = onBack,
      children = children
    }
  }

  local actions = resolveHeaderActions()
  local rightEdge = LCD_W - 20
  local xHelp = rightEdge - TOP_BUTTON_W_SMALL
  local xStar = xHelp - TOP_BUTTON_GAP - TOP_BUTTON_W_SMALL
  local xReload = xStar - TOP_BUTTON_GAP - TOP_BUTTON_W_ACTION
  local xSave = xReload - TOP_BUTTON_GAP - TOP_BUTTON_W_ACTION
  local xBack = xSave - TOP_BUTTON_GAP - TOP_BUTTON_W_ACTION

  appendTopActionButton(lyt, xHelp, TOP_BUTTON_W_SMALL, tAction("help", "?"), actions.help, onHelp)
  appendTopActionButton(lyt, xStar, TOP_BUTTON_W_SMALL, tAction("star", "*"), actions.star, onStar)
  appendTopActionButton(lyt, xReload, TOP_BUTTON_W_ACTION, tAction("reload", "RELOAD"), actions.reload, onReload)
  appendTopActionButton(lyt, xSave, TOP_BUTTON_W_ACTION, tAction("save", "SAVE"), actions.save, onSave)
  appendTopActionButton(lyt, xBack, TOP_BUTTON_W_ACTION, tAction("back", "BACK"), true, onBack)

  lvgl.build(lyt)
end

-- ── Init / Run ────────────────────────────────────────────────────────────────

function M.init()
  state.shouldExit = false
  state.i18n       = I18n.new("de")
  state.menu       = MenuRegistry.new(manifest, state.i18n)
  M.buildUI()
end

function M.run(event, touchState)
  local function isEvent(ev, ...)
    for i = 1, select("#", ...) do
      local c = select(i, ...)
      if c and ev == c then return true end
    end
    return false
  end

  if lvgl == nil then
    lcd.drawText(10, 10, "LVGL support required (EdgeTX 2.11+)", WHITE)
  end

  if state.menu then
    if isEvent(event, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_NEXT_PAGE) then
      if #state.cards > 0 then
        state.focusIndex = state.focusIndex + 1
        if state.focusIndex > #state.cards then state.focusIndex = 1 end
        M.buildUI()
      end
    elseif isEvent(event, EVT_VIRTUAL_PREV, EVT_VIRTUAL_PREV_PAGE) then
      if #state.cards > 0 then
        state.focusIndex = state.focusIndex - 1
        if state.focusIndex < 1 then state.focusIndex = #state.cards end
        M.buildUI()
      end
    elseif isEvent(event, EVT_VIRTUAL_ENTER, EVT_ENTER_BREAK) then
      local card = state.cards[state.focusIndex]
      if card then
        if state.menu.isRoot() then
          if state.menu.isRootEntryEnabled(card.sectionId, card.id) then
            state.menu.openRootEntry(card.sectionId, card.id)
          end
        else
          if state.menu.isEntryEnabled(card.id) then
            state.menu.openEntry(card.id)
          end
        end
        state.focusIndex = 0
        M.buildUI()
      end
    elseif isEvent(event, EVT_VIRTUAL_EXIT, EVT_EXIT_BREAK) then
      onBack()
    end
  end

  if state.shouldExit then return 2 end
  return 0
end

return { init = M.init, run = M.run, useLvgl = true }
