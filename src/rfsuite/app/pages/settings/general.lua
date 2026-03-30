local M = {}

local ui = {
  loaded = false,
  dirty = false,
  comboOpen = nil,
  sections = {
    display = true,
    safety = false,
    integration = false,
    development = true
  },
  config = {
    iconsize = 2,
    developer_tools = false
  }
}

local ICONSIZE_OPTIONS = {
  { value = 0, key = "combo_text", fallback = "TEXT" },
  { value = 1, key = "combo_small", fallback = "KLEIN" },
  { value = 2, key = "combo_large", fallback = "GROSS" }
}

local function t(i18n, key, fallback)
  if i18n and i18n.t then
    return i18n.t("app.pages.settings_general." .. key)
  end
  return fallback
end

local function copyFromPrefs(prefs)
  local general = (prefs and prefs.general) or {}
  ui.config.iconsize = tonumber(general.iconsize) or 2
  ui.config.developer_tools = general.developer_tools == true
end

local function ensureLoaded(prefs)
  if ui.loaded then return end
  copyFromPrefs(prefs)
  ui.loaded = true
  ui.dirty = false
  ui.comboOpen = nil
end

local function markDirty()
  ui.dirty = true
end

local function toggleSection(name)
  ui.sections[name] = not ui.sections[name]
end

local function getIconSizeLabel(i18n)
  for i = 1, #ICONSIZE_OPTIONS do
    if ICONSIZE_OPTIONS[i].value == ui.config.iconsize then
      return t(i18n, ICONSIZE_OPTIONS[i].key, ICONSIZE_OPTIONS[i].fallback)
    end
  end
  return t(i18n, "combo_large", "GROSS")
end

local function appendSectionHeader(children, x, y, w, title, expanded, onToggle)
  children[#children + 1] = {
    type = "label",
    x = x,
    y = y,
    text = title,
    color = WHITE,
    font = DBLSIZE
  }

  local arrowW = 32
  local arrowX = x + w - arrowW
  children[#children + 1] = {
    type = "button",
    x = arrowX,
    y = y,
    w = arrowW,
    h = 28,
    text = expanded and "v" or ">",
    press = onToggle
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

local function appendComboRow(children, x, y, w, labelText, valueText, selected, onPress)
  local valueW = math.floor(w * 0.52)
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
    type = "button",
    x = valueX,
    y = y,
    w = valueW,
    h = 40,
    text = "",
    press = onPress,
    color = selected and COLOR_THEME_SECONDARY1 or GREY_DEFAULT
  }

  children[#children + 1] = {
    type = "label",
    x = valueX + 8,
    y = y + 10,
    w = valueW - 30,
    text = valueText,
    color = selected and BLACK or WHITE,
    align = RIGHT,
    font = MIDSIZE
  }

  children[#children + 1] = {
    type = "label",
    x = valueX + valueW - 20,
    y = y + 10,
    w = 14,
    text = "v",
    color = selected and BLACK or WHITE,
    align = RIGHT,
    font = MIDSIZE
  }

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

local function appendRadioSwitchRow(children, x, y, w, labelText, valueOn, onToggleOff, onToggleOn)
  local valueW = math.floor(w * 0.34)
  local valueX = x + w - valueW
  local btnW = math.floor((valueW - 8) / 2)

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
    type = "button",
    x = valueX,
    y = y,
    w = btnW,
    h = 40,
    text = t(nil, "value_off", "AUS"),
    press = onToggleOff,
    color = valueOn and GREY_DEFAULT or COLOR_THEME_SECONDARY1
  }

  children[#children + 1] = {
    type = "button",
    x = valueX + btnW + 8,
    y = y,
    w = btnW,
    h = 40,
    text = t(nil, "value_on", "EIN"),
    press = onToggleOn,
    color = valueOn and COLOR_THEME_SECONDARY1 or GREY_DEFAULT
  }

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

