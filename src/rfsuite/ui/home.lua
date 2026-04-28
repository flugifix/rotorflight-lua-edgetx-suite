local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local GridLayout = nil
local I18n = nil
local DisplayProfile = nil
local manifest = nil
local MenuRegistry = nil
local PageRegistry = nil
local HelpRegistryFactory = nil
local HelpRegistry = nil
local Tiles = nil
local Header = nil
local HelpView = nil
local PreferencesSafe = nil
local Version = nil
local MspRuntime = nil
local Log = nil
local Events = nil
local Audio = nil
local Sensors = nil

local MEM_LOG_INTERVAL_TICKS = 100

local ICON_ROOT = "/SCRIPTS/TOOLS/rfsuite-core/assets/icons/"
local APP_ICON  = "/SCRIPTS/TOOLS/rfsuite-core/assets/icon.png"

local M = {}

local mspUnsupportedDialogModule = nil
local mspUnsupportedDialogLoadTried = false

local Prefs = nil
local loadPreferencesSafe = nil
local savePreferencesSafe = nil

local function ensurePreferencesSafe()
  if not PreferencesSafe then
    PreferencesSafe = loadModule("ui/preferences.lua")
  end
  if not Prefs and PreferencesSafe and type(PreferencesSafe.new) == "function" then
    Prefs = PreferencesSafe.new(loadModule)
    loadPreferencesSafe = Prefs.load
    savePreferencesSafe = Prefs.save
  end
end

local function ensureVersion()
  if not Version then
    Version = loadModule("lib/version.lua")
  end
end

local function ensureMspRuntime()
  if not MspRuntime then
    MspRuntime = loadModule("tasks/msp/runtime.lua")
  end
end

local function ensureEvents()
  if not Events then
    Events = loadModule("tasks/events/runtime.lua")
  end
  if not Audio then
    Audio = loadModule("lib/audio.lua")
  end
  if not Sensors then
    Sensors = loadModule("lib/sensors.lua")
  end
end

local function ensureLog()
  if not Log then
    Log = loadModule("lib/log.lua")
  end
end

local function ensurePageRegistry()
  if not PageRegistry then
    PageRegistry = loadModule("app/pages/init.lua")
  end
end

local function ensureHelpRegistry()
  ensurePageRegistry()
  if not HelpRegistryFactory then
    HelpRegistryFactory = loadModule("app/pages/help_registry.lua")
  end
  if not HelpRegistry and HelpRegistryFactory and type(HelpRegistryFactory.new) == "function" then
    HelpRegistry = HelpRegistryFactory.new({
      pagePathByMenuId = PageRegistry.pagePathByMenuId
    })
  end
end

local function ensureBuildDeps()
  if not GridLayout then
    GridLayout = loadModule("layouts/grid.lua")
  end
  if not DisplayProfile then
    DisplayProfile = loadModule("core/display_profile.lua")
  end
  if not Tiles then
    Tiles = loadModule("ui/tiles.lua")
  end
  if not Header then
    Header = loadModule("ui/header.lua")
  end
end

local function ensureHelpView()
  if not HelpView then
    HelpView = loadModule("ui/help_view.lua")
  end
end

local function ensureInitDeps()
  ensurePreferencesSafe()
  if not I18n then
    I18n = loadModule("i18n/init.lua")
  end
  if not manifest then
    manifest = loadModule("app/manifest.lua")
  end
  if not MenuRegistry then
    MenuRegistry = loadModule("app/menu_registry.lua")
  end
