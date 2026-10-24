-- Shared Governor page editor specifications. Times are stored in tenths of a second.
local M = {
  headspeed = { min = 0, max = 30000, step = 10 },
  gov_spoolup_time = { min = 0, max = 600, step = 1 },
  gov_spooldown_time = { min = 0, max = 600, step = 1 },
  gov_recovery_time = { min = 0, max = 100, step = 1 }
}
function M.seconds(v)
  return string.format("%.1fs", (tonumber(v) or 0) / 10)
end
return M
