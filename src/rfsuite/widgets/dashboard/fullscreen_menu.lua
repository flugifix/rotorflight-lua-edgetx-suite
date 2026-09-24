local M = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require) or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local chunk = loadScript(fullPath, "t")
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

-- The translator, with the fallback the menu has always carried: a widget that has no i18n
-- table of its own still draws the English text an entry names.
local function translator(widget)
  local i18n = widget.i18n
  if i18n and type(i18n.t) == "function" then return i18n.t end
  return function(k, f) return f or k end
end

-- The conditions an entry's `visibleWhen` may name. The menu is built from the state of the
-- pass it is drawn in, so a condition is a function of the widget rather than a flag in a
-- table prepared beforehand; a name that is not here hides its entry, which is what an
-- unresolvable condition does in `app/menu_registry.lua` as well.
--
-- Only the vocabulary an entry below actually uses is resolved. `enabledWhen`,
-- `lockedWhileArmed` and `confirm` are part of the same manifest vocabulary and nothing here
-- sets one, so the first entry that needs one brings its resolver with it.
local CONDITIONS = {}

-- In-flight tuning, only for a model that has it switched on and only while the preview
-- switch is on.
--
-- The snapshot alone would very nearly do -- the drive that publishes it is not built with
-- the preview off -- but the menu is built from the preferences of this pass and the
-- snapshot is what the last one left behind. Reading the switch here means the entry cannot
-- offer a route into a feature the runtime has already stopped driving.
--
-- The entry is offered with the interlock OPEN on purpose: the setup check and the parameter
-- grid are what a pilot wants to see on the ground, and the interlock is what decides whether
-- anything is sent. The screen the entry opens is inert until the switch is thrown.
function CONDITIONS.previewInflightTuning(widget)
  local previewOn = widget.preferences and widget.preferences.general
    and widget.preferences.general.preview_inflight_tuning == true
  return previewOn == true and type(widget.state.inflight) == "table"
end

local function isEntryVisible(entry, widget)
  local conditionKey = entry.visibleWhen
  if conditionKey == nil then return true end
  local condition = CONDITIONS[conditionKey]
  if type(condition) ~= "function" then return false end
  return condition(widget) == true
end

