local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local GridLayout   = loadModule("layouts/grid.lua")
local I18n         = loadModule("i18n/init.lua")
local DisplayProfile = loadModule("core/display_profile.lua")
local manifest     = loadModule("app/manifest.lua")
local MenuRegistry = loadModule("app/menu_registry.lua")
local PageRegistry = loadModule("app/pages/init.lua")
local Tiles             = loadModule("ui/tiles.lua")
local Header            = loadModule("ui/header.lua")
local PreferencesSafe   = loadModule("ui/preferences.lua")

local ICON_ROOT = "/SCRIPTS/TOOLS/rfsuite-core/assets/icons/"
local APP_ICON  = "/SCRIPTS/TOOLS/rfsuite-core/assets/icon.png"

local M = {}

local Prefs           = PreferencesSafe.new(loadModule)
local loadPreferencesSafe  = Prefs.load
local savePreferencesSafe  = Prefs.save

-- Global access point: rfsuite.preferences and rfsuite.savePreferences
-- Any module can read settings via: rfsuite.preferences.general.save_confirm
_G.rfsuite = _G.rfsuite or {}
_G.rfsuite.savePreferences = function()
  return savePreferencesSafe(_G.rfsuite.preferences)
end

local function computeTileSize(cardW, cfg)
  local hardMax = math.min(cfg.tileMax, cardW)
  if cardW < cfg.tileMin then
    return hardMax
  end
  local soft = math.max(cfg.tileMin, hardMax)
  return soft
end

local function getRequiredColumns(items)
  local required = 1
  for i = 1, #items do
    local c = tonumber(items[i].col)
    if c and c > required then
      required = c
    end
  end
  return required
end

local function toWrappedItems(items, cols)
  local wrapped = {}
  local c = 1
  local r = 1
  for i = 1, #items do
    local item = items[i]
    wrapped[i] = {
      id = item.id,
      row = r,
      col = c,
      data = item.data
    }
    c = c + 1
    if c > cols then
      c = 1
      r = r + 1
    end
  end
  return wrapped, r
end

