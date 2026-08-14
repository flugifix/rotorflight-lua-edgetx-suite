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

local state = {
  lastSeq = -1,
  requestRebuild = nil,
  i18n = nil
}

local function ensureDeps()
  if not Common then Common = loadModule("app/pages/settings/common.lua") end
  if not t then t = Common and Common.pageT("diagnostics_session_logs") or nil end
end

local function pageText(i18n, key, fallback)
  local obj = i18n or state.i18n
  if t then return t(obj, key, fallback) end
  return fallback
end

local function getLogColor(level)
  local l = string.lower(tostring(level or "debug"))
  if l == "error" then return COLOR_THEME_WARNING end
  if l == "warn" then return COLOR_THEME_PRIMARY2 end
  if l == "info" then return COLOR_THEME_PRIMARY1 end
  return GREY_DEFAULT
end

function M.getModuleTitle()
  return "Session Logs"
end

function M.getHeaderActions()
  return { reload = true, save = false, help = false }
end

function M.isPageOpen()
  return true
end

function M.onReload()
  local rf = _G.rfsuite
  if rf then
    rf.log_history = {}
    rf.log_history_seq = (rf.log_history_seq or 0) + 1
    state.lastSeq = -1
  end
  return true
end

function M.build(ctx)
  ensureDeps()
  local rf = _G.rfsuite
  state.requestRebuild = ctx.requestRebuild
  state.i18n = ctx.i18n

  local children = ctx.children
  local x = ctx.x
  local y = ctx.y
  local w = ctx.w
  local h = ctx.h

  -- Always sync sequence counter to prevent rebuild loop in empty state
  state.lastSeq = rf and rf.log_history_seq or 0

  local history = rf and rf.log_history
  if not history or #history == 0 then
    children[#children + 1] = {
      type = "label",
      x = x + 10, y = y + 20, w = w - 20,
      text = pageText(ctx.i18n, "no_logs", "No logs available"),
      color = GREY_DEFAULT, align = CENTER
    }
    return
  end

  local rowH = 22
  local cursorY = y + 5
  local maxVisible = math.floor((h - 10) / rowH)
  
  local startIdx = 1
  if #history > maxVisible then
    startIdx = #history - maxVisible + 1
  end

  for i = startIdx, #history do
    local entry = history[i]
    local color = getLogColor(entry.level)
    
    local timeStr = ""
    if entry.time and entry.time > 0 then
        timeStr = string.format("[%0.1f] ", entry.time / 100)
    end
    
    local lineText = timeStr .. "[" .. tostring(entry.tag) .. "] " .. tostring(entry.msg)

    children[#children + 1] = {
      type = "label",
      x = x + 5, y = cursorY, w = w - 10,
      text = lineText,
      color = color,
      font = SMLSIZE
    }
    cursorY = cursorY + rowH
  end
end

function M.wakeup()
  local rf = _G.rfsuite
  if rf and (rf.log_history_seq or 0) ~= state.lastSeq then
    if type(state.requestRebuild) == "function" then
      state.requestRebuild()
    end
  end
end

function M.paint()
end

function M.handleEvent(eventData)
  return eventData
end

function M.closePage()
  state.requestRebuild = nil
  state.lastSeq = -1
  state.i18n = nil
  Common = nil
  t = nil
end

return M