--- What the menu offers, as a list rather than as drawing code.
--
-- One entry per row, in the order they are drawn, carrying the manifest's own vocabulary:
-- `id`, `title`, `kind`, `visibleWhen` and `press`. `kind` is what the builder makes of the
-- row -- `action` is a single button, `choice` is a title over a grid of options -- so the
-- battery-profile grid is a row of this list rather than a special case inside the builder.
--
-- The title is resolved here, and it is resolved from a complete literal key: the translation
-- precompiler rewrites what it can read, and a key assembled from parts ships the English
-- fallback in every language with nothing saying so.
function M.entries(widget)
  local t = translator(widget)
  local list = {}

  list[#list+1] = {
    id = "erase_blackbox",
    kind = "action",
    title = t("widgets.dashboard.erase_blackbox", "ERASE BLACKBOX"),
    press = function()
         local mspModule = requireModule("tasks/msp/runtime.lua")
         if mspModule and mspModule.getState then
            local mState = mspModule.getState()
            if mState and mState.queue then
               local eraseApi = requireModule("tasks/msp/api/dataflash_erase.lua")
               local summaryApi = requireModule("tasks/msp/api/dataflash_summary.lua")

               if eraseApi and summaryApi then
                 mState.queue:add({
                    command = eraseApi.writeCommand,
                    payload = eraseApi.buildWritePayload({}),
                    simulatorResponse = {},
                    isWrite = true,
                    timeout = 10.0,
                 })
                 mState.queue:add({
                    command = summaryApi.command,
                    simulatorResponse = summaryApi.simulatorResponse,
                    processReply = function(_, buf)
                      local stats = summaryApi.parse(buf)
                      if stats then
                        if type(_G) == "table" and _G.rfsuite and _G.rfsuite.session then
                          _G.rfsuite.session.dataflash = stats
                        end
                      end
                    end
                 })
               end
            end
         end

         widget.built = false
         widget.renderKey = nil
         if lcd and type(lcd.exitFullScreen) == "function" then
            lcd.exitFullScreen()
         end
    end
  }

  list[#list+1] = {
    id = "inflight_tuning",
    kind = "action",
    title = t("widgets.dashboard.inflight_open", "IN-FLIGHT TUNING"),
    visibleWhen = "previewInflightTuning",
    press = function()
        widget.inflightFullscreen = true
        widget.built = false
        widget.renderKey = nil
    end
  }

  list[#list+1] = {
    id = "battery_profile",
    kind = "choice",
    title = t("widgets.dashboard.battery_profile", "BATTERY PROFILE"),
    -- One option per capacity the flight controller carries, resolved when the row is drawn
    -- rather than when the list is made, so an entry stays a description of what it offers.
    options = function(w)
      local options = {}
      local state = w and w.state or {}
      local config = state.battery_config
      if config then
        for i=0,5 do
          local cap = config["batteryCapacity_"..i] or 0
          if cap > 0 then
            options[#options+1] = {
              label = tostring(cap).." mAh",
              -- Highlight active battery profile
              -- FIX: Telemetry sensor BatP is 1-based (1 to 6)
              current = (state.batteryProfile == (i + 1)),
              press = function()
                local mspModule = requireModule("tasks/msp/runtime.lua")
                if mspModule and mspModule.getState then
                  local mState = mspModule.getState()
                  if mState and mState.queue then
                     -- 1. Set Battery Profile
                     local api = requireModule("tasks/msp/api/battery_profile.lua")
                     if api and type(api.buildWritePayload) == "function" then
                       mState.queue:add({
                          command = api.writeCommand,
                          payload = api.buildWritePayload({ batteryProfile = i }),
                          simulatorResponse = {}
                       })
                     end
                     -- 2. Save to EEPROM so the FC applies and broadcasts the change
                     local eepromApi = requireModule("tasks/msp/api/eeprom_write.lua")
                     if eepromApi and type(eepromApi.buildWritePayload) == "function" then
                       mState.queue:add({
                          command = eepromApi.writeCommand,
                          payload = eepromApi.buildWritePayload({}),
                          simulatorResponse = {},
                          isWrite = true,
                       })
                     end
                  end
                end

                -- Close after selection
                w.built = false
                w.renderKey = nil
                if lcd and type(lcd.exitFullScreen) == "function" then
                   lcd.exitFullScreen()
                end
              end
            }
          end
        end
      end
      return options
    end
  }

  return list
end

