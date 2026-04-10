local M = {}

M.MAJOR = 1
M.MINOR = 0
M.PATCH = 0

M.VERSION = M.MAJOR .. "." .. M.MINOR .. "." .. M.PATCH

-- Keep supported protocol targets centralized with app versioning.
-- New Lua package is intended for the latest MSP API version only.
M.SUPPORTED_MSP_API_VERSIONS = {
  "12.09"
}

function M.getVersionString()
  return "v" .. M.VERSION
end

function M.getSupportedMspApiVersions()
  return M.SUPPORTED_MSP_API_VERSIONS
end

function M.getLatestSupportedMspApiVersion()
  local versions = M.SUPPORTED_MSP_API_VERSIONS
  if type(versions) ~= "table" or #versions == 0 then
    return "-"
  end
  return versions[#versions]
end

function M.getSupportedMspApiVersionsString()
  local versions = M.SUPPORTED_MSP_API_VERSIONS
  if type(versions) ~= "table" or #versions == 0 then
    return "-"
  end

  local out = tostring(versions[1])
  for i = 2, #versions do
    out = out .. "," .. tostring(versions[i])
  end
  return out
end

-- Backward-compatible aliases (legacy callers).
function M.getSupportedEdgeTxVersions()
  return M.getSupportedMspApiVersions()
end

function M.getLatestSupportedEdgeTxVersion()
  return M.getLatestSupportedMspApiVersion()
end

function M.getSupportedEdgeTxVersionsString()
  return M.getSupportedMspApiVersionsString()
end

return M
