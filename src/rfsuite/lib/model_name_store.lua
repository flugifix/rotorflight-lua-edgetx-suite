-- Where the radio's own model name is kept while a craft's name stands in its place.
--
-- The rename `tasks/events/onconnect/tasks/model_name_sync.lua` performs is temporary, and the
-- restore is the whole of what makes it temporary. The record it restores from therefore has to
-- outlive everything that could be running when the link goes -- the tool, the widgets, and the
-- radio itself. Two properties follow from that, and neither is decoration.
--
-- It is readable WITH NO LINK. A per-board file is not: it is addressed by the flight
-- controller's MCU id, and with nothing powered there is no id to address it by. That is exactly
-- the case a backstop exists for -- the radio switched off while still connected, where no
-- disconnect ever runs and the model comes back up wearing the craft's name.
--
-- It is keyed by the RADIO MODEL. A single slot for the whole transmitter puts one model's old
-- name onto whichever model happens to be selected when the restore finally runs, which turns a
-- missing restore into a wrong one.
--
-- The file is this module's own rather than a section of preferences.ini. That file is rewritten
-- whole on every save and is watched for changes by the widget; a record written twice per flight
-- has no business triggering either.

if type(_G) == "table" and type(_G.__rfsuite_model_name_store) == "table" then
  return _G.__rfsuite_model_name_store
end

local M = {}

local USER_ROOTS = {
  "/SCRIPTS/TOOLS/rfsuite.user",
  "SCRIPTS:/TOOLS/rfsuite.user"
}

local FILE_NAME = "model_name_restore.ini"
local KEY = "previous_name"

-- How much is asked for per io.read() call. A chunk size, not a limit: the reader keeps going
-- until the file ends.
local READ_CHUNK = 2048

-- How often the current model is asked for while a record exists that does not belong to it.
-- `model.getInfo()` builds a table on every call, and this runs on the disconnected tick.
local LOOKUP_INTERVAL_SECONDS = 1.0

--: model filename -> the name that model had before the rename. `nil` until the file has been
--: read, which happens once per Lua state; the tool and the widgets each hold their own copy and
--: the file is what they share.
local entries = nil
local anyEntries = false
local resolvedPath = nil
local nextLookupAt = 0

local function trim(s)
  local asString = tostring(s or "")
  asString = string.gsub(asString, "^%s+", "")
  asString = string.gsub(asString, "%s+$", "")
  return asString
end

local function nowSeconds()
  if type(getTime) == "function" then
    local ok, v = pcall(getTime)
    if ok and type(v) == "number" then return v / 100 end
  end
  return 0
end

local function fileExists(path)
  local f = io.open(path, "r")
  if not f then return false end
  io.close(f)
  return true
end

-- The same root order the per-board store uses: whichever spelling of the user directory already
-- holds the suite's settings is the one this file belongs beside. Falling back to the first entry
-- rather than to nothing means a fresh install still has a path to write to.
local function resolvePath()
  if resolvedPath then return resolvedPath end
  for i = 1, #USER_ROOTS do
    if fileExists(USER_ROOTS[i] .. "/" .. FILE_NAME) then
      resolvedPath = USER_ROOTS[i] .. "/" .. FILE_NAME
      return resolvedPath
    end
  end
  for i = 1, #USER_ROOTS do
    if fileExists(USER_ROOTS[i] .. "/preferences.ini") then
      resolvedPath = USER_ROOTS[i] .. "/" .. FILE_NAME
      return resolvedPath
    end
  end
  resolvedPath = USER_ROOTS[1] .. "/" .. FILE_NAME
  return resolvedPath
end

