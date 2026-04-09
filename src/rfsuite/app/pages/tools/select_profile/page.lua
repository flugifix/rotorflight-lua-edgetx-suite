local M = {}

function M.getModuleTitle()
  return "Select Profile"
end

function M.isPageOpen()
  return true
end

function M.buildPage(page)
  return page
end

function M.wakeup()
end

function M.paint()
end

function M.handleEvent(eventData)
  return eventData
end

function M.closePage()
end

return M
