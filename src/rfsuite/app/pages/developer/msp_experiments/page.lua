--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]]--

-- MSP Experiments Page (EdgeTX)
-- Refactored to match msp_speed page structure and UI/UX

local M = {}

local function loadModule(path)
    local fullPath = "/SCRIPTS/TOOLS/rfsuite-core/" .. path
    local chunk = assert(loadScript(fullPath, "t"))
    return chunk()
end

local Common = nil
local Controls = nil
local t = nil

local ui = {
    loaded = false,
    rebuild = nil,
    lastAutoRefreshAt = 0,
    expBytes = 16,
    fieldMap = {},
    int8_dirty = false,
    uint8_dirty = false,
    enableWakeup = false,
    apidata = nil,
}

local function uint8_to_int8(value)
    if type(value) ~= "number" then return 0 end
    if value > 127 then return value - 256 else return value end
end

local function int8_to_uint8(value)
    return (value or 0) & 0xFF
end

local function buildFieldMap(fields)
    ui.fieldMap = {}
    for _, field in ipairs(fields or {}) do
        if not ui.fieldMap[field.label] then ui.fieldMap[field.label] = {} end
        table.insert(ui.fieldMap[field.label], field)
    end
end

local function safeFieldValue(field)
    if not field or field.value == nil then return 0 end
    return field.value
end

local function update_int8(fields)
    if not ui.uint8_dirty then return end
    ui.uint8_dirty = false
    for _, field in ipairs(fields or {}) do
        if field.isINT8 then
            for _, match in ipairs(ui.fieldMap[field.label] or {}) do
                if match.isUINT8 then
                    field.value = uint8_to_int8(safeFieldValue(match))
                end
            end
        end
    end
end

local function update_uint8(fields)
    if not ui.int8_dirty then return end
    ui.int8_dirty = false
    for _, field in ipairs(fields or {}) do
        if field.isUINT8 then
            for _, match in ipairs(ui.fieldMap[field.label] or {}) do
                if match.isINT8 then
                    field.value = int8_to_uint8(safeFieldValue(match))
                end
            end
        end
    end
end

local function generateMSPAPI(numLabels)
    if numLabels > 16 then numLabels = 16 end
    local apidata = {api = {'EXPERIMENTAL'}, formdata = {labels = {}, fields = {}}}
    for i = 1, numLabels do
        table.insert(apidata.formdata.labels, {t = tostring(i), inline_size = 17, label = i})
        table.insert(apidata.formdata.fields, {t = "UINT8", isUINT8 = true, label = i, inline = 2, mspapi = 1, apikey = "exp_uint" .. i, min = 0, max = 255, onChange = function() ui.uint8_dirty = true end})
        table.insert(apidata.formdata.fields, {t = "INT8", isINT8 = true, label = i, inline = 1, mspapi = 1, apikey = "exp_int" .. i, min = -128, max = 127, onChange = function() ui.int8_dirty = true end})
    end
    return apidata
end

local function getExpBytes()
    -- Default to 16 if not set
    if _G and _G.rfsuite and _G.rfsuite.preferences and _G.rfsuite.preferences.developer and _G.rfsuite.preferences.developer.mspexpbytes then
        return _G.rfsuite.preferences.developer.mspexpbytes
    end
    return 16
end

local function ensureDeps()
    if not Common then
        Common = loadModule("app/pages/settings/common.lua")
    end
    if not Controls then
        Controls = loadModule("ui/controls.lua")
    end
    if not t then
        t = Common.pageT("developer_msp_experiments")
    end
end

local function periodicSync()
    update_int8(ui.apidata.formdata.fields)
    update_uint8(ui.apidata.formdata.fields)
end

