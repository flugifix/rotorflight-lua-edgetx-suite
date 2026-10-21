-- MSP_ARMING_DISABLE is scoped by the firmware to the active MSP connection.
local Api = { writeCommand = 99 }
function Api.buildWritePayload(data) return { data and data.disabled and 1 or 0 } end
return Api
