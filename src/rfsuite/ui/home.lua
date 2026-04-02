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
local HelpRegistryFactory = loadModule("app/pages/help_registry.lua")
local Tiles             = loadModule("ui/tiles.lua")
local Header            = loadModule("ui/header.lua")
local HelpView          = loadModule("ui/help_view.lua")
local PreferencesSafe   = loadModule("ui/preferences.lua")

local ICON_ROOT = "/SCRIPTS/TOOLS/rfsuite-core/assets/icons/"
local APP_ICON  = "/SCRIPTS/TOOLS/rfsuite-core/assets/icon.png"

local M = {}

local Prefs           = PreferencesSafe.new(loadModule)
local loadPreferencesSafe  = Prefs.load
local savePreferencesSafe  = Prefs.save
local HelpRegistry = HelpRegistryFactory.new({
  pagePathByMenuId = PageRegistry.pagePathByMenuId
})

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

local function wipeTable(t)
  if type(t) ~= "table" then return end
  for k in pairs(t) do t[k] = nil end
end

local state = {
  shouldExit   = false,
  cards        = {},
  groupedCards = {},
  i18n         = nil,
  menu         = nil,
  preferences  = nil,
  manifest     = manifest,
  cardHandlers = {},
  focusIndex   = 0,
  ignoreNextPageKey = false,
  suppressPressFrames = 0,
  memBucket    = nil,
  memLastTick  = 0,
  lastInputTick = 0,
  activePageMenuId = nil,
  helpContent = nil,
  helpPageTitle = nil,
  helpPageSubtitle = nil,
  pendingBuildUI = false,
  pendingGcAfterBuild = false,
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
  },
  children = {}
}

local function performSave()
  _G.rfsuite.preferences = state.preferences
  return savePreferencesSafe(state.preferences)
end

local function resolveLocaleFromSystem()
  local locale = "de"

  if system and system.getGeneralSettings then
    local ok, gs = pcall(system.getGeneralSettings)
    if ok and type(gs) == "table" then
      local gsLocale = gs.locale or gs.language or gs.lang
      if type(gsLocale) == "string" and gsLocale ~= "" then
        locale = gsLocale
      end
    end
  end

  if locale == "de" and system and system.getLocale then
    local sysLocale = system.getLocale()
    if type(sysLocale) == "string" and sysLocale ~= "" then
      locale = sysLocale
    end
  end

  return locale
end

local function buildPageContext()
  return {
    i18n = state.i18n,
    preferences = state.preferences,
    menu = state.menu,
    manifest = state.manifest,
    refresh = M.buildUI,
    savePreferences = performSave
  }
end

local function scheduleBuildUI(withGc)
  state.pendingBuildUI = true
  if withGc == true then
    state.pendingGcAfterBuild = true
  end
end

local function syncActivePageModule()
  local currentMenuId = state.menu and state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or nil
  if state.activePageMenuId == currentMenuId then
    return
  end

  if state.activePageMenuId and PageRegistry and PageRegistry.release then
    PageRegistry.release(state.activePageMenuId, buildPageContext())
  end

  state.activePageMenuId = currentMenuId
end

-- ── Handlers ─────────────────────────────────────────────────────────────────

local function onBack()
  if state.helpContent then
    state.helpContent = nil
    state.helpPageTitle = nil
    state.helpPageSubtitle = nil
    scheduleBuildUI(false)
    return
  end

  if state.menu and state.menu.goBack() then
    state.focusIndex = 0
    scheduleBuildUI(false)
    return
  end
  state.shouldExit = true
end

local function onHelp()
  if state.helpContent then return end

  local menuId = state.menu and state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or nil
  if not menuId then return end

  local helpData = HelpRegistry and HelpRegistry.get and HelpRegistry.get(menuId, {
    i18n = state.i18n,
    preferences = state.preferences,
    menu = state.menu,
    manifest = state.manifest
  }) or nil

  local message = nil
  if type(helpData) == "string" then
    message = helpData
  elseif type(helpData) == "table" then
    message = helpData.message or helpData.text
  end
  if type(message) ~= "string" or message == "" then
    return
  end

  local title = state.menu.getHeaderTitle and state.menu.getHeaderTitle() or ""
  local subtitle = nil
  local breadcrumb = state.menu.getHeaderBreadcrumb and state.menu.getHeaderBreadcrumb() or ""
  if breadcrumb == "" and state.menu.getBreadcrumb then
    breadcrumb = state.menu.getBreadcrumb() or ""
  end
  if breadcrumb ~= "" then
    subtitle = breadcrumb
  end

  state.helpContent = message
  state.helpPageTitle = title
  state.helpPageSubtitle = subtitle
  scheduleBuildUI(false)
end

local function onStar()
  if lvgl and lvgl.alert and state.i18n then
    lvgl.alert({
      title = state.i18n.t("app.help.title"),
      message = "Star action is reserved for standard functions."
    })
  end
end