end

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
  i18n         = nil,
  menu         = nil,
  preferences  = nil,
  manifest     = nil,
  cardHandlers = {},
  focusIndex   = 0,
  ignoreNextPageKey = false,
  suppressPressFrames = 0,
  memBucket    = nil,
  memLastTick  = 0,
  memPeakKb    = 0,
  lastInputTick = 0,
  activePageMenuId = nil,
  helpContent = nil,
  helpPageTitle = nil,
  helpPageSubtitle = nil,
  pendingBuildUI = false,
  pendingGcAfterBuild = false,
  mspAttached = false,
  mspLastTick = 0,
  fblConnected = false,
  infoSessionSnapshot = nil,
  lastAudioTick = 0,
  audioState = {
    initialized = false,
    nextAllowedAt = 0,
    modelAnnounced = false,
    lastFuelCallout = nil,
    lowFuelActive = false,
    lowFuelLastAt = 0,
    lowFuelRepeatCount = 0,
    -- lastAlertAt wird nicht mehr hier initialisiert, sondern nur noch lazy in Audio
    lastValues = { arming_flags = nil, governor_state = nil, pid_profile = nil, rate_profile = nil, battery_profile = nil },
    pendingValues = { pid_profile = nil, rate_profile = nil, battery_profile = nil },
    lastEnabled = { governor_state = nil }
  },
  telemetryState = { profile = 1, rateProfile = 1, batteryProfile = 1, voltage = 0, escTemp = 0, fuel = 100, armFlags = 0, governor = 0, themeConfig = { v_min = 18.0 } },
  mspLinkConfigWarningAt = 0,
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

