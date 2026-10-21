-- EdgeTX MSP API: ACC_CALIBRATION (MSP_ACC_CALIBRATION, 205, write only)
--
-- Starts the accelerometer calibration; the firmware ignores it while armed. The payload is
-- empty, and the queue takes a message without a payload for a read, so the caller marks it
-- with isWrite = true.

local Api = { writeCommand = 205 }

function Api.buildWritePayload() return {} end

return Api
