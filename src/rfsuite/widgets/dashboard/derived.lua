local Derived = {}

local requireModule = (_G.rfsuite and _G.rfsuite.require)
if not requireModule then
  local mode = (_G.rfsuite and _G.rfsuite.loadMode) or "bt"
  local rChunk = loadScript("/SCRIPTS/TOOLS/rfsuite-core/lib/require.lua", mode)
  if rChunk then
    local ok, res = pcall(rChunk)
    if ok and type(res) == "function" then
      requireModule = res
    end
  end
end
requireModule = requireModule or function(path)
  local fullPath = string.sub(path, 1, 1) == "/" and path or ("/SCRIPTS/TOOLS/rfsuite-core/" .. path)
  local mode = (_G.rfsuite and _G.rfsuite.loadMode) or "bt"
  local chunk = loadScript(fullPath, mode)
  if chunk then
    local ok, mod = pcall(chunk)
    if ok and type(mod) == "table" then return mod end
  end
  return nil
end

local Utils = requireModule("widgets/dashboard/objects/common.lua")

-- Builds `state.derived`: one resolved value per source the standing tree reads, so the
-- reactive sweep never probes. Probing (sensors, `model.getInfo`) is legal HERE -- this
-- runs in the widget's own pass, inside its pcall, on the telemetry-read cadence -- and
-- illegal in a reactive closure, which runs per frame on the refresh's leftover budget
-- outside any pcall (see GEMINI.md, "Dashboard reactive closures").
--
-- Beside each plain source, its `+` and `-` variants are resolved too: the stats objects
-- read the min/max sensors under those names, and a variant that does not exist simply
-- resolves to nil, exactly as its probe would have.
function Derived.build(state, sources)
  if type(state) ~= "table" then return end
  if not (Utils and type(Utils.mapTelemetrySource) == "function") then return end

  local snap = {}
  if type(sources) == "table" then
    for i = 1, #sources do
      local source = sources[i]
      if type(source) == "string" and source ~= "" then
        snap[source] = Utils.mapTelemetrySource(source, state)
        snap[source .. "+"] = Utils.mapTelemetrySource(source .. "+", state)
        snap[source .. "-"] = Utils.mapTelemetrySource(source .. "-", state)
      end
    end
  end

  -- Read by the image and text objects whether or not any box declares them as a source.
  snap.model_name = Utils.mapTelemetrySource("model_name", state)
  if model and type(model.getInfo) == "function" then
    local info = model.getInfo()
    if info then
      snap.edgetx_model_name = info.name
      snap.edgetx_model_bitmap = info.bitmap
    end
  end

  -- Assigned once, as a fresh table per build: closures hold `state` and read mid-sweep,
  -- so the swap has to be atomic -- a table filled in place would show half a snapshot.
  state.derived = snap
end

return Derived