local function postLoad()
    ui.fieldMap = {}
    ui.int8_dirty = false
    ui.uint8_dirty = true
    ui.enableWakeup = false
    local rx = _G and _G.rfsuite and _G.rfsuite.tasks and _G.rfsuite.tasks.msp and _G.rfsuite.tasks.msp.api and _G.rfsuite.tasks.msp.api.apidata and _G.rfsuite.tasks.msp.api.apidata.receivedBytesCount
    if rx and rx['EXPERIMENTAL'] == 0 then
        if _G.rfsuite and _G.rfsuite.app and _G.rfsuite.app.triggers then
            _G.rfsuite.app.triggers.closeProgressLoader = true
        end
        if _G.rfsuite and _G.rfsuite.app and _G.rfsuite.app.ui then
            _G.rfsuite.app.ui.disableAllFields()
            _G.rfsuite.app.ui.disableAllNavigationFields()
            _G.rfsuite.app.ui.enableNavigationField('menu')
        end
        return
    end
    if rx and getExpBytes() ~= rx['EXPERIMENTAL'] then
        if _G.rfsuite and _G.rfsuite.preferences and _G.rfsuite.preferences.developer then
            _G.rfsuite.preferences.developer.mspexpbytes = rx['EXPERIMENTAL']
        end
        if _G.rfsuite and _G.rfsuite.app and _G.rfsuite.app.triggers then
            _G.rfsuite.app.triggers.reloadFull = true
        end
    end
    buildFieldMap(ui.apidata.formdata.fields)
    ui.uint8_dirty = true
    ui.enableWakeup = true
    if _G.rfsuite and _G.rfsuite.app and _G.rfsuite.app.triggers then
        _G.rfsuite.app.triggers.closeProgressLoader = true
    end
end

local function wakeup()
    if not ui.enableWakeup or not ui.apidata or not ui.apidata.formdata or not ui.apidata.formdata.fields then return end
    periodicSync()
end

local function preUnload()
    ui.enableWakeup = false
end

local function requestRebuild()
    if type(ui.rebuild) == "function" then
        ui.rebuild()
    end
end

function M.getHeaderActions()
    ensureDeps()
    return { save = true, reload = true, help = true, menu = true }
end

function M.allowMemAutoRefresh()
    return true
end

function M.onReload()
    ensureDeps()
    ui.expBytes = getExpBytes()
    ui.apidata = generateMSPAPI(ui.expBytes)
    buildFieldMap(ui.apidata.formdata.fields)
    ui.int8_dirty = false
    ui.uint8_dirty = true
    ui.enableWakeup = true
    ui.loaded = true
    ui.lastAutoRefreshAt = 0
end

function M.onClose()
    ui.loaded = false
    ui.rebuild = nil
    ui.fieldMap = {}
    ui.int8_dirty = false
    ui.uint8_dirty = false
    ui.enableWakeup = false
    ui.apidata = nil
    Common = nil
    Controls = nil
    t = nil
end

function M.wakeup()
    ensureDeps()
    wakeup()
end


