local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = loadScript(fullPath, "t")
  if type(chunk) ~= "function" then return nil end
  local ok, mod = pcall(chunk)
  if not ok then return nil end
  return mod
end

local Common = nil
local t = nil
local GridLayout = nil
local Tiles = nil
local DisplayProfile = nil
local ConfirmDialog = nil

local MFG_INDEX = {
  { folder = "am32",     name = "AM32",      image = "icon.png" },
  { folder = "blheli_s", name = "BLHeli_S",  image = "icon.png" },
  { folder = "bluejay",  name = "Bluejay",   image = "icon.png" },
  { folder = "flrtr",    name = "Flyrotor",  image = "icon.png" },
  { folder = "hw5",      name = "Hobbywing", image = "icon.png" },
  { folder = "omp",      name = "OMP",       image = "icon.png" },
  { folder = "scorp",    name = "Scorpion",  image = "icon.png" },
  { folder = "xdfly",    name = "XDFly",     image = "icon.png" },
  { folder = "yge",      name = "YGE",       image = "icon.png" },
  { folder = "ztw",      name = "ZTW",       image = "icon.png" }
}

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not t then t = Common and Common.pageT("setup_esc_motors") or nil end
  if not GridLayout then GridLayout = loadModule("layouts/grid.lua") end
  if not Tiles then Tiles = loadModule("ui/tiles.lua") end
  if not DisplayProfile then DisplayProfile = loadModule("core/display_profile.lua") end
  if not ConfirmDialog then ConfirmDialog = loadModule("ui/confirm_dialog.lua") end
end

local function pageText(i18n, key, fallback)
  if t then
    local translated = t(i18n, key, fallback)
    if translated ~= nil and translated ~= "" and translated ~= key then
      return translated
    end
  end
  return fallback
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

local function computeTileSize(cardW, cardH, cfg)
  local size = math.min(cfg.tileMax or 120, cardW)
  if size < 1 then
    return 1
  end
  return size
end

function M.onLoad()
  ensureDeps()
end

function M.onActivate()
  ensureDeps()
end

function M.wakeup(ctx)
  ensureDeps()
end

function M.getHeaderActions()
  return {
    menu = true
  }
end

function M.build(ctx)
  ensureDeps()
  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local h = ctx.h
  local i18n = ctx.i18n

  -- Sync header title
  local title = pageText(i18n, "esc_tools", "ESC Tools")
  if type(ctx.syncHeaderTitle) == "function" then
    ctx.syncHeaderTitle(title, M.getHeaderActions())
  end

  local profile = DisplayProfile.current()
  local contentW = w - 4
  local tileGap = profile.tileGap or 10
  local minCardWidth = profile.menuMinCardWidth or 120
  local maxColumns = profile.menuMaxColumns or 4

  local columns = Tiles.computeColumns(contentW, minCardWidth, maxColumns)
  
  local gridItems = {}
  for i, mfg in ipairs(MFG_INDEX) do
    gridItems[i] = {
      id = mfg.folder,
      data = {
        text = mfg.name,
        icon = "/SCRIPTS/TOOLS/rfsuite-core/app/pages/setup/esc_motors/esc_tools/escmfg/" .. mfg.folder .. "/" .. mfg.image,
        enabled = true
      }
    }
  end

  local layoutItems, rows = toWrappedItems(gridItems, columns)
  local rowHeight = profile.tileMax or 120
  local gridH = rows * rowHeight + math.max(0, rows - 1) * tileGap

  local cards = GridLayout.layout(
    { x = x + 2, y = y + 2, w = contentW, h = gridH },
    { rows = rows, cols = columns, gap = tileGap, padding = 2, items = layoutItems },
    {}
  )

  for i = 1, #cards do
    local card     = cards[i]
    local tileSize = computeTileSize(card.w, card.h, profile)
    local tileX    = card.x + math.floor((card.w - tileSize) / 2)
    local tileY    = card.y + math.floor((card.h - tileSize) / 2)

    local function getPressHandler()
      return function()
        if not ConfirmDialog then
          -- Fallback if no confirm dialog
          _G.rfsuite = _G.rfsuite or {}
          _G.rfsuite.selectedEscMfg = card.id
          if ctx.menu and type(ctx.menu.openEntry) == "function" then
            ctx.menu.openEntry("setup_esc_motors_esc_tool_run_page")
          end
          return
        end

        local warningTitle = pageText(i18n, "safety_warning_title", "Safety Warning")
        local warningMsg = pageText(i18n, "remove_blades_warning", "Please remove main and tail blades before configuring the ESC!")

        ConfirmDialog.show({
          title = warningTitle,
          message = warningMsg,
          onConfirm = function()
            _G.rfsuite = _G.rfsuite or {}
            _G.rfsuite.selectedEscMfg = card.id
            if ctx.menu and type(ctx.menu.openEntry) == "function" then
              ctx.menu.openEntry("setup_esc_motors_esc_tool_run_page")
            end
          end
        })
      end
    end

    Tiles.append(
      children, tileX, tileY, tileSize,
      card.data.icon, card.data.text,
      false, -- focused
      getPressHandler(),
      card.data.enabled
    )
  end
end

function M.onClose()
  Common = nil
  t = nil
  GridLayout = nil
  Tiles = nil
  DisplayProfile = nil
  ConfirmDialog = nil
end

return M
