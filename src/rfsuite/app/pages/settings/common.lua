local M = {}

local function wipeTable(t)
  if type(t) ~= "table" then return end
  for k in pairs(t) do
    t[k] = nil
  end
end

function M.t(i18n, pageKey, key, fallback)
  if i18n and i18n.t then
    return i18n.t("app.pages." .. pageKey .. "." .. key)
  end
  return fallback
end

function M.pageT(pageKey)
  return function(i18n, key, fallback)
    return M.t(i18n, pageKey, key, fallback)
  end
end

-- Reusable runtime helpers for settings pages with toggle fields.
-- Keeps per-build allocations low by caching handlers/getters/setters.
function M.createFormRuntime(ui)
  local runtime = {
    requestRebuild = nil,
    sectionToggleHandlers = {},
    boolGetters = {},
    boolSetters = {}
  }

  local function markDirty()
    if ui.dirty then return end
    ui.dirty = true
    local rebuild = runtime.requestRebuild
    if rebuild then rebuild() end
  end

  function runtime.setRequestRebuild(fn)
    runtime.requestRebuild = fn
  end

  function runtime.markDirty()
    markDirty()
  end

  function runtime.getSectionToggleHandler(name)
    local handler = runtime.sectionToggleHandlers[name]
    if handler then return handler end

    handler = function()
      ui.sections[name] = not ui.sections[name]
      local rebuild = runtime.requestRebuild
      if rebuild then rebuild() end
    end
    runtime.sectionToggleHandlers[name] = handler
    return handler
  end

  function runtime.getBoolGetter(key)
    local getter = runtime.boolGetters[key]
    if getter then return getter end

    getter = function(nextVal)
      if nextVal ~= nil then return end
      return ui.config[key] == true
    end
    runtime.boolGetters[key] = getter
    return getter
  end

  function runtime.getBoolSetter(key)
    local setter = runtime.boolSetters[key]
    if setter then return setter end

    setter = function(nextVal)
      ui.config[key] = (nextVal == true)
      markDirty()
    end
    runtime.boolSetters[key] = setter
    return setter
  end

  return runtime
end

-- Shared teardown helper for page modules.
-- Keeps close/reset behavior consistent across pages.
function M.resetPageState(ui, opts)
  opts = opts or {}
  if type(ui) ~= "table" then return end

  if opts.resetLoaded ~= false and ui.loaded ~= nil then
    ui.loaded = false
  end
  if opts.resetDirty ~= false and ui.dirty ~= nil then
    ui.dirty = false
  end
  if opts.clearRebuild == true and ui.rebuild ~= nil then
    ui.rebuild = nil
  end
  if opts.clearLastAutoRefresh == true and ui.lastAutoRefreshAt ~= nil then
    ui.lastAutoRefreshAt = 0
  end

  if type(ui.handlers) == "table" then
    wipeTable(ui.handlers)
  end

  if type(ui.runtime) == "table" then
    ui.runtime.requestRebuild = nil
    wipeTable(ui.runtime.sectionToggleHandlers)
    wipeTable(ui.runtime.boolGetters)
    wipeTable(ui.runtime.boolSetters)
    wipeTable(ui.runtime.valueGetters)
    wipeTable(ui.runtime.valueSetters)
  end
  ui.runtime = nil

  local tablesToWipe = opts.tablesToWipe
  if type(tablesToWipe) == "table" then
    for i = 1, #tablesToWipe do
      local key = tablesToWipe[i]
      if type(key) == "string" and type(ui[key]) == "table" then
        wipeTable(ui[key])
      end
    end
  end
end

function M.appendSectionHeader(children, x, y, w, title)
  children[#children + 1] = {
    type = "label",
    x = x,
    y = y,
    text = title,
    color = WHITE,
    font = DBLSIZE
  }

  children[#children + 1] = {
    type = "label",
    x = x + w - 18,
    y = y + 2,
    w = 16,
    text = "v",
    color = WHITE,
    align = RIGHT,
    font = DBLSIZE
  }

  children[#children + 1] = {
    type = "rectangle",
    x = x,
    y = y + 34,
    w = w,
    h = 1,
    color = GREY_DEFAULT,
    filled = true
  }
end

function M.appendSettingsRow(children, x, y, w, labelText, valueText, withArrow)
  local valueW = math.floor(w * 0.50)
  local valueX = x + w - valueW

  children[#children + 1] = {
    type = "label",
    x = x,
    y = y + 10,
    w = valueX - x - 8,
    text = labelText,
    color = WHITE,
    font = MIDSIZE
  }

  children[#children + 1] = {
    type = "rectangle",
    x = valueX,
    y = y,
    w = valueW,
    h = 40,
    color = GREY_DEFAULT,
    filled = true
  }

  local valueLabelW = withArrow and (valueW - 26) or (valueW - 10)
  children[#children + 1] = {
    type = "label",
    x = valueX + 6,
    y = y + 10,
    w = valueLabelW,
    text = valueText,
    color = WHITE,
    align = RIGHT,
    font = MIDSIZE
  }

  if withArrow then
    children[#children + 1] = {
      type = "label",
      x = valueX + valueW - 20,
      y = y + 10,
      w = 14,
      text = "v",
      color = WHITE,
      align = RIGHT,
      font = MIDSIZE
    }
  end

  children[#children + 1] = {
    type = "rectangle",
    x = x,
    y = y + 40,
    w = w,
    h = 1,
    color = GREY_DEFAULT,
    filled = true
  }
end

function M.buildSimplePage(ctx, pageKey, sectionKey, sectionFallback, rows)
  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local i18n = ctx.i18n

  M.appendSectionHeader(children, x, y, w, M.t(i18n, pageKey, sectionKey, sectionFallback))

  local rowY = y + 46
  for i = 1, #rows do
    local row = rows[i]
    local yOffset = (i - 1) * 44
    local label = M.t(i18n, pageKey, row.labelKey, row.labelFallback)
    local value = M.t(i18n, pageKey, row.valueKey, row.valueFallback)
    M.appendSettingsRow(children, x, rowY + yOffset, w, label, value, row.withArrow ~= false)
  end
end

return M