local function shortenBreadcrumb(breadcrumb)
  -- Reduces full breadcrumb to "../LastPart" format
  -- E.g., "System / Tools" or "System > Tools" becomes "../Tools"
  if type(breadcrumb) ~= "string" or breadcrumb == "" then
    return breadcrumb
  end
  
  local parts = {}
  local normalized = string.gsub(breadcrumb, " > ", " / ")
  for part in string.gmatch(normalized, "[^/]+") do
    local trimmed = string.match(part, "^%s*(.-)%s*$")
    if trimmed then
      parts[#parts + 1] = trimmed
    end
  end
  
  if #parts <= 1 then
    return breadcrumb
  end
  
  local lastPart = parts[#parts]
  if lastPart then
    return "../" .. lastPart
  end
  return breadcrumb
end

local function performSave()
  _G.rfsuite.preferences = state.preferences
  return savePreferencesSafe(state.preferences)
end

local function isContinuousMemoryLogEnabled()
  local general = state.preferences and state.preferences.general
  return type(general) == "table" and general.continuous_memory_log == true
end

local function isSerialMemoryLogEnabled()
  local general = state.preferences and state.preferences.general
  return type(general) == "table" and general.enable_serial_debug == true and type(serialWrite) == "function"
end

local function logMemoryUsage(now)
  if not isContinuousMemoryLogEnabled() then
    state.memLastTick = 0
    return
  end

  if type(collectgarbage) ~= "function" then
    return
  end

  local tickNow = tonumber(now) or 0
  if tickNow > 0 and state.memLastTick > 0 and (tickNow - state.memLastTick) < MEM_LOG_INTERVAL_TICKS then
    return
  end

  local memKb = math.floor((collectgarbage("count") or 0) + 0.5)
  if memKb > (state.memPeakKb or 0) then
    state.memPeakKb = memKb
  end

  state.memLastTick = tickNow > 0 and tickNow or (state.memLastTick or 0)

  local line = "[mem][info] lua_kb=" .. tostring(memKb) .. " peak_kb=" .. tostring(state.memPeakKb or memKb)
  local msg = "lua_kb=" .. tostring(memKb) .. " peak_kb=" .. tostring(state.memPeakKb or memKb)
  ensureLog()
  pcall(Log.emit, "mem", msg, "info", true)
end

local function resolveLocaleFromSystem()
  -- Always reload module on init so locale behavior changes are picked up
  -- immediately and not held back by stale cached globals.
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/system_locale.lua", "t")
  if chunk then
    local ok, localeMod = pcall(chunk)
    if ok and type(localeMod) == "table" and type(localeMod.resolveSystemLanguage) == "function" then
      if type(_G) == "table" then
        _G.__rfsuiteSystemLocaleModule = localeMod
      end
      local okResolve, locale = pcall(localeMod.resolveSystemLanguage, "en")
      if okResolve and type(locale) == "string" and locale ~= "" then
        return locale
      end
    end
  end

  return "en"
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

  ensureHelpRegistry()

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
    subtitle = shortenBreadcrumb(breadcrumb)
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
  ensurePageRegistry()
  return PageRegistry and PageRegistry.byMenuId and PageRegistry.byMenuId[menuId]
end

local function closeHelpDialogIfOpen()
  state.helpContent = nil
  state.helpPageTitle = nil
  state.helpPageSubtitle = nil
end

local function applyLocaleFromPreferences()
  local lang = nil
  local general = state.preferences and state.preferences.general
  if type(general) == "table" then
    lang = general.language
  end

  if state.i18n and type(state.i18n.setLocale) == "function" then
    pcall(state.i18n.setLocale, lang or "en")
  end
end

local function getMspUnsupportedDialogModule()
  if mspUnsupportedDialogLoadTried then
    return mspUnsupportedDialogModule
  end

  mspUnsupportedDialogLoadTried = true
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/ui/msp_unsupported_dialog.lua", "t")
  if type(chunk) ~= "function" then
    return nil
  end

  local ok, mod = pcall(chunk)
  if ok and type(mod) == "table" and type(mod.show) == "function" then
    mspUnsupportedDialogModule = mod
  end

  return mspUnsupportedDialogModule
end

local confirmDialogModule = nil
local confirmDialogLoadTried = false
local function getConfirmDialogModule()
  if confirmDialogLoadTried then
    return confirmDialogModule
  end
  confirmDialogLoadTried = true
  local chunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/ui/confirm_dialog.lua", "t")
  if type(chunk) ~= "function" then
    return nil
  end
  local ok, mod = pcall(chunk)
  if ok and type(mod) == "table" and type(mod.show) == "function" then
    confirmDialogModule = mod
  end
  return confirmDialogModule
end

local function maybeShowUnsupportedMspDialog()
  if not state.i18n then
    return
  end

  local root = _G and _G.rfsuite
  local session = root and root.session
  local diagnostics = root and root.diagnostics
  if type(session) ~= "table" and type(diagnostics) ~= "table" then
    return
  end

  local function tr(key, fallback)
    local value = state.i18n.t and state.i18n.t(key) or nil
    if type(value) ~= "string" or value == "" or value == key then
      return fallback
    end
    return value
  end

  local apiSupported = nil
  if type(session) == "table" and session.apiSupported ~= nil then
    apiSupported = session.apiSupported
  elseif type(diagnostics) == "table" and diagnostics.apiSupported ~= nil then
    apiSupported = diagnostics.apiSupported
  end

  if apiSupported == true then
    return
  end

  if apiSupported ~= false then
    return
  end

  local apiVersion = nil
  if type(session) == "table" and session.apiVersion ~= nil then
    apiVersion = session.apiVersion
  elseif type(diagnostics) == "table" and diagnostics.apiVersion ~= nil then
    apiVersion = diagnostics.apiVersion
  end
  local version = tostring(apiVersion or "?")

  local supported = "-"
  ensureVersion()
  if Version and type(Version.getSupportedMspApiVersionsString) == "function" then
    supported = Version.getSupportedMspApiVersionsString() or "-"
  end

  local title = tr("app.msp.unsupported_title", "Unsupported MSP API")
  local prefix = tr("app.msp.unsupported_message_prefix", "MSP API version ")
  local suffix = tr("app.msp.unsupported_message_suffix", " is not supported.")
  local supportedLabel = tr("app.msp.supported_label", "Supported: ")
  local message = prefix .. version .. suffix .. "\n" .. supportedLabel .. tostring(supported)

  local dialog = getMspUnsupportedDialogModule()
  if dialog then
    local shown = dialog.show({
      title = title,
      message = message,
      version = version,
      onFallback = function(fallbackTitle, fallbackMessage)
        state.helpContent = fallbackMessage
        state.helpPageTitle = fallbackTitle
        state.helpPageSubtitle = nil
        scheduleBuildUI(false)
      end
    })
    if shown then
      return
    end
  end

  -- Ultimate fallback if dialog module failed to load.
  state.helpContent = message
  state.helpPageTitle = title
  state.helpPageSubtitle = nil
  scheduleBuildUI(false)
end

local function maybeShowMspLinkConfigDialog()
  if not state.i18n then
    return
  end

  local root = _G and _G.rfsuite
  local session = root and root.session
  local diagnostics = root and root.diagnostics
  if type(session) ~= "table" and type(diagnostics) ~= "table" then
    return
  end

  local function tr(key, fallback)
    local value = state.i18n.t and state.i18n.t(key) or nil
    if type(value) ~= "string" or value == "" or value == key then
      return fallback
    end
    return value
  end

  local errMsg = nil
  local errAt = 0
  if type(session) == "table" then
    errMsg = session.mspLastError or errMsg
    errAt = tonumber(session.mspLastErrorAt) or errAt
  end
  if (not errMsg or errMsg == "") and type(diagnostics) == "table" then
    errMsg = diagnostics.mspLastError or errMsg
    errAt = tonumber(diagnostics.mspLastErrorAt) or errAt
  end

  if type(errMsg) ~= "string" or errMsg == "" then
    state.mspLinkConfigWarningAt = 0
    return
  end

  if not string.find(errMsg, "cmd=1", 1, true) then
    return
  end

  if errAt > 0 and state.mspLinkConfigWarningAt == errAt then
    return
  end

  local title = tr("app.msp.link_config_title", "MSP link configuration")
  local l1 = tr("app.msp.link_config_message_1", "Initial MSP read failed (API_VERSION).")
  local l2 = tr("app.msp.link_config_message_2", "Please check Rotorflight telemetry settings.")
  local l3 = tr("app.msp.link_config_message_3", "Packet Rate and Packet Ratio must match the ELRS link.")
  local l4 = tr("app.msp.link_config_message_4", "Then reconnect and open Info again.")
  local message = l1 .. "\n" .. l2 .. "\n" .. l3 .. "\n" .. l4

  local dialog = getMspUnsupportedDialogModule()
  if dialog then
    local shown = dialog.show({
      title = title,
      message = message,
      onFallback = function(fallbackTitle, fallbackMessage)
        state.helpContent = fallbackMessage
        state.helpPageTitle = fallbackTitle
        state.helpPageSubtitle = nil
        scheduleBuildUI(false)
      end
    })
    if shown then
      state.mspLinkConfigWarningAt = errAt > 0 and errAt or (state.mspLinkConfigWarningAt + 1)
      return
    end
  end

  state.helpContent = message
  state.helpPageTitle = title
  state.helpPageSubtitle = nil
  state.mspLinkConfigWarningAt = errAt > 0 and errAt or (state.mspLinkConfigWarningAt + 1)
  scheduleBuildUI(false)
end

local function readFblConnected()
  local root = _G and _G.rfsuite
  local session = root and root.session
  if type(session) == "table" and session.isConnected ~= nil then
    return session.isConnected == true
  end

  if not MspRuntime or type(MspRuntime.getState) ~= "function" then
    return false
  end

  local mspState = MspRuntime.getState()
  if type(mspState) ~= "table" then
    return false
  end

  -- MSP-Version nicht unterstützt? Dann wie "nicht verbunden" behandeln
  if mspState.unsupportedApi == true then
    return false
  end
  if mspState.apiSupported == false then
    return false
  end

  return mspState.lastConnected == true
end

local function updateRuntimeMenuConditions()
  if not state.menu then return end

  local nextFblConnected = readFblConnected()
  if state.fblConnected ~= nextFblConnected then
    state.fblConnected = nextFblConnected
    state.menu.setCondition("fblConnected", nextFblConnected)
    scheduleBuildUI(false)
  end
end

local function maybeRefreshInfoPageFromSession()
  if not state.menu or state.menu.getCurrentMenuId() ~= "diagnostics_info_page" then
    state.infoSessionSnapshot = nil
    return
  end

  local root = _G and _G.rfsuite
  local session = root and root.session
  local diagnostics = root and root.diagnostics
  if type(session) ~= "table" then
    return
  end

  local snapshot = tostring(session.apiVersion or "") .. "|" .. tostring(session.fcVersion or "") .. "|" .. tostring(session.rfVersion or "") ..
    "|" .. tostring(session.mcu_id or "") ..
    "|" .. tostring(session.mspLastError or "") .. "|" .. tostring(session.mspLastErrorAt or "") ..
    "|" .. tostring(diagnostics and diagnostics.mspLastError or "") .. "|" .. tostring(diagnostics and diagnostics.mspLastErrorAt or "")
  if state.infoSessionSnapshot ~= snapshot then
    state.infoSessionSnapshot = snapshot
    scheduleBuildUI(false)
  end
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

    local function doPageReload()
      -- Keep preferences in-memory for reload to avoid repeated disk loads and table churn.
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
    end

    local reloadPref = state.preferences and state.preferences.general and state.preferences.general.reload_confirm
    if reloadPref == true and lvgl then
      local function tr(key, fallback)
        if state and state.i18n and type(state.i18n.t) == "function" then
          local ok, val = pcall(state.i18n.t, key)
          if ok and type(val) == "string" and val ~= "" and val ~= key then
            return val
          end
        end
        return fallback
      end

      local title = tr("app.pages.settings_general.reload_confirm", "Confirm on Reload")
      local message = tr("app.dialogs.confirm_reload", "Reload and discard unsaved changes?")

      ensureLog()
      pcall(Log.emit, "rfsuite", "onReload invoked; reloadPref=true", "debug", true)
      if lvgl then
        pcall(Log.emit, "rfsuite", "lvgl types: confirm=" .. tostring(type(lvgl.confirm)) .. ", dialog=" .. tostring(type(lvgl.dialog)) .. ", alert=" .. tostring(type(lvgl.alert)), "debug", true)
      else
        pcall(Log.emit, "rfsuite", "lvgl is nil", "debug", true)
      end

      local confirmModule = getConfirmDialogModule()
      if confirmModule and type(confirmModule.show) == "function" then
        local ok, res = pcall(confirmModule.show, {
          title = title,
          message = message,
          onConfirm = doPageReload,
          onCancel = function() end,
          onFallback = doPageReload
        })
        ensureLog()
        if ok and res == true then return end
      end

      if type(lvgl.confirm) == "function" then
        local ok, res = pcall(lvgl.confirm, { title = title, message = message })
        ensureLog()
        pcall(Log.emit, "rfsuite", "called lvgl.confirm; pcall ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true)
        if ok and res == true then doPageReload() end
        return
      end

      -- Fallback: no confirm UI available — proceed with reload.
      ensureLog()
      pcall(Log.emit, "rfsuite", "no confirm API available; performing reload fallback", "debug", true)
      doPageReload()
      return
    end

    -- Preference disabled: just reload immediately.
    doPageReload()
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

    -- Helper that performs the actual page save logic.
    local function doPageSave()
      local shouldRebuild = page.onSave({
        i18n = state.i18n,
        preferences = state.preferences,
        menu = state.menu,
        savePreferences = performSave,
        refresh = M.buildUI
      })

      -- Apply possibly updated language setting immediately after save.
      applyLocaleFromPreferences()

      if shouldRebuild ~= false then
        scheduleBuildUI(false)
      end
    end

    -- Check preference and show confirm dialog if enabled.
    local savePref = state.preferences and state.preferences.general and state.preferences.general.save_confirm
    if savePref == true and lvgl then
      local function tr(key, fallback)
        if state and state.i18n and type(state.i18n.t) == "function" then
          local ok, val = pcall(state.i18n.t, key)
          if ok and type(val) == "string" and val ~= "" and val ~= key then
            return val
          end
        end
        return fallback
      end

      local title = tr("app.pages.settings_general.save_confirm", "Confirm on Save")
      local message = tr("app.dialogs.confirm_save", "Save changes?")

      ensureLog()
      pcall(Log.emit, "rfsuite", "onSave invoked; savePref=true", "debug", true)
      if lvgl then
        pcall(Log.emit, "rfsuite", "lvgl types: confirm=" .. tostring(type(lvgl.confirm)) .. ", dialog=" .. tostring(type(lvgl.dialog)) .. ", alert=" .. tostring(type(lvgl.alert)), "debug", true)
      else
        pcall(Log.emit, "rfsuite", "lvgl is nil", "debug", true)
      end

      local confirmModule = getConfirmDialogModule()
      if confirmModule and type(confirmModule.show) == "function" then
        local ok, res = pcall(confirmModule.show, {
          title = title,
          message = message,
          onConfirm = doPageSave,
          onCancel = function() end,
          onFallback = doPageSave
        })
        ensureLog()
        if ok and res == true then return end
      end

      if type(lvgl.confirm) == "function" then
        local ok, res = pcall(lvgl.confirm, { title = title, message = message })
        ensureLog()
        pcall(Log.emit, "rfsuite", "called lvgl.confirm; pcall ok=" .. tostring(ok) .. ", res=" .. tostring(res), "debug", true)
        if ok and res == true then doPageSave() end
        return
      end

      -- Fallback: no confirm API available — proceed with save.
      ensureLog()
      pcall(Log.emit, "rfsuite", "no confirm API available; performing save fallback", "debug", true)
      doPageSave()
      return
    end

    -- Preference disabled: just save immediately.
    doPageSave()
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

  ensureBuildDeps()

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
  local currentMenuId = state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or "root"
  if currentMenuId ~= "root" and not PageRegistry then
    ensurePageRegistry()
  end
  local actions = Header.resolveActions({
    headerActions = state.headerActions,
    menu          = state.menu,
    i18n          = state.i18n,
    preferences   = state.preferences,
    PageRegistry  = PageRegistry,
    HelpRegistry  = HelpRegistry
  })

  -- Clear and reuse the children table to reduce garbage collection
  local children = state.children
  wipeTable(children)

  local contentX = contentPad
  local contentY = tileGap
  local contentW = LCD_W - contentPad * 2

  -- ── Help view (no lvgl.dialog – avoids LVGL lifecycle crashes) ───────────────
  if state.helpContent then
    ensureHelpView()
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
    if lvgl and type(lvgl.clear) == "function" then
      lvgl.clear()
    end
    lvgl.build(helpLyt)
    return
  end
  -- ── End help view ────────────────────────────────────────────────────────────

  if state.menu.isRoot() then
    local groups    = state.menu.getRootGroups(ICON_ROOT)
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
      local layoutItems, rows = toWrappedItems(group.cards, columns)

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
    currentMenuId = state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or nil
    ensurePageRegistry()
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
      local layoutItems, rows = toWrappedItems(gridItems, columns)
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
  local rootSubtitle = nil
  if breadcrumb ~= "" then
    rootSubtitle = shortenBreadcrumb(breadcrumb)
  elseif state.menu.isRoot() and Version and type(Version.getVersionString) == "function" then
    rootSubtitle = Version.getVersionString()
  end

  local lyt = {
    {
      type     = "page",
      title    = pageTitle,
      subtitle = rootSubtitle,
      icon     = APP_ICON,
      back     = onBack,
      children = children
    }
  }

  Header.appendToLayout(lyt, {
    actions  = actions,
    i18n     = state.i18n,
    preferences = state.preferences,
    layout   = profile.header,
    onHelp   = onHelp,
    onStar   = onStar,
    onReload = onReload,
    onSave   = onSave,
    onBack   = onBack
  })

  if lvgl and type(lvgl.clear) == "function" then
    lvgl.clear()
  end
  lvgl.build(lyt)
end

-- ── Init / Run ────────────────────────────────────────────────────────────────

function M.init()
  ensureInitDeps()

  ensurePreferencesSafe()
  state.shouldExit = false
  local prefs = loadPreferencesSafe()
  state.preferences = prefs
  _G.rfsuite.preferences = prefs
  local locale = resolveLocaleFromSystem()
  state.i18n       = I18n.new(locale)
  _G.rfsuite.savePreferences = performSave
  state.manifest = manifest
  state.menu       = MenuRegistry.new(manifest, state.i18n, {
    conditions = {
      developerTools = prefs.general and prefs.general.developer_tools == true,
      fblConnected = false
    },
    iconByMenuIdProvider = function()
      ensurePageRegistry()
      return PageRegistry and PageRegistry.iconByMenuId or nil
    end
  })
  state.memBucket  = nil
  state.memLastTick = 0
  state.memPeakKb = 0
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
  state.mspLastTick = 0
  state.fblConnected = false
  state.infoSessionSnapshot = nil
  state.mspUnsupportedDialogShown = false
  state.mspUnsupportedVersionShown = nil
  state.mspLinkConfigWarningAt = 0
  state.mspAttached = false
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
    local now = getTime and getTime() or 0

    if not state.mspAttached then
      ensureMspRuntime()
      if MspRuntime and type(MspRuntime.attach) == "function" then
        MspRuntime.attach("tool")
        state.mspAttached = true
      end
    end

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

    local currentMenuId = state.menu and state.menu.getCurrentMenuId and state.menu.getCurrentMenuId() or nil
    local mspSpeedPageActive = currentMenuId == "developer_msp_speed_page"

    if (not mspSpeedPageActive) and MspRuntime and type(MspRuntime.tick) == "function" then
      if now == 0 or (now - (state.mspLastTick or 0)) >= 5 then
        state.mspLastTick = now
        MspRuntime.tick()
        -- Let the events manager observe MSP state transitions (connect/disconnect)
        ensureEvents()
        if Events and type(Events.wakeup) == "function" then
          pcall(Events.wakeup)
        end
      end
    end

    local activePage = getActivePageModule()
    local wakeupFn = activePage and (activePage.wakeup or activePage.onWake)
    if type(wakeupFn) == "function" then
      local ok, err = pcall(wakeupFn, {
        i18n = state.i18n,
        preferences = state.preferences,
        menu = state.menu,
        manifest = state.manifest,
        requestRebuild = function() scheduleBuildUI(false) end
      })
      if not ok then
        ensureLog()
        pcall(Log.emit, "rfsuite", "Crash in activePage.wakeup: " .. tostring(err), "error", true)
        if type(serialWrite) == "function" then
          pcall(serialWrite, "[rfsuite][error] Crash in activePage.wakeup: " .. tostring(err) .. "\n")
        end
      end
    end

    logMemoryUsage(now)

    updateRuntimeMenuConditions()
    maybeRefreshInfoPageFromSession()

    -- Audio Feedback Polling (gedrosselt auf ca. 5Hz)
    if Audio and type(Audio.process) == "function" and (now - state.lastAudioTick) > 0.2 then
      state.lastAudioTick = now
      
      local lq = Sensors and Sensors.getValue("link") or 0
      local vbat = Sensors and Sensors.getValue("voltage") or 0
      local fuel = Sensors and Sensors.getValue("fuel") or -1

      if Sensors then
        state.telemetryState.profile = Sensors.getValue("pid_profile") or state.telemetryState.profile
        state.telemetryState.rateProfile = Sensors.getValue("rate_profile") or state.telemetryState.rateProfile
        state.telemetryState.batteryProfile = Sensors.getValue("battery_profile") or state.telemetryState.batteryProfile
        state.telemetryState.armFlags = Sensors.getValue("armflags") or state.telemetryState.armFlags
        state.telemetryState.governor = Sensors.getValue("governor") or state.telemetryState.governor
        state.telemetryState.escTemp = Sensors.getValue("temp_esc") or state.telemetryState.escTemp
      end

      state.telemetryState.voltage = vbat > 0 and vbat or state.telemetryState.voltage
      state.telemetryState.fuel = fuel >= 0 and fuel or state.telemetryState.fuel

      local batteryReady = (vbat > 0) or (fuel >= 0)
      local rfReady = (lq ~= 0)
      local connected = readFblConnected()

      if connected and batteryReady and rfReady then
        local audioContext = {
          audioState = state.audioState,
          preferences = state.preferences,
          state = state.telemetryState
        }
        Audio.process(audioContext, { log = function(msg, level) if Log then pcall(Log.emit, "rfsuite.audio", msg, level, false) end end })
      else
        state.audioState.initialized = false
      end
    end

    maybeShowUnsupportedMspDialog()
    maybeShowMspLinkConfigDialog()

    -- Intentionally no periodic MEM-triggered rebuild here.
    -- Rebuilding while navigating resets LVGL focus on some pages.
    -- MEM value updates on normal UI rebuild points (navigation/actions).
  end

  if state.shouldExit then
    if state.mspAttached and MspRuntime and type(MspRuntime.detach) == "function" then
      MspRuntime.detach("tool")
      state.mspAttached = false
    end
    return 2
  end
  return 0
end

return { init = M.init, run = M.run, useLvgl = true }