local function readFile(path)
  local f = io.open(path, "r")
  if not f then return nil end

  local parts = {}
  while true do
    local chunk = io.read(f, READ_CHUNK)
    if chunk == nil or chunk == "" then break end
    parts[#parts + 1] = chunk
  end
  io.close(f)

  local content = table.concat(parts)
  if content == "" then return nil end
  return content
end

-- A model file name goes in the SECTION rather than in the key, because a section is read to the
-- last `]` on its line and a key only to the first `=`. Of the two characters, an equals sign is
-- much the likelier to turn up in a model name, and this way such a name survives a round trip.
local function parse(content)
  local result = {}
  local anyFound = false
  if type(content) ~= "string" or content == "" then return result, anyFound end

  local section = nil
  for line in string.gmatch(content, "[^\r\n]+") do
    local normalized = trim(line)
    if normalized ~= "" and string.sub(normalized, 1, 1) ~= ";" and string.sub(normalized, 1, 1) ~= "#" then
      local sec = string.match(normalized, "^%[(.-)%]$")
      if sec then
        section = trim(sec)
      elseif section then
        local k, v = string.match(normalized, "^([^=]+)=(.*)$")
        if k and trim(k) == KEY then
          local name = trim(v)
          if name ~= "" then
            result[section] = name
            anyFound = true
          end
        end
      end
    end
  end

  return result, anyFound
end

local function ensureLoaded()
  if entries ~= nil then return end
  entries, anyEntries = parse(readFile(resolvePath()))
end

local function save()
  local path = resolvePath()
  local f = io.open(path, "w")
  if not f then return false end

  for modelFile, name in pairs(entries or {}) do
    io.write(f, "[" .. tostring(modelFile) .. "]\n")
    io.write(f, KEY .. "=" .. tostring(name) .. "\n")
  end

  io.close(f)
  return true
end

local function currentModelFile()
  if type(model) ~= "table" or type(model.getInfo) ~= "function" then return nil end
  local ok, info = pcall(model.getInfo)
  if not ok or type(info) ~= "table" then return nil end
  local fileName = info.filename
  if type(fileName) ~= "string" or fileName == "" then return nil end
  return fileName, info
end

--- Is there anything at all to put back, for any model?
--
-- The cheap half of the disconnected tick: after the first call, false costs one boolean. That is
-- what keeps this out of the way in the case that is almost always the true one -- nothing
-- renamed, nothing to do.
function M.hasAny()
  ensureLoaded()
  return anyEntries
end

--- The name recorded for the model that is selected now, or nil.
function M.pending()
  ensureLoaded()
  if not anyEntries then return nil end
  local modelFile = currentModelFile()
  if not modelFile then return nil end
  return entries[modelFile]
end

--- Record what this model was called before the craft name was written over it.
function M.remember(name)
  if type(name) ~= "string" or name == "" then return false end
  ensureLoaded()
  local modelFile = currentModelFile()
  if not modelFile then return false end
  if entries[modelFile] == name then return true end
  entries[modelFile] = name
  anyEntries = true
  return save()
end

--- Drop this model's record without touching the model itself.
function M.forget()
  ensureLoaded()
  if not anyEntries then return true end
  local modelFile = currentModelFile()
  if not modelFile or entries[modelFile] == nil then return true end
  entries[modelFile] = nil
  anyEntries = next(entries) ~= nil
  return save()
end

--- Put the recorded name back on the model that is selected now, and clear the record.
--
-- Returns the name that was restored, or nil where there was nothing to do. The caller decides
-- WHEN this may happen: it writes to the pilot's model, so it belongs on a tick that has already
-- established there is no craft on the other end.
function M.restore()
  ensureLoaded()
  if not anyEntries then return nil end

  local t = nowSeconds()
  if t < nextLookupAt then return nil end
  nextLookupAt = t + LOOKUP_INTERVAL_SECONDS

  local modelFile, info = currentModelFile()
  if not modelFile then return nil end

  local name = entries[modelFile]
  if name == nil then return nil end

  -- The record is dropped only once the name is actually back on the model. Dropping it first
  -- would turn a single failed write into a name the pilot never gets back at all; leaving it
  -- costs one retry on a later tick, which is what the interval above bounds.
  if info.name ~= name then
    if type(model.setInfo) ~= "function" then return nil end
    info.name = name
    if pcall(model.setInfo, info) ~= true then return nil end
  end

  entries[modelFile] = nil
  anyEntries = next(entries) ~= nil
  save()
  return name
end

if type(_G) == "table" then
  _G.__rfsuite_model_name_store = M
end

return M
