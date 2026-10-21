-- EdgeTX MSP API: SET_ARMING_DISABLED (MSP_SET_ARMING_DISABLED, 99, write only)
--
-- U8 1 inhibits arming (and disarms an armed board), 0 releases the inhibit. The firmware scopes
-- the inhibit to the MSP connection that set it; the caller owns entry, read-back and release.

local Api = { writeCommand = 99 }

function Api.buildWritePayload(data) return { data and data.disabled and 1 or 0 } end

return Api