local function getActivePageModule()
  if not state.menu then return nil end
  local menuId = state.menu.getCurrentMenuId and state.menu.getCurrentMenuId()
  if not menuId then return nil end
  return PageRegistry and PageRegistry.byMenuId and PageRegistry.byMenuId[menuId]
end

local function closeHelpDialogIfOpen()
  state.helpContent = nil
  state.helpPageTitle = nil
  state.helpPageSubtitle = nil
end

local function onReload()
  local page = getActivePageModule()

  if page and page.onReload then
    local actions = nil
    if type(page.getHeaderActions) == "function" then
      actions = page.getHeaderActions()
    end
    if type(actions) == "table" and actions.reload == false then
      return
    end

    closeHelpDialogIfOpen()

    -- Keep preferences in-memory for reload to avoid repeated disk loads and table churn.
    -- The app loads preferences once during init and pages should work against that shared state.
    _G.rfsuite.preferences = state.preferences
    local shouldRebuild = page.onReload({
      i18n = state.i18n,
      preferences = state.preferences,
      menu = state.menu,
      refresh = M.buildUI
    })
    if shouldRebuild ~= false then
      scheduleBuildUI(true)
    end
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
  local page = getActivePageModule()

  if page and page.onSave then
    closeHelpDialogIfOpen()

    local shouldRebuild = page.onSave({
      i18n = state.i18n,
      preferences = state.preferences,
      menu = state.menu,
      savePreferences = performSave,
      refresh = M.buildUI
    })
    if shouldRebuild ~= false then
      scheduleBuildUI(false)
    end
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
      scheduleBuildUI(false)
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
      scheduleBuildUI(false)
    end
  end
  state.cardHandlers[key] = fn
  return fn
end

-- ── Main UI build ─────────────────────────────────────────────────────────────

function M.buildUI()
  if lvgl == nil then return end

  syncActivePageModule()

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

  -- Clear and reuse the children table to reduce garbage collection
  local children = state.children
  wipeTable(children)

  local contentX = contentPad
  local contentY = tileGap
  local contentW = LCD_W - contentPad * 2

  -- ── Help view (no lvgl.dialog – avoids LVGL lifecycle crashes) ───────────────
  if state.helpContent then
    local helpLyt = HelpView.build({
      i18n = state.i18n,
      contentX = contentX,
      contentY = contentY,
      contentW = contentW,
      lcdH = LCD_H,
      message = state.helpContent,
      title = state.helpPageTitle or pageTitle,
      subtitle = state.helpPageSubtitle,
      icon = APP_ICON,
      onBack = onBack,
      header = Header,
      headerLayout = profile.header
    })
    lvgl.build(helpLyt)
    return
  end
  -- ── End help view ────────────────────────────────────────────────────────────

  if state.menu.isRoot() then
    local groups    = state.menu.getRootGroups(ICON_ROOT)
    state.groupedCards = groups
    local flatCards = Tiles.flattenRootCards(groups)
    -- Never alias cached root card tables into state.cards because submenu grid
    -- layout reuses state.cards as mutable output and would overwrite root data.
    wipeTable(state.cards)
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
      wipeTable(state.cards)
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
        manifest = state.manifest,
        requestRebuild = function() scheduleBuildUI(false) end
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
    PageRegistry  = PageRegistry,
    HelpRegistry  = HelpRegistry
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
  if PageRegistry and PageRegistry.releaseAll then
    PageRegistry.releaseAll(buildPageContext())
  end

  state.shouldExit = false
  local locale = resolveLocaleFromSystem()
  state.i18n       = I18n.new(locale)
  local prefs = loadPreferencesSafe()
  state.preferences = prefs
  _G.rfsuite.preferences = prefs
  _G.rfsuite.savePreferences = performSave
  state.menu       = MenuRegistry.new(manifest, state.i18n, {
    conditions = {
      developerTools = prefs.general and prefs.general.developer_tools == true
    },
    iconByMenuId = PageRegistry.iconByMenuId
  })
  state.memBucket  = nil
  state.memLastTick = 0
  state.lastInputTick = getTime and getTime() or 0
  state.ignoreNextPageKey = false
  state.suppressPressFrames = 0
  state.focusIndex = 0
  state.activePageMenuId = nil
  state.helpContent = nil
  state.helpPageTitle = nil
  state.helpPageSubtitle = nil
  state.pendingBuildUI = false
  state.pendingGcAfterBuild = false
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

    if state.pendingBuildUI then
      state.pendingBuildUI = false
      local doGc = state.pendingGcAfterBuild == true
      state.pendingGcAfterBuild = false
      M.buildUI()
      if doGc and collectgarbage then
        collectgarbage("collect")
      end
    end

    -- Intentionally no periodic MEM-triggered rebuild here.
    -- Rebuilding while navigating resets LVGL focus on some pages.
    -- MEM value updates on normal UI rebuild points (navigation/actions).
  end

  if state.shouldExit then return 2 end
  return 0
end

return { init = M.init, run = M.run, useLvgl = true }
