-- SD snapshots use the same Lua-data format and model directory as model preferences.
-- Serialization and verification are sliced; only a complete temporary file is promoted.
local M = {}
local requireModule = _G.rfsuite.require
local Preferences = requireModule("lib/model_preferences.lua")
if type(Preferences) ~= "table" then error("inflight/baseline.lua: dependency missing", 0) end

function M.path(uid)
  local path = Preferences.buildPath(uid)
  return path and string.gsub(path, "%.lua$", ".inflight.lua") or nil
end

local function read(path)
  local chunk = loadScript(path, "t", {})
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  return ok and type(data) == "table" and data or nil
end
M.read = read

local function temporary(path)
  -- loadScript replaces the last extension before probing the source and bytecode.
  return string.gsub(path, "%.lua$", ".tmp.lua")
end

local function remove(path)
  return type(del) == "function" and del(path) == 0
end
local function move(from, to)
  return type(rename) == "function" and rename(from, to) == 0
end

function M.load(uid, identity)
  local path = M.path(uid)
  local data = path and (read(path) or read(temporary(path)))
  if not data then return nil, "baseline_missing" end
  if type(data.meta) ~= "table" or data.meta.identity ~= identity or data.meta.uid ~= uid then
    return nil, "baseline_identity"
  end
  return data
end

function M.begin(uid, data)
  local path = M.path(uid)
  if not path or type(rename) ~= "function" or type(del) ~= "function" then return nil, "baseline_io" end
  local f = io.open(temporary(path), "w")
  if not f then return nil, "baseline_io" end
  io.write(f, "return {\n")
  return { path = path, file = f, data = data, section = nil, key = nil, phase = "write" }
end

function M.cancel(work)
  if work and work.file then io.close(work.file); work.file = nil end
end

-- At most eight scalar values per pass, including the independent read-back comparison.
function M.step(work)
  if work.phase == "write" then
    for _ = 1, 8 do
      if not work.section then
        local section = next(work.data, work.lastSection)
        if not section then
          io.write(work.file, "}\n"); io.close(work.file); work.file = nil
          work.phase = "load"
          return false
        end
        work.section, work.key = section, nil
        io.write(work.file, "[" .. string.format("%q", section) .. "]={\n")
      end
      local key, value = next(work.data[work.section], work.key)
      if key == nil then
        io.write(work.file, "},\n")
        work.lastSection, work.section = work.section, nil
      else
        local literal = type(value) == "string" and string.format("%q", value) or tostring(value)
        io.write(work.file, "[" .. string.format("%q", tostring(key)) .. "]=" .. literal .. ",\n")
        work.key = key
      end
    end
  elseif work.phase == "load" then
    work.check = read(work.promoted and work.path or temporary(work.path))
    if not work.check then return true, "baseline_io" end
    work.phase, work.section, work.lastSection = "verify", nil, nil
  elseif work.phase == "verify" then
    for _ = 1, 8 do
      if not work.section then
        local section = next(work.data, work.lastSection)
        if not section then
          if work.promoted then return true end
          work.phase = "promote"; return false
        end
        if type(work.check[section]) ~= "table" then return true, "baseline_io" end
        work.section, work.key = section, nil
      end
      local key, value = next(work.data[work.section], work.key)
      if key == nil then
        work.lastSection, work.section = work.section, nil
      else
        if work.check[work.section][tostring(key)] ~= value then return true, "baseline_io" end
        work.key = key
      end
    end
  elseif work.phase == "promote" then
    -- FAT rename cannot replace a file. Keep the previous complete snapshot until the
    -- new one has been verified, as config_store.lua does for preference saves.
    local existing = io.open(work.path, "r")
    if existing then
      io.close(existing)
      if not remove(work.path) then return true, "baseline_io" end
    end
    if not move(temporary(work.path), work.path) then return true, "baseline_io" end
    work.phase, work.promoted = "load", true
    return false
  end
  return false
end

return M
