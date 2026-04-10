local function hasFunction(name)
  return type(_G[name]) == "function"
end

local function isSimulatorRuntime()
  if type(system) == "table" and type(system.getVersion) == "function" then
    local ok, info = pcall(system.getVersion)
    if ok and type(info) == "table" then
      local sim = info.simulation
      if sim ~= nil and sim ~= false and sim ~= 0 then
        return true
      end
    end
  end

  if type(getVersion) == "function" then
    local ok, _, fw = pcall(getVersion)
    if ok and type(fw) == "string" then
      local fwl = string.lower(fw)
      if string.find(fwl, "simu", 1, true) ~= nil then
        return true
      end
    end
  end

  return false
end

return function()
  -- Simulator must bypass real MSP transport and use simulator responses.
  if isSimulatorRuntime() then
    return nil
  end

  -- EdgeTX target: only CRSF/ELRS transport is supported.
  if hasFunction("crossfireTelemetryPush") and hasFunction("crossfireTelemetryPop") then
    return "crsf"
  end
  return nil
end