function M.build(ctx)
    ensureDeps()
    if not ui.loaded then
        M.onReload()
    end
    ui.rebuild = ctx.requestRebuild

    local children = ctx.children
    local x, y, w = ctx.x, ctx.y, ctx.w
    local i18n = ctx.i18n

    Controls.appendStaticSectionHeader(children, x, y, w, t(i18n, "section_experiments", "MSP Experiments"))

    local cursorY = y + Controls.STATIC_SECTION_H
    local rowH = 44
    local buttonW = 130
    local buttonH = 36
    local comboW = 130
    local comboH = 36
    local comboYOffset = -2
    local rightPad = 10
    local gap = 8
    local buttonX = x + w - buttonW - rightPad
    local comboX = buttonX - gap - comboW
    local labelW = comboX - x - 8
    local buttonY = cursorY + math.floor((rowH - buttonH) / 2) + comboYOffset
    local comboY = cursorY + math.floor((rowH - comboH) / 2) + comboYOffset

    -- Label for experiment bytes
    children[#children + 1] = {
        type = "label",
        x = x,
        y = cursorY + 10,
        w = labelW,
        text = t(i18n, "exp_bytes", "Experiment Bytes"),
        color = COLOR_THEME_PRIMARY1,
        font = SMLSIZE,
    }

    -- Choice control for number of experiment bytes (8, 12, 16)
    local EXP_BYTE_OPTIONS = {8, 12, 16}
    local EXP_BYTE_LABELS = {"8", "12", "16"}
    local function expByteIndexForValue(val)
        for i, v in ipairs(EXP_BYTE_OPTIONS) do if v == val then return i end end
        return 3 -- default to 16
    end
    children[#children + 1] = {
        type = "choice",
        x = comboX,
        y = comboY,
        w = comboW,
        h = comboH,
        title = tostring(t(i18n, "exp_bytes", "Experiment Bytes")),
        values = EXP_BYTE_LABELS,
        get = function()
            return expByteIndexForValue(ui.expBytes)
        end,
        set = function(nextIndex)
            local idx = tonumber(nextIndex) or expByteIndexForValue(ui.expBytes)
            if idx < 1 then idx = 1 end
            if idx > #EXP_BYTE_OPTIONS then idx = #EXP_BYTE_OPTIONS end
            local nextVal = EXP_BYTE_OPTIONS[idx]
            if ui.expBytes ~= nextVal then
                ui.expBytes = nextVal
            end
        end
    }

    -- Apply button to regenerate fields
    children[#children + 1] = {
        type = "button",
        x = buttonX,
        y = buttonY,
        w = buttonW,
        h = buttonH,
        text = t(i18n, "apply", "Apply"),
        press = function()
            M.onReload()
            requestRebuild()
        end,
    }

    children[#children + 1] = {
        type = "rectangle",
        x = x,
        y = cursorY + rowH,
        w = w,
        h = 1,
        color = GREY_DEFAULT,
        filled = true,
    }
    cursorY = cursorY + rowH + 1

    -- Table header
    local tableRowH = 36
    local colLabelW = math.floor(w * 0.45)
    local colUint8W = math.floor(w * 0.25)
    local colInt8W = w - colLabelW - colUint8W - 2
    local colLabelX = x
    local colUint8X = x + colLabelW + 1
    local colInt8X = colUint8X + colUint8W + 1

    children[#children + 1] = {
        type = "label",
        x = colLabelX,
        y = cursorY,
        w = colLabelW,
        text = t(i18n, "field_label", "Label"),
        color = COLOR_THEME_PRIMARY1,
        font = SMLSIZE,
    }
    children[#children + 1] = {
        type = "label",
        x = colUint8X,
        y = cursorY,
        w = colUint8W,
        text = t(i18n, "field_uint8", "UINT8 (0-255)"),
        color = COLOR_THEME_PRIMARY1,
        font = SMLSIZE,
    }
    children[#children + 1] = {
        type = "label",
        x = colInt8X,
        y = cursorY,
        w = colInt8W,
        text = t(i18n, "field_int8", "INT8 (-127-127)"),
        color = COLOR_THEME_PRIMARY1,
        font = SMLSIZE,
    }
    cursorY = cursorY + tableRowH


    -- Render experiment fields as editable table rows using lvgl.numberedit
    for i = 1, ui.expBytes do
        local label = t(i18n, "field_" .. tostring(i), tostring(i))
        -- Find matching UINT8 and INT8 fields for this label
        local uint8Field, int8Field
        for _, field in ipairs(ui.apidata.formdata.fields) do
            if field.label == i then
                if field.isUINT8 then uint8Field = field end
                if field.isINT8 then int8Field = field end
            end
        end
        -- Label column
        children[#children + 1] = {
            type = "label",
            x = colLabelX,
            y = cursorY,
            w = colLabelW,
            text = label,
            color = COLOR_THEME_PRIMARY1,
            font = SMLSIZE,
        }
        -- UINT8 numberedit field
        Controls.appendNumberField(children, colUint8X, cursorY, colUint8W, nil, {
            min = 0,
            max = 255,
            get = function() return uint8Field and uint8Field.value or 0 end,
            set = function(val)
                if uint8Field then
                    local v = tonumber(val) or 0
                    if v < 0 then v = 0 end
                    if v > 255 then v = 255 end
                    uint8Field.value = v
                    ui.uint8_dirty = true
                end
            end,
            enabled = true,
        })
        -- INT8 numberedit field
        Controls.appendNumberField(children, colInt8X, cursorY, colInt8W, nil, {
            min = -127,
            max = 127,
            get = function() return int8Field and int8Field.value or 0 end,
            set = function(val)
                if int8Field then
                    local v = tonumber(val) or 0
                    if v < -127 then v = -127 end
                    if v > 127 then v = 127 end
                    int8Field.value = v
                    ui.int8_dirty = true
                end
            end,
            enabled = true,
        })
        cursorY = cursorY + tableRowH
    end

    children[#children + 1] = {
        type = "rectangle",
        x = x,
        y = cursorY,
        w = w,
        h = 1,
        color = GREY_DEFAULT,
        filled = true,
    }
end

return M