local function appendComboPopup(children, x, y, w, i18n, requestRebuild)
  local popupW = math.min(380, math.floor(w * 0.52))
  local popupX = x + w - popupW
  local optionH = 44

  children[#children + 1] = {
    type = "rectangle",
    x = popupX,
    y = y,
    w = popupW,
    h = optionH * #ICONSIZE_OPTIONS,
    color = GREY_DEFAULT,
    filled = true
  }

  for i = 1, #ICONSIZE_OPTIONS do
    local opt = ICONSIZE_OPTIONS[i]
    local selected = opt.value == ui.config.iconsize
    children[#children + 1] = {
      type = "button",
      x = popupX,
      y = y + (i - 1) * optionH,
      w = popupW,
      h = optionH,
      text = t(i18n, opt.key, opt.fallback),
      color = selected and COLOR_THEME_SECONDARY1 or GREY_DEFAULT,
      press = function()
        ui.config.iconsize = opt.value
        ui.comboOpen = nil
        markDirty()
        requestRebuild()
      end
    }
  end
end

function M.getHeaderActions()
  return {
    save = ui.dirty,
    reload = true,
    help = false
  }
end

function M.allowMemAutoRefresh()
  return ui.comboOpen == nil
end

function M.onReload(ctx)
  copyFromPrefs(ctx.preferences)
  ui.comboOpen = nil
  ui.dirty = false
end

function M.onSave(ctx)
  if not ctx.preferences.general then ctx.preferences.general = {} end
  ctx.preferences.general.iconsize = ui.config.iconsize
  ctx.preferences.general.developer_tools = ui.config.developer_tools == true

  local ok, err = ctx.savePreferences()
  if ok then
    if ctx.menu and ctx.menu.setCondition then
      ctx.menu.setCondition("developerTools", ui.config.developer_tools == true)
    end
    ui.dirty = false
    if lvgl and lvgl.alert then
      lvgl.alert({
        title = t(ctx.i18n, "saved_title", "Gespeichert"),
        message = t(ctx.i18n, "saved_message", "Einstellungen gespeichert")
      })
    end
  else
    if lvgl and lvgl.alert then
      lvgl.alert({
        title = t(ctx.i18n, "save_error_title", "Fehler"),
        message = (t(ctx.i18n, "save_error_message", "Speichern fehlgeschlagen") .. ": " .. tostring(err or "io"))
      })
    end
  end
end

function M.build(ctx)
  ensureLoaded(ctx.preferences)

  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local i18n = ctx.i18n
  local requestRebuild = ctx.requestRebuild

  local cursorY = y

  appendSectionHeader(
    children,
    x,
    cursorY,
    w,
    t(i18n, "section_display", "Anzeige"),
    ui.sections.display,
    function()
      toggleSection("display")
      ui.comboOpen = nil
      requestRebuild()
    end
  )

  cursorY = cursorY + 46
  if ui.sections.display then
    appendComboRow(
      children,
      x,
      cursorY,
      w,
      t(i18n, "icon_size", "Icongroesse"),
      getIconSizeLabel(i18n),
      ui.comboOpen == "iconsize",
      function()
        ui.comboOpen = (ui.comboOpen == "iconsize") and nil or "iconsize"
        requestRebuild()
      end
    )

    if ui.comboOpen == "iconsize" then
      appendComboPopup(children, x, cursorY + 42, w, i18n, requestRebuild)
      cursorY = cursorY + 44 + (44 * #ICONSIZE_OPTIONS)
    else
      cursorY = cursorY + 44
    end
  end

  cursorY = cursorY + 10
  appendSectionHeader(
    children,
    x,
    cursorY,
    w,
    t(i18n, "section_development", "Entwicklung"),
    ui.sections.development,
    function()
      toggleSection("development")
      requestRebuild()
    end
  )

  cursorY = cursorY + 46
  if ui.sections.development then
    appendRadioSwitchRow(
      children,
      x,
      cursorY,
      w,
      t(i18n, "developer_tools", "Entwickler Tools"),
      ui.config.developer_tools == true,
      function()
        if ui.config.developer_tools ~= false then
          ui.config.developer_tools = false
          markDirty()
          requestRebuild()
        end
      end,
      function()
        if ui.config.developer_tools ~= true then
          ui.config.developer_tools = true
          markDirty()
          requestRebuild()
        end
      end
    )
  end
end

return M
