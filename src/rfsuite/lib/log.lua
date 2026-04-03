local Log = {}

local function isTruthy(value)
  return value == true or value == 1 or value == "1" or value == "true"
end

function Log.emit(tag, msg, level, enabled)
  if not isTruthy(enabled) then
    return
  end

  if type(print) ~= "function" then
    return
  end

  local t = tag or "rfsuite"
  local lvl = level or "debug"
  print("[" .. tostring(t) .. "][" .. tostring(lvl) .. "] " .. tostring(msg))
end

return Log
