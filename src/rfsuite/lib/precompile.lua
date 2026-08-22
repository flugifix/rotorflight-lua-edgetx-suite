-- lib/precompile.lua
-- Compiles the installed sources ahead of the first page that needs them.
--
-- Opening a page for the first time starts with EdgeTX parsing the .lua and writing the
-- .luac next to it; only then does anything run. With the suite loading in binary-or-text
-- mode (see lib/require.lua) that part can be done in advance, so this walks the installed
-- tree and compiles whatever has no bytecode beside it yet. It does a little of the work per
-- call, so the screen keeps drawing while it runs.
--
-- The version stamp is here because bytecode is picked by timestamp. A source arriving with
-- an older timestamp than the .luac of the previous install would keep running the old
-- bytecode, so a change of version recompiles the whole tree instead of trusting the dates.

local Precompile = {}

local ROOTS = {
  "/SCRIPTS/TOOLS/rfsuite-core",
  "/WIDGETS/rfsuite"
}

local STAMP_PATH = "/SCRIPTS/TOOLS/rfsuite.user/precompiled.txt"

-- Listing a directory costs little next to compiling a file, so the walk is allowed to move
-- faster; both are capped so that no single call runs long.
local DIRS_PER_STEP = 8
local FILES_PER_STEP = 1
local GC_EVERY = 8

local state = nil

local function loadUncached(path, mode)
  local utils = _G.rfsuite and _G.rfsuite.utils
  local loader = utils and utils.loadScriptUncached
  if type(loader) ~= "function" then
    -- Without the uncached loader every chunk read here would be held by the chunk cache of
    -- the tool state, which is the opposite of what this pass is for.
    return nil
  end
  local ok, chunk = pcall(loader, path, mode)
  if not ok then
    return nil
  end
  return chunk
end

local function listEntries(path)
  local entries = {}
  if type(dir) ~= "function" then
    return entries
  end

  local ok, iterator = pcall(dir, path)
  if not ok or type(iterator) ~= "function" then
    return entries
  end

  for name in iterator do
    if type(name) == "string" and name ~= "" and name ~= "." and name ~= ".." then
      entries[#entries + 1] = name
    end
  end

  return entries
end

local function readStamp()
  local f = io.open(STAMP_PATH, "r")
  if not f then
    return nil
  end
  local text = io.read(f, 32)
  io.close(f)
  if type(text) ~= "string" then
    return nil
  end
  return (string.gsub(text, "%s", ""))
end

local function writeStamp(version)
  local f = io.open(STAMP_PATH, "w")
  if not f then
    return
  end
  io.write(f, version)
  io.close(f)
end

local function walk()
  for _ = 1, DIRS_PER_STEP do
    local path = table.remove(state.dirs)
    if not path then
      state.walking = false
      return
    end

    local entries = listEntries(path)

    local hasBytecode = {}
    for i = 1, #entries do
      local name = entries[i]
      if string.sub(name, -5) == ".luac" then
        hasBytecode[string.sub(name, 1, -6)] = true
      end
    end

    for i = 1, #entries do
      local name = entries[i]
      if string.find(name, ".", 1, true) == nil then
        -- No directory in the installed tree carries a dot and every file has an extension,
        -- so this tells the two apart without a stat call per entry.
        state.dirs[#state.dirs + 1] = path .. "/" .. name
      elseif string.sub(name, -4) == ".lua" then
        if state.force or not hasBytecode[string.sub(name, 1, -5)] then
          state.files[#state.files + 1] = path .. "/" .. name
        end
      end
    end
  end
end

local function compile()
  for _ = 1, FILES_PER_STEP do
    local path = state.files[state.done + 1]
    if not path then
      return
    end

    -- "c" compiles even when the bytecode looks newer than the source. The chunk is of no
    -- use here and is dropped, so the collector can take it back.
    loadUncached(path, state.force and "tc" or "t")

    state.done = state.done + 1
    if state.done % GC_EVERY == 0 then
      collectgarbage("collect")
    end
  end
end

-- version is the suite version the stamp is compared against; without one the pass still
-- fills in missing bytecode but never forces a rebuild.
function Precompile.start(version)
  local stamp = readStamp()

  state = {
    version = version,
    force = version ~= nil and stamp ~= version,
    dirs = {},
    files = {},
    done = 0,
    walking = true,
    finished = false
  }

  for i = #ROOTS, 1, -1 do
    state.dirs[#state.dirs + 1] = ROOTS[i]
  end
end

-- One unit of work: a few directories while the tree is still being read, one file after
-- that. Call it once per run cycle.
function Precompile.step()
  if state == nil or state.finished then
    return
  end

  if state.walking then
    walk()
    return
  end

  if state.done < #state.files then
    compile()
    return
  end

  state.finished = true
  collectgarbage("collect")
  if state.force and state.version ~= nil then
    writeStamp(state.version)
  end
end

function Precompile.getProgress()
  if state == nil then
    return 0, 0, true
  end
  return state.done, #state.files, state.finished
end

return Precompile
