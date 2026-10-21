-- EdgeTX MSP API: RX_SERIAL_TRIAL (MSP2_RX_SERIAL_TRIAL, 0x5F12)
--
-- The firmware cycles serialrx_inverted, halfDuplex and pinSwap on the configured serial receiver
-- and reports which combination produced a signal. Request: an optional U8 action -- none or 0
-- polls, 1 (re)starts a scan, 2 stops it and restores the previous wiring. Reply, seven bytes:
-- U8 state, U8 combo index, U8 inverted, U8 half duplex, U8 pin swap, U16 elapsed ms.
--
-- Same shape as esc_sensor_trial.lua. A payload on this command reads as a write to the MSP queue
-- unless the message says otherwise, so a caller marks a poll isWrite = false and a start or
-- stop isWrite = true. Re-initialising the receiver port can interrupt an MSP link that runs over
-- that receiver.

local Api = {
  command = 0x5F12,
  ACTION_POLL = 0,
  ACTION_START = 1,
  ACTION_CANCEL = 2,
  simulatorResponse = { 0, 0, 0, 0, 0, 0, 0 }
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 7 then return nil end
  return {
    state = buf[1],
    comboIndex = buf[2],
    inverted = buf[3],
    half_duplex = buf[4],
    pin_swap = buf[5],
    elapsedMs = buf[6] + buf[7] * 256
  }
end

function Api.buildPayload(action)
  return { (tonumber(action) or 0) & 0xFF }
end

return Api