local state = {
  shouldExit   = false,
  cards        = {},
  groupedCards = {},
  i18n         = nil,
  menu         = nil,
  preferences  = nil,
  cardHandlers = {},
  focusIndex   = 0,
  ignoreNextPageKey = false,
  suppressPressFrames = 0,
  memBucket    = nil,
  memLastTick  = 0,
  lastInputTick = 0,
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
    },
    byMenuId = {
      settings_general_page      = { save = true, reload = true, help = false },
      settings_localization_page = { save = true, reload = true, help = false }
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
  local page = state.menu and (function()
    local menuId = state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or nil
    return PageRegistry and PageRegistry.byMenuId and PageRegistry.byMenuId[menuId] or nil
  end)() or nil

  if page and page.onReload then
    state.preferences = loadPreferencesSafe()
    _G.rfsuite.preferences = state.preferences
    page.onReload({
      i18n = state.i18n,
      preferences = state.preferences,
      menu = state.menu,
      refresh = M.buildUI
    })
    M.buildUI()
    return
  end

  if lvgl and lvgl.alert then
    lvgl.alert({
      title = "Reload",
      message = "Reload from FBL is not wired yet."
    })
  end
end

local function onSave()
  local page = state.menu and (function()
    local menuId = state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or nil
    return PageRegistry and PageRegistry.byMenuId and PageRegistry.byMenuId[menuId] or nil
  end)() or nil

  if page and page.onSave then
    page.onSave({
      i18n = state.i18n,
      preferences = state.preferences,
      menu = state.menu,
      savePreferences = function()
        local ok, err = savePreferencesSafe(state.preferences)
        -- keep global in sync after save
        _G.rfsuite.preferences = state.preferences
        _G.rfsuite.savePreferences = function() return savePreferencesSafe(_G.rfsuite.preferences) end
        return ok, err
      end,
      refresh = M.buildUI
    })
    M.buildUI()
    return
  end

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
    if (state.suppressPressFrames or 0) > 0 then
      return
    end
    if state.menu and (not state.menu.isRoot()) then
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
    if (state.suppressPressFrames or 0) > 0 then
      return
    end
    if state.menu and state.menu.isRoot() then
      state.menu.openRootEntry(sectionId, cardId)
      state.focusIndex = 0
      M.buildUI()
    end
  end
  state.cardHandlers[key] = fn
  return fn
end

-- ── Main UI build ─────────────────────────────────────────────────────────────

function M.buildUI()
  if lvgl == nil then return end
  lvgl.clear()

  local profile = DisplayProfile.current()
  local contentPad = profile.contentPad
  local labelIndent = profile.labelIndent
  local tileGap = profile.tileGap
  local groupTitleH = profile.groupTitleH
  local groupDivH = profile.groupDivH
  local groupGapAfter = profile.groupGapAfter
  local groupHeaderH = groupTitleH + groupDivH + groupGapAfter

  local breadcrumb = ""
  if not state.menu.isRoot() then
    breadcrumb = state.menu.getHeaderBreadcrumb()
    if breadcrumb == "" then breadcrumb = state.menu.getBreadcrumb() end
  end

  local pageTitle = state.menu.isRoot() and "Rotorflight" or state.menu.getHeaderTitle()

  -- Build children list for the page
  local children = {}

  local contentX = contentPad
  local contentY = tileGap
  local contentW = LCD_W - contentPad * 2

  if state.menu.isRoot() then
    local groups    = state.menu.getRootGroups(ICON_ROOT)
    state.groupedCards = groups
    local flatCards = Tiles.flattenRootCards(groups)
    state.cards     = flatCards
    state.focusIndex = math.max(0, math.min(state.focusIndex, #flatCards))

    local cursorY   = contentY
    local flatIndex = 0

    for i = 1, #groups do
      local group   = groups[i]
      local computedCols = Tiles.computeColumns(contentW, profile.rootMinCardWidth, profile.rootMaxColumns)
      local columns = computedCols
      local rows = 1
      local layoutItems = group.cards
      if profile.wrapTiles == true then
        layoutItems, rows = toWrappedItems(group.cards, columns)
      else
        local requiredCols = getRequiredColumns(group.cards)
        columns = math.max(computedCols, requiredCols)
      end

      -- Section heading label (indented from left edge)
      children[#children + 1] = {
        type  = "label",
        x = contentX + labelIndent, y = cursorY,
        text  = group.title,
        color = COLOR_THEME_PRIMARY1,
        font  = SMLSIZE
      }
      -- Divider line
      children[#children + 1] = {
        type   = "rectangle",
        x = contentX, y = cursorY + groupTitleH,
        w = contentW, h = groupDivH,
        color  = COLOR_THEME_SECONDARY1,
        filled = true
      }
      cursorY = cursorY + groupHeaderH

      local groupCards = GridLayout.layout(
        { x = contentX, y = cursorY, w = contentW, h = profile.rootRowHeight * rows },
        { rows = rows, cols = columns, gap = tileGap, padding = 0, items = layoutItems },
        {}
      )

      local groupBottom = cursorY
      for j = 1, #groupCards do
        local card     = groupCards[j]
        flatIndex      = flatIndex + 1
        local tileSize = computeTileSize(card.w, profile)
        local tileX    = card.x + math.floor((card.w - tileSize) / 2)
        local tileY    = card.y

        Tiles.append(
          children, tileX, tileY, tileSize,
          card.data.icon, card.data.text,
          flatIndex == state.focusIndex,
          getRootCardPressHandler(group.id, card.id),
          card.data.enabled
        )

        local bottom = tileY + tileSize
        if bottom > groupBottom then groupBottom = bottom end
      end

      cursorY = groupBottom + profile.groupGapBottom
    end

  else
    local currentMenuId = state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or nil
    local pageModule = PageRegistry and PageRegistry.byMenuId and PageRegistry.byMenuId[currentMenuId] or nil
    if pageModule and pageModule.build then
      state.cards = {}
      state.focusIndex = 0
      pageModule.build({
        children = children,
        x = contentX,
        y = contentY,
        w = contentW,
        h = LCD_H,
        i18n = state.i18n,
        preferences = state.preferences,
        menu = state.menu,
        requestRebuild = M.buildUI
      })
    else
      local gridItems = state.menu.getCards(ICON_ROOT)
      local computedCols = Tiles.computeColumns(contentW, profile.menuMinCardWidth, profile.menuMaxColumns)
      local columns   = computedCols
      local rows      = math.max(1, math.ceil(#gridItems / columns))
      local layoutItems = gridItems
      if profile.wrapTiles == true then
        layoutItems, rows = toWrappedItems(gridItems, columns)
      else
        local requiredCols = getRequiredColumns(gridItems)
        columns = math.max(computedCols, requiredCols)
        rows = math.max(1, math.ceil(#gridItems / columns))
      end
      local cards     = GridLayout.layout(
        { x = contentX, y = contentY, w = contentW, h = LCD_H },
        { rows = rows, cols = columns, gap = tileGap, padding = 2, items = layoutItems },
        state.cards
      )
      state.cards = cards
      state.focusIndex = math.max(0, math.min(state.focusIndex, #cards))

      for i = 1, #cards do
        local card     = cards[i]
        local tileSize = computeTileSize(card.w, profile)
        local tileX    = card.x + math.floor((card.w - tileSize) / 2)
        local tileY    = card.y

        Tiles.append(
          children, tileX, tileY, tileSize,
          card.data.icon, card.data.text,
          i == state.focusIndex,
          getCardPressHandler(card.id),
          card.data.enabled
        )
      end
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

  local actions = Header.resolveActions({
    headerActions = state.headerActions,
    menu          = state.menu,
    i18n          = state.i18n,
    preferences   = state.preferences,
    PageRegistry  = PageRegistry
  })
  Header.appendToLayout(lyt, {
    actions  = actions,
    i18n     = state.i18n,
    layout   = profile.header,
    onHelp   = onHelp,
    onStar   = onStar,
    onReload = onReload,
    onSave   = onSave,
    onBack   = onBack
  })

  lvgl.build(lyt)
end

-- ── Init / Run ────────────────────────────────────────────────────────────────

function M.init()
  state.shouldExit = false
  state.i18n       = I18n.new("de")
  local prefs = loadPreferencesSafe()
  state.preferences = prefs
  _G.rfsuite.preferences = prefs
  _G.rfsuite.savePreferences = function() return savePreferencesSafe(_G.rfsuite.preferences) end
  state.menu       = MenuRegistry.new(manifest, state.i18n, {
    conditions = {
      developerTools = prefs.general and prefs.general.developer_tools == true
    }
  })
  state.memBucket  = nil
  state.memLastTick = 0
  state.lastInputTick = getTime and getTime() or 0
  state.ignoreNextPageKey = false
  state.suppressPressFrames = 0
  state.focusIndex = 0
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
    if (state.suppressPressFrames or 0) > 0 then
      state.suppressPressFrames = state.suppressPressFrames - 1
    end

    if getTime and event and event ~= 0 then
      state.lastInputTick = getTime()
    end

    -- Keep a single focus model: LVGL handles PAGE/PAGE- and ENTER natively.
    -- We only handle EXIT/back here.
    if isEvent(event, EVT_VIRTUAL_EXIT, EVT_EXIT_BREAK) then
      onBack()
    end

    -- Intentionally no periodic MEM-triggered rebuild here.
    -- Rebuilding while navigating resets LVGL focus on some pages.
    -- MEM value updates on normal UI rebuild points (navigation/actions).
  end

  if state.shouldExit then return 2 end
  return 0
end

return { init = M.init, run = M.run, useLvgl = true }
