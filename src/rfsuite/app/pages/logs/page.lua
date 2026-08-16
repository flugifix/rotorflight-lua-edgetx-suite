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
local Controls = nil
local t = nil

local state = {
  selectedFile = nil,
  selectedFilePath = nil,
  selectedModel = nil,
  logsList = {},
  summary = nil,
  requestRebuild = nil
}

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not t then t = Common and Common.pageT("logs") or nil end
end

local function pageText(i18n, key)
  if t then
    local translated = t(i18n, key)
    if translated ~= nil and translated ~= "" and translated ~= key then
      return translated
    end
  end
  return key
end

local function safeCollectEntries(listBasePath)
  local entries = {}
  if type(dir) == "function" then
    local iterator = dir(listBasePath)
    if type(iterator) == "function" then
      for name in iterator do
        if name and name ~= "." and name ~= ".." and name ~= "" then
          entries[#entries + 1] = name
        end
      end
      return entries
    end
  end

  if system and system.listFiles then
    local ok, res = pcall(system.listFiles, listBasePath)
    if ok and type(res) == "table" then
      for i = 1, #res do
        local name = res[i]
        if name and name ~= "." and name ~= ".." and name ~= "" then
          entries[#entries + 1] = name
        end
      end
      return entries
    end
  end

  return entries
end

local function scanLogFiles()
  local found = {}
  local searchPaths = {
    "/LOGS/rfsuite/telemetry",
    "/LOGS/rfsuite",
    "/LOGS"
  }

  for s = 1, #searchPaths do
    local basePath = searchPaths[s]
    local topEntries = safeCollectEntries(basePath)
    for i = 1, #topEntries do
      local entry = topEntries[i]
      if string.match(entry, "%.csv$") then
        local fullPath = basePath .. "/" .. entry
        local date, time = string.match(entry, "(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)")
        found[#found + 1] = {
          file = entry,
          path = fullPath,
          model = "Default",
          date = date or "Unknown",
          time = time and string.gsub(time, "%-", ":") or "",
          sortKey = (date or "") .. "_" .. (time or "") .. "_" .. entry
        }
      elseif not string.match(entry, "%.%w+$") then
        -- Subdirectory (e.g. Model name)
        local modelDir = basePath .. "/" .. entry
        local subEntries = safeCollectEntries(modelDir)
        for j = 1, #subEntries do
          local subFile = subEntries[j]
          if string.match(subFile, "%.csv$") then
            local fullPath = modelDir .. "/" .. subFile
            local date, time = string.match(subFile, "(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)")
            found[#found + 1] = {
              file = subFile,
              path = fullPath,
              model = entry,
              date = date or "Unknown",
              time = time and string.gsub(time, "%-", ":") or "",
              sortKey = (date or "") .. "_" .. (time or "") .. "_" .. subFile
            }
          end
        end
      end
    end
  end

  table.sort(found, function(a, b) return a.sortKey > b.sortKey end)
  state.logsList = found
  return found
end

local function parseTelemetryCsv(filePath)
  local f = io.open(filePath, "r")
  if not f then return nil end

  local content = ""
  while true do
    local chunk = io.read(f, 4096)
    if not chunk or chunk == "" then break end
    content = content .. chunk
    if #content > 500000 then break end
  end
  io.close(f)

  if content == "" then return nil end

  local lines = {}
  local header = nil
  for line in string.gmatch(content, "[^\r\n]+") do
    if line and line ~= "" then
      if not header and string.match(line, "%a") then
        header = line
      else
        lines[#lines + 1] = line
      end
    end
  end

  if #lines == 0 then return nil end

  -- Identify columns
  local vIdx, cIdx, rIdx, tIdx, thrIdx = 1, 2, 3, 4, 5
  if header then
    local lowerHeader = string.lower(header)
    local colIdx = 1
    for col in string.gmatch(lowerHeader, "([^,]+)") do
      local trimmed = string.gsub(col, "^%s+", "")
      trimmed = string.gsub(trimmed, "%s+$", "")
      if string.find(trimmed, "volt") or string.find(trimmed, "vfas") or string.find(trimmed, "bat") then
        vIdx = colIdx
      elseif string.find(trimmed, "curr") or string.find(trimmed, "amp") or string.find(trimmed, "strom") then
        cIdx = colIdx
      elseif string.find(trimmed, "rpm") or string.find(trimmed, "head") or string.find(trimmed, "drehzahl") then
        rIdx = colIdx
      elseif string.find(trimmed, "temp") or string.find(trimmed, "esc_t") or string.find(trimmed, "grad") then
        tIdx = colIdx
      elseif string.find(trimmed, "thr") or string.find(trimmed, "gas") then
        thrIdx = colIdx
      end
      colIdx = colIdx + 1
    end
  end

  local function splitRow(rowStr)
    local cols = {}
    for item in string.gmatch(rowStr .. ",", "([^,]*),") do
      cols[#cols + 1] = tonumber(item) or 0
    end
    return cols
  end

  local voltages = {}
  local currents = {}
  local rpms = {}
  local temps = {}
  local throttles = {}

  for i = 1, #lines do
    local row = splitRow(lines[i])
    if #row >= 2 then
      voltages[#voltages + 1] = row[vIdx] or 0
      currents[#currents + 1] = row[cIdx] or 0
      rpms[#rpms + 1] = row[rIdx] or 0
      temps[#temps + 1] = row[tIdx] or 0
      throttles[#throttles + 1] = row[thrIdx] or 0
    end
  end

  local sampleCount = #voltages
  if sampleCount == 0 then return nil end

  -- Compute stats
  local vStart = voltages[1] or 0
  local vEnd = voltages[sampleCount] or vStart
  local vMin = vStart
  local vMax = vStart
  for i = 1, sampleCount do
    local v = voltages[i]
    if v > 0 then
      if v < vMin or vMin == 0 then vMin = v end
      if v > vMax then vMax = v end
    end
  end

  local cPeak = 0
  local cSum = 0
  for i = 1, sampleCount do
    local c = currents[i]
    if c > cPeak then cPeak = c end
    cSum = cSum + c
  end
  local cAvg = sampleCount > 0 and (cSum / sampleCount) or 0
  local mah = (cSum / 3600) * 1000

  local rMax = 0
  local rMin = 0
  local rSum = 0
  local rActiveCount = 0
  for i = 1, sampleCount do
    local r = rpms[i]
    if r > rMax then rMax = r end
    if r > 500 then
      if rMin == 0 or r < rMin then rMin = r end
      rSum = rSum + r
      rActiveCount = rActiveCount + 1
    end
  end
  local rAvg = rActiveCount > 0 and (rSum / rActiveCount) or 0

  local tStart = temps[1] or 0
  local tMax = tStart
  for i = 1, sampleCount do
    local tmp = temps[i]
    if tmp > tMax then tMax = tmp end
  end

  local thrMax = 0
  for i = 1, sampleCount do
    local thr = throttles[i]
    if thr > thrMax then thrMax = thr end
  end

  local durationSec = sampleCount
  local durationMin = math.floor(durationSec / 60)
  local durationRemSec = durationSec % 60
  local durationStr = string.format("%02d:%02d min", durationMin, durationRemSec)

  return {
    sampleCount = sampleCount,
    durationStr = durationStr,
    vStart = vStart,
    vMin = vMin,
    vMax = vMax,
    vEnd = vEnd,
    vSag = (vStart > vMin) and (vStart - vMin) or 0,
    cPeak = cPeak,
    cAvg = cAvg,
    mah = mah,
    rMax = rMax,
    rMin = rMin,
    rAvg = rAvg,
    tStart = tStart,
    tMax = tMax,
    thrMax = thrMax
  }
end

function M.getHeaderActions()
  return {
    reload = true,
    save = false,
    help = true
  }
end

function M.onHelp(ctx)
  local help = loadModule("app/pages/logs/help.lua")
  if type(help) == "function" then
    return help(ctx)
  end
  return { title = "Logs", message = "" }
end

function M.onReload(ctx)
  scanLogFiles()
  state.selectedFile = nil
  state.selectedFilePath = nil
  state.summary = nil
  if type(ctx) == "table" and type(ctx.requestRebuild) == "function" then
    ctx.requestRebuild()
  end
  return true
end

function M.onBack(ctx)
  if state.selectedFile ~= nil then
    state.selectedFile = nil
    state.selectedFilePath = nil
    state.selectedModel = nil
    state.summary = nil
    return true
  end
  return false
end

function M.build(ctx)
  ensureDeps()
  state.requestRebuild = ctx and ctx.requestRebuild or nil

  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local h = ctx.h or 200
  local i18n = ctx.i18n

  local cursorY = y

  -- If a log file is selected, show summary dashboard
  if state.selectedFile and state.selectedFilePath then
    local summary = state.summary
    if not summary then
      summary = parseTelemetryCsv(state.selectedFilePath)
      state.summary = summary
    end

    local titleText = string.format("%s - %s", state.selectedModel or "Log", state.selectedFile)
    if Controls and type(Controls.appendStaticSectionHeader) == "function" then
      Controls.appendStaticSectionHeader(children, x, cursorY, w, titleText)
      cursorY = cursorY + (Controls.STATIC_SECTION_H or 50)
    end

    if not summary then
      children[#children + 1] = {
        type = "label",
        x = x + 10,
        y = cursorY + 20,
        w = w - 20,
        text = "Failed to parse log file",
        color = COLOR_THEME_WARNING,
        align = CENTER
      }
      return
    end

    local rowH = 40
    local labelColW = 120

    -- 1) Flight Duration Row
    children[#children + 1] = {
      type = "label",
      x = x + 12,
      y = cursorY + 10,
      w = labelColW,
      text = pageText(i18n, "flight_duration"),
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }
    children[#children + 1] = {
      type = "label",
      x = x + labelColW + 15,
      y = cursorY + 10,
      w = w - labelColW - 27,
      text = string.format("%s   (%d %s)", summary.durationStr, summary.sampleCount, pageText(i18n, "samples")),
      color = COLOR_WHITE,
      font = SMLSIZE
    }
    cursorY = cursorY + rowH
    children[#children + 1] = {
      type = "rectangle",
      x = x,
      y = cursorY - 1,
      w = w,
      h = 1,
      color = GREY_DEFAULT,
      filled = true
    }

    -- 2) Voltage Row
    children[#children + 1] = {
      type = "label",
      x = x + 12,
      y = cursorY + 10,
      w = labelColW,
      text = pageText(i18n, "voltage_title"),
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }
    children[#children + 1] = {
      type = "label",
      x = x + labelColW + 15,
      y = cursorY + 10,
      w = w - labelColW - 27,
      text = string.format("%s: %.2fV   |   %s: %.2fV (-%.2fV)   |   %s: %.2fV",
        pageText(i18n, "start"), summary.vStart,
        pageText(i18n, "min"), summary.vMin, summary.vSag,
        pageText(i18n, "end_val"), summary.vEnd),
      color = COLOR_WHITE,
      font = SMLSIZE
    }
    cursorY = cursorY + rowH
    children[#children + 1] = {
      type = "rectangle",
      x = x,
      y = cursorY - 1,
      w = w,
      h = 1,
      color = GREY_DEFAULT,
      filled = true
    }

    -- 3) Current Row
    children[#children + 1] = {
      type = "label",
      x = x + 12,
      y = cursorY + 10,
      w = labelColW,
      text = pageText(i18n, "current_title"),
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }
    children[#children + 1] = {
      type = "label",
      x = x + labelColW + 15,
      y = cursorY + 10,
      w = w - labelColW - 27,
      text = string.format("%s: %.1f A   |   %s: %.1f A   |   %s: ~%d mAh",
        pageText(i18n, "peak"), summary.cPeak,
        pageText(i18n, "avg"), summary.cAvg,
        pageText(i18n, "consumption_title"), math.floor(summary.mah)),
      color = COLOR_WHITE,
      font = SMLSIZE
    }
    cursorY = cursorY + rowH
    children[#children + 1] = {
      type = "rectangle",
      x = x,
      y = cursorY - 1,
      w = w,
      h = 1,
      color = GREY_DEFAULT,
      filled = true
    }

    -- 4) Headspeed RPM Row
    children[#children + 1] = {
      type = "label",
      x = x + 12,
      y = cursorY + 10,
      w = labelColW,
      text = pageText(i18n, "rpm_title"),
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }
    children[#children + 1] = {
      type = "label",
      x = x + labelColW + 15,
      y = cursorY + 10,
      w = w - labelColW - 27,
      text = string.format("%s: %d rpm   |   %s: %d rpm   |   %s: %d rpm",
        pageText(i18n, "max"), math.floor(summary.rMax),
        pageText(i18n, "avg"), math.floor(summary.rAvg),
        pageText(i18n, "min"), math.floor(summary.rMin)),
      color = COLOR_WHITE,
      font = SMLSIZE
    }
    cursorY = cursorY + rowH
    children[#children + 1] = {
      type = "rectangle",
      x = x,
      y = cursorY - 1,
      w = w,
      h = 1,
      color = GREY_DEFAULT,
      filled = true
    }

    -- 5) ESC Temp Row
    children[#children + 1] = {
      type = "label",
      x = x + 12,
      y = cursorY + 10,
      w = labelColW,
      text = pageText(i18n, "temp_title"),
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }
    children[#children + 1] = {
      type = "label",
      x = x + labelColW + 15,
      y = cursorY + 10,
      w = w - labelColW - 27,
      text = string.format("%s: %d °C   |   %s: %d °C   |   %s %s: %d %%",
        pageText(i18n, "max"), math.floor(summary.tMax),
        pageText(i18n, "start"), math.floor(summary.tStart),
        pageText(i18n, "max"), pageText(i18n, "throttle_title"), math.floor(summary.thrMax)),
      color = COLOR_WHITE,
      font = SMLSIZE
    }
    cursorY = cursorY + rowH
    children[#children + 1] = {
      type = "rectangle",
      x = x,
      y = cursorY - 1,
      w = w,
      h = 1,
      color = GREY_DEFAULT,
      filled = true
    }

    return
  end

  -- List Mode: show available telemetry logs
  if #state.logsList == 0 then
    scanLogFiles()
  end

  if Controls and type(Controls.appendStaticSectionHeader) == "function" then
    Controls.appendStaticSectionHeader(children, x, cursorY, w, pageText(i18n, "select_log"))
    cursorY = cursorY + (Controls.STATIC_SECTION_H or 50)
  end

  if #state.logsList == 0 then
    children[#children + 1] = {
      type = "label",
      x = x + 10,
      y = cursorY + 25,
      w = w - 20,
      text = pageText(i18n, "no_logs_found"),
      color = GREY_DEFAULT,
      align = CENTER
    }
    cursorY = cursorY + 60

    local btnW = 200
    local btnH = 36
    local btnX = x + math.floor((w - btnW) / 2)
    children[#children + 1] = {
      type = "button",
      x = btnX,
      y = cursorY,
      w = btnW,
      h = btnH,
      text = pageText(i18n, "refresh"),
      press = function()
        scanLogFiles()
        if state.requestRebuild then
          state.requestRebuild()
        end
      end
    }
    return
  end

  -- Render log files list
  local rowH = 44
  for i = 1, #state.logsList do
    local item = state.logsList[i]
    local itemY = cursorY

    -- Date and Time with ample width
    children[#children + 1] = {
      type = "label",
      x = x + 10,
      y = itemY + 11,
      w = 175,
      text = string.format("%s  %s", item.date, item.time),
      color = COLOR_THEME_PRIMARY1,
      font = SMLSIZE
    }

    -- Model name and File name
    children[#children + 1] = {
      type = "label",
      x = x + 190,
      y = itemY + 11,
      w = w - 305,
      text = string.format("[%s] %s", item.model, item.file),
      color = GREY_DEFAULT,
      font = SMLSIZE
    }

    -- View button (wider to avoid cutting off "Anzeigen")
    local btnW = 100
    local btnH = 30
    local btnX = x + w - btnW - 10
    children[#children + 1] = {
      type = "button",
      x = btnX,
      y = itemY + 7,
      w = btnW,
      h = btnH,
      text = pageText(i18n, "btn_view"),
      press = function()
        state.selectedFile = item.file
        state.selectedFilePath = item.path
        state.selectedModel = item.model
        state.summary = nil
        if state.requestRebuild then
          state.requestRebuild()
        end
      end
    }

    children[#children + 1] = {
      type = "rectangle",
      x = x,
      y = itemY + rowH - 1,
      w = w,
      h = 1,
      color = GREY_DEFAULT,
      filled = true
    }

    cursorY = cursorY + rowH
  end
end

function M.onClose()
  state.selectedFile = nil
  state.selectedFilePath = nil
  state.selectedModel = nil
  state.summary = nil
  state.logsList = {}
end

return M