--- Draw the menu.
--
-- `entries` is the list to draw; omitted, the menu draws its own, which is what the runtime
-- asks for. Taking the list as an argument is the point of the split: the same drawing code
-- can serve a list assembled somewhere else.
function M.build(children, widget, entries)
  entries = entries or M.entries(widget)
  local dW = widget.zone.w
  local dH = widget.zone.h
  local dX = 0
  local dY = 0
  
  local t = translator(widget)

  local bg_color = COLOR_THEME_PRIMARY3 or BLACK
  if bg_color == BLACK and lcd and type(lcd.RGB) == "function" then
     bg_color = lcd.RGB(40, 40, 40)
  end
  local accent_color = COLOR_THEME_SECONDARY1 or WHITE
  local btn_color = COLOR_THEME_PRIMARY1 or DARKGREY
  
  -- 1. Full Background
  children[#children+1] = {
    type = "rectangle", x=dX, y=dY, w=dW, h=dH, color=bg_color, filled=true
  }

  -- Layout Profile Definition
  -- TX16S MK3 is 800x480 (dH ~480)
  -- Standard TX16S is 480x272 (dH ~272)
  local isLarge = dH > 350
  
  local headerH, titleFont, fontH, closeSize, contentGap, titleGap, btnH, gapY, paddingX
  local headTextOffY, closeTextOffY, btnTextOffY

  if isLarge then
    -- Layout for TX16S MK3 (Large High-Res)
    headerH = 60
    titleFont = MIDSIZE
    fontH = 24
    closeSize = 44
    contentGap = 20
    titleGap = fontH + 30
    btnH = 50
    gapY = 10
    paddingX = 15
    headTextOffY = -6
    closeTextOffY = -8
    btnTextOffY = -8
  else
    -- Layout for standard TX16S (480x272)
    headerH = 22
    titleFont = SMLSIZE
    fontH = 12
    closeSize = 20
    contentGap = 5
    titleGap = fontH + 10
    btnH = 28
    gapY = 8
    paddingX = 5
    headTextOffY = -2
    closeTextOffY = -4
    btnTextOffY = -4
  end

  -- 2. Header
  children[#children+1] = {
    type = "rectangle", x=dX, y=dY, w=dW, h=headerH, color=btn_color, filled=true
  }
  
  children[#children+1] = {
    type = "label", x=dX + paddingX, y=dY + math.floor((headerH - fontH)/2) + headTextOffY, w=dW-60, 
    text=t("widgets.dashboard.quick_settings", "QUICK SETTINGS"), color=WHITE, align=LEFT, font=titleFont
  }
  
  -- 3. Close Button (X)
  local cx = dX + dW - closeSize - (isLarge and 8 or 1)
  local cy = dY + math.floor((headerH - closeSize)/2)
  
  children[#children+1] = {
    type = "button", x=cx, y=cy, w=closeSize, h=closeSize, color=COLOR_THEME_SECONDARY1 or RED,
    press = function()
      widget.built = false
      widget.renderKey = nil
      if lcd and type(lcd.exitFullScreen) == "function" then
         lcd.exitFullScreen()
      end
    end
  }
  
  children[#children+1] = {
    type = "label", x=cx, y=cy + math.floor((closeSize - fontH)/2) + closeTextOffY, w=closeSize, text="X", color=WHITE, align=CENTER, font=titleFont
  }
  
  -- 4. Content Area
  local contentY = dY + headerH + contentGap
  local entryW = math.floor(dW - paddingX * 2)

  for _, entry in ipairs(entries) do
    if isEntryVisible(entry, widget) then
      if entry.kind == "choice" then
        -- 4b. A title over a grid of options.
        contentY = contentY + titleGap - gapY

        children[#children+1] = {
          type = "label", x=dX + paddingX, y=contentY, w=dW-(paddingX*2),
          text=entry.title, color=WHITE, align=LEFT, font=titleFont
        }

        local listY = contentY + titleGap

        local options = entry.options
        if type(options) == "function" then options = options(widget) end
        options = options or {}

        -- Every action row above the grid pushes it down, and an option whose button would
        -- cross the bottom edge is not drawn. Three columns on a wide zone keep six options to
        -- two rows, so they still fit below a longer list of actions.
        local cols = 2
        if dW < 200 then cols = 1 end
        if #options > 4 and dW >= 400 then cols = 3 end
        local btnW = math.floor((dW - paddingX*(cols+1)) / cols)

        for i, option in ipairs(options) do
           local row = math.floor((i-1)/cols)
           local col = (i-1)%cols
           local bx = dX + paddingX + col*(btnW+paddingX)
           local by = listY + row*(btnH+gapY)

           if by + btnH > dY + dH then break end

           local isCurrent = option.current == true
           local bColor = isCurrent and accent_color or btn_color
           local tColor = isCurrent and BLACK or WHITE

           -- Button (Interactive layer)
           children[#children+1] = {
             type = "button", x=bx, y=by, w=btnW, h=btnH, color=bColor, press = option.press
           }

           -- Label (visual only)
           local textY = by + math.floor((btnH - fontH)/2) + btnTextOffY
           children[#children+1] = {
             type = "label", x=bx, y=textY, w=btnW, text=option.label, color=tColor, align=CENTER, font=titleFont
           }
        end

        -- The next row starts below the whole grid, the way an action row leaves room for itself.
        contentY = listY + math.ceil(#options / cols) * (btnH + gapY)
      else
        -- 4a. A single button.
        children[#children+1] = {
          type = "button", x=dX + paddingX, y=contentY, w=entryW, h=btnH, color=btn_color,
          press = entry.press
        }
        children[#children+1] = {
          type = "label", x=dX + paddingX, y=contentY + math.floor((btnH - fontH)/2) + btnTextOffY, w=entryW,
          text=entry.title, color=WHITE, align=CENTER, font=titleFont
        }
        contentY = contentY + btnH + gapY
      end
    end
  end
end

return M
