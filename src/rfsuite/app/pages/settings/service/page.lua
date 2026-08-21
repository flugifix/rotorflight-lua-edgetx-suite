local M = {}

local function loadModule(path)
  local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
  local chunk = assert(loadScript(fullPath, "t"))
  return chunk()
end

local Controls = nil
local Common = nil

-- ─── Config schema ───────────────────────────────────────────────────────────
-- Single source of truth for what this page loads, defaults and saves. A control drawn here
-- whose key is not in this table is read from nothing and written to nothing.
--
-- Every key lives in preferences.general, where it already did: this page gives the settings a
-- home of their own, it does not move them between stores. A store move would need a migration
-- for anybody who has already set one.
local CONFIG_SCHEMA = {
  { key = "syncname",   type = "bool", default = false },
  { key = "syncparams", type = "bool", default = false },
}

local function buildDefaultConfig()
  local cfg = {}
  for _, field in ipairs(CONFIG_SCHEMA) do
    cfg[field.key] = field.default
  end
  return cfg
end

-- ─── State ────────────────────────────────────────────────────────────────────

local ui = {
  loaded = false,
  sections = {
    model = true,
  },
  config = buildDefaultConfig()
}

ui.runtime = nil

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local t = nil

local function ensureDeps()
  if not Common then
    Common = loadModule("app/pages/settings/common.lua")
  end
  if not Controls then
    Controls = loadModule("ui/controls.lua")
  end
  if not ui.runtime then
    ui.runtime = Common.createFormRuntime(ui)
  end
  if not t then
    t = Common.pageT("settings_service")
  end
end

local function prefBool(value, default)
  if value == nil then return default end
  return value == true or value == "true" or value == 1 or value == "1"
end

local function copyFromPrefs(prefs)
  local general = (prefs and prefs.general) or {}
  for _, field in ipairs(CONFIG_SCHEMA) do
    ui.config[field.key] = prefBool(general[field.key], field.default)
  end
end

local function ensureLoaded(prefs)
  if ui.loaded then return end
  copyFromPrefs(prefs)
  ui.loaded = true
end

-- ─── Section content builders ────────────────────────────────────────────────
-- Signature: (cursorY, children, x, w, i18n) -> newCursorY

local MODEL_ITEMS = {
  { key = "syncname",   labelKey = "sync_model_name",   fallback = "Synchronize Model Name" },
  { key = "syncparams", labelKey = "sync_model_params", fallback = "Synchronize Model Parameters" },
}

local function buildModel(cursorY, children, x, w, i18n)
  for _, item in ipairs(MODEL_ITEMS) do
    cursorY = cursorY + Controls.appendRadioSwitch(children, x, cursorY, w,
      t(i18n, item.labelKey, item.fallback),
      ui.runtime.getBoolGetter(item.key),
      ui.runtime.getBoolSetter(item.key)
    )
  end
  return cursorY
end

-- ─── Section manifest ────────────────────────────────────────────────────────
-- Add new sections here — one entry, one builder function above, done.

local SECTIONS = {
  { key = "model", titleKey = "section_model", titleFallback = "Model Synchronization", build = buildModel },
}

-- ─── Module API ──────────────────────────────────────────────────────────────

function M.getHeaderActions()
  ensureDeps()
  return { save = true, help = true }
end

function M.allowMemAutoRefresh()
  return true
end

function M.onReload(ctx)
  ensureDeps()
  copyFromPrefs(ctx.preferences)
end

function M.onSave(ctx)
  ensureDeps()
  if not ctx.preferences.general then ctx.preferences.general = {} end

  for _, field in ipairs(CONFIG_SCHEMA) do
    ctx.preferences.general[field.key] = ui.config[field.key]
  end

  local ok, err = ctx.savePreferences()
  if ok then
    if ctx and type(ctx.reportSave) == "function" then
      ctx.reportSave({
        title = t(ctx.i18n, "saved_title", "Saved"),
        message = t(ctx.i18n, "saved_message", "Settings saved")
      })
    end
  else
    if lvgl and lvgl.message then
      lvgl.message({
        title = t(ctx.i18n, "save_error_title", "Error"),
        message = t(ctx.i18n, "save_error_message", "Save failed") .. ": " .. tostring(err or "io")
      })
    end
  end
end

function M.build(ctx)
  ensureDeps()
  ensureLoaded(ctx.preferences)

  local children = ctx.children
  local x, w     = ctx.x, ctx.w
  local i18n     = ctx.i18n
  ui.runtime.setRequestRebuild(ctx.requestRebuild)
  local cursorY  = ctx.y

  for i, section in ipairs(SECTIONS) do
    if i > 1 then cursorY = cursorY + 10 end

    local key = section.key
    Controls.appendSectionHeader(children, x, cursorY, w,
      t(i18n, section.titleKey, section.titleFallback),
      ui.sections[key],
      ui.runtime.getSectionToggleHandler(key)
    )

    cursorY = cursorY + Controls.SECTION_H
    if ui.sections[key] then
      cursorY = section.build(cursorY, children, x, w, i18n)
    end
  end
end

function M.onClose()
  Common.resetPageState(ui)
  Controls = nil
  Common = nil
  t = nil
end

return M
