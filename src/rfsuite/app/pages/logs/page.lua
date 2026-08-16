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
local LoadingOverlay = nil
local t = nil

local state = {
  selectedFile = nil,
  selectedFilePath = nil,
  selectedModel = nil,
  logsList = {},
  summary = nil,
  loading = false,
  requestRebuild = nil
}

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not Controls then Controls = loadModule("ui/controls.lua") end
  if not LoadingOverlay then LoadingOverlay = loadModule("ui/loading_overlay.lua") end
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

local function extractFileInfo(filename, fullPath, parentFolder)
  local date = string.match(filename, "(%d%d%d%d%-%d%d%-%d%d)")
  local time = nil

  -- Pattern: YYYY-MM-DD-HHMMSS or YYYY-MM-DD_HHMMSS
  local h1, m1, s1 = string.match(filename, "%d%d%d%d%-%d%d%-%d%d[_-]?(%d%d)(%d%d)(%d%d)")
  if h1 and m1 and s1 then
    time = h1 .. ":" .. m1 .. ":" .. s1
  else
    -- Pattern: YYYY-MM-DD_HH-MM-SS or YYYY-MM-DD-HH-MM-SS
    local h2, m2, s2 = string.match(filename, "%d%d%d%d%-%d%d%-%d%d[_-](%d%d)%-(%d%d)%-(%d%d)")
    if h2 and m2 and s2 then
      time = h2 .. ":" .. m2 .. ":" .. s2
    end
  end

  local model = string.match(filename, "^(.-)%-%d%d%d%d")
  if not model or model == "" then
    model = (parentFolder and parentFolder ~= "" and parentFolder ~= "telemetry" and parentFolder ~= "rfsuite" and parentFolder ~= "LOGS") and parentFolder or "Default"
  end

  -- Fallback: peek first lines if date/time not in filename
  if not date or not time then
    local f = io.open(fullPath, "r")
    if f then
      local firstChunk = io.read(f, 512)
      io.close(f)
      if firstChunk then
        local l1, l2 = string.match(firstChunk, "([^\r\n]+)[\r\n]+([^\r\n]+)")
        if l2 then
          local d, tm = string.match(l2, "^(.-),(.-),")
          if d and string.match(d, "^%d%d%d%d%-%d%d%-%d%d$") then
            date = d
          end
          if tm then
            local tClean = string.match(tm, "^(%d%d:%d%d:%d%d)")
            if tClean then time = tClean end
          end
        end
      end
    end
  end

  date = date or "Unknown"
  time = time or ""
  local sortKey = date .. "_" .. string.gsub(time, ":", "") .. "_" .. filename

  return {
    file = filename,
    path = fullPath,
    model = model,
    date = date,
    time = time,
    sortKey = sortKey
  }
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
        found[#found + 1] = extractFileInfo(entry, fullPath, "")
      elseif not string.match(entry, "%.%w+$") then
        -- Subdirectory (e.g. Model name)
        local modelDir = basePath .. "/" .. entry
        local subEntries = safeCollectEntries(modelDir)
        for j = 1, #subEntries do
          local subFile = subEntries[j]
          if string.match(subFile, "%.csv$") then
            local fullPath = modelDir .. "/" .. subFile
            found[#found + 1] = extractFileInfo(subFile, fullPath, entry)
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

  local headerLine = nil
  local dateCol, timeCol = nil, nil
  local vbatCol, currCol, capaCol = nil, nil, nil
  local hspdCol, esctCol, thrCol, armCol = nil, nil, nil

  local function parseHeader(hStr)
    local colIdx = 1
    for col in string.gmatch(hStr .. ",", "([^,]*),") do
      local trimmed = string.lower(string.gsub(string.gsub(col, "^%s+", ""), "%s+$", ""))
      if trimmed == "date" then
        dateCol = colIdx
      elseif trimmed == "time" then
        timeCol = colIdx
      elseif trimmed == "vbat(v)" or trimmed == "vbat" or trimmed == "vfas" or trimmed == "voltage" then
        vbatCol = colIdx
      elseif trimmed == "curr(a)" or trimmed == "curr" or trimmed == "current" or trimmed == "amp" then
        currCol = colIdx
      elseif trimmed == "capa(mah)" or trimmed == "capa" or trimmed == "capacity" or trimmed == "smcp(mah)" then
        capaCol = colIdx
      elseif trimmed == "hspd(rpm)" or trimmed == "hspd" or trimmed == "rpm" or trimmed == "headspeed" then
        hspdCol = colIdx
      elseif string.find(trimmed, "esct") or string.find(trimmed, "esc_t") or string.find(trimmed, "temp_esc") or trimmed == "temp" then
        esctCol = colIdx
      elseif trimmed == "thr(%)" or trimmed == "thr%" or trimmed == "throttle%" or trimmed == "throttle_percent" then
        thrCol = colIdx
      elseif trimmed == "armd" or trimmed == "arm" then
        armCol = colIdx
      end
      colIdx = colIdx + 1
    end
    -- Fallbacks
    if not vbatCol then vbatCol = 1 end
    if not currCol then currCol = 2 end
    if not hspdCol then hspdCol = 3 end
    if not esctCol then esctCol = 4 end
    if not thrCol then thrCol = 5 end
  end

  local function splitRow(rowStr)
    local cols = {}
    for item in string.gmatch(rowStr .. ",", "([^,]*),") do
      cols[#cols + 1] = item
    end
    return cols
  end

  local function parseTimeSec(tStr)
    if not tStr then return nil end
    local h, m, s, ms = string.match(tStr, "(%d+):(%d+):(%d+)%.?(%d*)")
    if h and m and s then
      local sec = tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
      if ms and ms ~= "" then
        sec = sec + (tonumber("0." .. ms) or 0)
      end
      return sec
    end
    return nil
  end

  local startTimeSec = nil
  local endTimeSec = nil
  local vStart = nil
  local vMin = nil
  local vMax = nil
  local vEnd = nil
  local cPeak = 0
  local cSum = 0
  local cSamples = 0
  local lastCapa = nil
  local rMax = 0
  local rMinFlight = nil
  local tStart = nil
  local tMax = nil
  local thrMax = 0
  local totalSamples = 0

  local buffer = ""
  while true do
    local chunk = io.read(f, 2048)
    if not chunk or chunk == "" then
      if buffer ~= "" then
        chunk = "\n"
      else
        break
      end
    end
    buffer = buffer .. chunk

    while true do
      local nl = string.find(buffer, "\n")
      if not nl then break end
      local line = string.sub(buffer, 1, nl - 1)
      buffer = string.sub(buffer, nl + 1)

      line = string.gsub(line, "\r", "")
      if line ~= "" then
        if not headerLine then
          if string.match(line, "%a") then
            headerLine = line
            parseHeader(line)
          end
        else
          local cols = splitRow(line)
          totalSamples = totalSamples + 1

          -- Time
          if timeCol and cols[timeCol] then
            local tSec = parseTimeSec(cols[timeCol])
            if tSec then
              if not startTimeSec then startTimeSec = tSec end
              endTimeSec = tSec
            end
          end

          -- Voltage
          if vbatCol and cols[vbatCol] then
            local v = tonumber(cols[vbatCol])
            if v and v > 2.0 then
              if not vStart then vStart = v end
              if not vMin or v < vMin then vMin = v end
              if not vMax or v > vMax then vMax = v end
              vEnd = v
            end
          end

          -- Current
          if currCol and cols[currCol] then
            local c = tonumber(cols[currCol])
            if c and c >= 0 then
              if c > cPeak then cPeak = c end
              cSum = cSum + c
              cSamples = cSamples + 1
            end
          end

          -- Capacity (from FC telemetry Capa(mAh) or SmCp(mAh))
          if capaCol and cols[capaCol] then
            local cap = tonumber(cols[capaCol])
            if cap and cap > 0 then
              lastCapa = cap
            end
          end

          -- ESC Temp
          if esctCol and cols[esctCol] then
            local tmp = tonumber(cols[esctCol])
            if tmp and tmp > 0 then
              if not tStart then tStart = tmp end
              if not tMax or tmp > tMax then tMax = tmp end
            end
          end

          -- Throttle %
          if thrCol and cols[thrCol] then
            local thr = tonumber(cols[thrCol])
            if thr and thr >= 0 and thr <= 100 then
              if thr > thrMax then thrMax = thr end
            end
          end

          -- RPM (only evaluate when motor is actively driving the head, ignoring spool-down / autorotation)
          if hspdCol and cols[hspdCol] then
            local r = tonumber(cols[hspdCol])
            if r and r > 0 then
              local cVal = currCol and tonumber(cols[currCol]) or 0
              local thrVal = thrCol and tonumber(cols[thrCol]) or 0
              local armVal = armCol and tonumber(cols[armCol]) or 1

              local isPowered = (armVal > 0) and ((thrVal >= 25) or (cVal >= 1.5))
              if isPowered then
                if r > rMax then rMax = r end
                if r > 1000 then
                  if not rMinFlight or r < rMinFlight then
                    rMinFlight = r
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  io.close(f)

  if totalSamples == 0 then return nil end

  local durationSec = 0
  if startTimeSec and endTimeSec and endTimeSec >= startTimeSec then
    durationSec = math.floor(endTimeSec - startTimeSec)
  else
    durationSec = math.floor(totalSamples / 10)
  end

  local durationMin = math.floor(durationSec / 60)
  local durationRemSec = durationSec % 60
  local durationStr = string.format("%02d:%02d min", durationMin, durationRemSec)

  local cAvg = cSamples > 0 and (cSum / cSamples) or 0
  local consumedMah = lastCapa or ((cSum / (cSamples > 0 and cSamples or 1)) * (durationSec / 3600) * 1000)

  return {
    sampleCount = totalSamples,
    durationStr = durationStr,
    vStart = vStart or 0,
    vMin = vMin or (vStart or 0),
    vMax = vMax or (vStart or 0),
    vEnd = vEnd or (vStart or 0),
    vSag = ((vStart or 0) > (vMin or 0)) and ((vStart or 0) - (vMin or 0)) or 0,
    cPeak = cPeak,
    cAvg = cAvg,
    mah = consumedMah,
    rMax = rMax,
    rMin = rMinFlight or 0,
    tStart = tStart or 0,
    tMax = tMax or (tStart or 0),
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

function M.wakeup(ctx)
  ensureDeps()
  if type(ctx) == "table" and type(ctx.requestRebuild) == "function" then
    state.requestRebuild = ctx.requestRebuild
  end

  if state.loading and state.selectedFilePath then
    state.loadingFrames = (state.loadingFrames or 0) + 1
    if state.loadingFrames >= 2 then
      state.summary = parseTelemetryCsv(state.selectedFilePath)
      collectgarbage("collect")
      state.loading = false
      state.loadingFrames = 0
      if state.requestRebuild then
        state.requestRebuild()
      end
    end
  end
end

function M.onReload(ctx)
  scanLogFiles()
  state.selectedFile = nil
  state.selectedFilePath = nil
  state.summary = nil
  state.loading = false
  state.loadingFrames = 0
  collectgarbage("collect")
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
    state.loading = false
    state.loadingFrames = 0
    collectgarbage("collect")
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

  -- If loading overlay is active
  if state.loading and LoadingOverlay then
    LoadingOverlay.append(children, {
      x = x,
      y = y,
      w = w,
      h = h,
      title = pageText(i18n, "loading_title"),
      message = pageText(i18n, "loading_message"),
      progress = 0.5
    })
    return
  end

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
      text = string.format("%s: %d rpm   |   %s: %d rpm (%s)",
        pageText(i18n, "max"), math.floor(summary.rMax),
        pageText(i18n, "min"), math.floor(summary.rMin),
        pageText(i18n, "in_flight")),
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

    -- Date and Time
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

    -- View button
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
        state.loading = true
        state.loadingFrames = 0
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
  state.loading = false
  state.loadingFrames = 0
  state.logsList = {}
  LoadingOverlay = nil
  collectgarbage("collect")
end

return M
