local MenuRegistry = {}

function MenuRegistry.new(manifest, i18n, options)
  options = options or {}

  local self = {
    i18n = i18n,
    sections = manifest.sections or {},
    menus = manifest.menus or {},
    conditions = options.conditions or {},
    activeSectionId = nil,
    currentMenuId = nil,
    currentEntryId = nil,
    breadcrumbStack = {}
  }

  local function isEntryEnabled(entry)
    if type(entry) ~= "table" then
      return false
    end

    if entry.enabled == false then
      return false
    end

    local conditionKey = entry.enabledWhen
    if conditionKey == nil then
      return true
    end

    if type(conditionKey) == "string" then
      return self.conditions[conditionKey] == true
    end

    if type(conditionKey) == "function" then
      return conditionKey(self.conditions, entry) == true
    end

    return true
  end

  local function resolveTitle(entry)
    if type(entry) ~= "table" then
      return ""
    end

    if entry.titleKey then
      return i18n.t(entry.titleKey)
    end

    if entry.title then
      return i18n.resolve(entry.title)
    end

    return ""
  end

  local function getSectionById(id)
    for i = 1, #self.sections do
      if self.sections[i].id == id then
        return self.sections[i]
      end
    end
    return nil
  end

  local function getCurrentContainer()
    if self.currentMenuId then
      return self.menus[self.currentMenuId]
    end
    return nil
  end

  local function getCurrentEntries()
    local container = getCurrentContainer()
    if not container then return {} end
    return container.pages or {}
  end

  local function syncCurrentEntry()
    local entries = getCurrentEntries()
    if #entries == 0 then
      self.currentEntryId = nil
      return
    end

    for i = 1, #entries do
      if entries[i].id == self.currentEntryId then
        return
      end
    end

    self.currentEntryId = entries[1].id
  end

  local function pushBreadcrumb(kind, id, title)
    self.breadcrumbStack[#self.breadcrumbStack + 1] = {
      kind = kind,
      id = id,
      title = title
    }
  end

  local function resetBreadcrumbForSection(section)
    self.breadcrumbStack = {}
    pushBreadcrumb("section", section.id, resolveTitle(section))
  end

  if #self.sections > 0 then
    local firstSection = self.sections[1]
    self.activeSectionId = firstSection.id
    self.currentMenuId = nil
    self.breadcrumbStack = {}
    self.currentEntryId = nil
  end

  function self.getActiveSection()
    return getSectionById(self.activeSectionId)
  end

  function self.setActiveSection(id)
    local section = getSectionById(id)
    if not section then return false end

    self.activeSectionId = id
    self.currentMenuId = nil
    resetBreadcrumbForSection(section)
    syncCurrentEntry()
    return true
  end

  function self.isRoot()
    return self.currentMenuId == nil
  end

  function self.getRootGroups(iconRoot)
    local groups = {}
    for i = 1, #self.sections do
      local section = self.sections[i]
      local entries = section.pages or {}
      local cards = {}

      for j = 1, #entries do
        local p = entries[j]
        cards[j] = {
          id = p.id,
          sectionId = section.id,
          row = p.row or 1,
          col = p.col or j,
          data = {
            text = resolveTitle(p),
            icon = p.icon and (iconRoot .. p.icon) or nil,
            isMenu = p.menuId ~= nil,
            enabled = isEntryEnabled(p)
          }
        }
      end

      groups[i] = {
        id = section.id,
        title = resolveTitle(section),
        cards = cards
      }
    end

    return groups
  end

  function self.openRootEntry(sectionId, entryId)
    local section = getSectionById(sectionId)
    if not section then return false end

    local entries = section.pages or {}
    for i = 1, #entries do
      local entry = entries[i]
      if entry.id == entryId then
        if not isEntryEnabled(entry) then
          return false
        end

        self.activeSectionId = sectionId
        self.currentEntryId = entryId
        resetBreadcrumbForSection(section)

        if entry.menuId and self.menus[entry.menuId] then
          self.currentMenuId = entry.menuId
          pushBreadcrumb("menu", entry.menuId, resolveTitle(self.menus[entry.menuId]))
          syncCurrentEntry()
        end

        return true
      end
    end

    return false
  end

  function self.openEntry(id)
    local entries = getCurrentEntries()
    for i = 1, #entries do
      local entry = entries[i]
      if entry.id == id then
        if not isEntryEnabled(entry) then
          return false
        end

        self.currentEntryId = id
        if entry.menuId and self.menus[entry.menuId] then
          self.currentMenuId = entry.menuId
          pushBreadcrumb("menu", entry.menuId, resolveTitle(self.menus[entry.menuId]))
          syncCurrentEntry()
        end
        return true
      end
    end
    return false
  end

  function self.goBack()
    if not self.currentMenuId then
      return false
    end

    self.breadcrumbStack[#self.breadcrumbStack] = nil
    local parent = self.breadcrumbStack[#self.breadcrumbStack]

    if not parent then
      self.currentMenuId = nil
      local section = self.getActiveSection()
      if section then
        resetBreadcrumbForSection(section)
      end
      syncCurrentEntry()
      return true
    end

    if parent.kind == "section" then
      self.currentMenuId = nil
      self.currentEntryId = nil
    elseif parent.kind == "menu" then
      self.currentMenuId = parent.id
    end

    syncCurrentEntry()
    return true
  end

  function self.getBreadcrumb()
    local parts = {}
    for i = 1, #self.breadcrumbStack do
      local title = self.breadcrumbStack[i].title
      if title and title ~= "" then
        parts[#parts + 1] = title
      end
    end

    return table.concat(parts, " / ")
  end

  function self.getHeaderTitle()
    if self:isRoot() then
      local section = self.getActiveSection()
      return section and resolveTitle(section) or ""
    end

    local top = self.breadcrumbStack[#self.breadcrumbStack]
    return (top and top.title) or ""
  end

  function self.getHeaderBreadcrumb()
    if self:isRoot() then
      return ""
    end

    local parts = {}
    for i = 1, (#self.breadcrumbStack - 1) do
      local title = self.breadcrumbStack[i].title
      if title and title ~= "" then
        parts[#parts + 1] = title
      end
    end

    return table.concat(parts, " / ")
  end

  function self.getCards(iconRoot)
    local entries = getCurrentEntries()
    local cards = {}
    for i = 1, #entries do
      local p = entries[i]
      local row = p.row or math.floor((i - 1) / 3) + 1
      local col = p.col or ((i - 1) % 3) + 1
      cards[i] = {
        id = p.id,
        row = row,
        col = col,
        data = {
          text = resolveTitle(p),
          icon = p.icon and (iconRoot .. p.icon) or nil,
          isMenu = p.menuId ~= nil,
          enabled = isEntryEnabled(p)
        }
      }
    end

    return cards
  end

  function self.getCurrentEntryId()
    return self.currentEntryId
  end

  function self.isRootEntryEnabled(sectionId, entryId)
    local section = getSectionById(sectionId)
    if not section then
      return false
    end

    local entries = section.pages or {}
    for i = 1, #entries do
      local entry = entries[i]
      if entry.id == entryId then
        return isEntryEnabled(entry)
      end
    end

    return false
  end

  function self.isEntryEnabled(entryId)
    local entries = getCurrentEntries()
    for i = 1, #entries do
      local entry = entries[i]
      if entry.id == entryId then
        return isEntryEnabled(entry)
      end
    end

    return false
  end

  function self.setCondition(key, value)
    self.conditions[key] = value == true
  end

  return self
end

return MenuRegistry
