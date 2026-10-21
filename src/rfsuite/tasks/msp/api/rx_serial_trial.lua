-- EdgeTX MSP API: RX_SERIAL_TRIAL (MSP2_RX_SERIAL_TRIAL, 0x5F12)
--
-- The firmware cycles serialrx_inverted, halfDuplex and pinSwap on the configured serial receiver
-- and reports which combination produced a signal. Request: an optional U8 action -- none or 0
-- polls, 1 (re)starts a scan, 2 stops it and restores the previous wiring. Reply, seven bytes:
-- U8 state, U8 combo index, U8 inverted, U8 half duplex, U8 pin swap, U16 elapsed ms.
--
-- A poll is sent as a plain read with NO payload: the queue takes any other command that carries
-- a payload for a write. Start and stop go through writeCommand and buildWritePayload.
-- Re-initialising the receiver port can interrupt an MSP link that runs over that receiver.

local Api = {
  command = 0x5F12,
  writeCommand = 0x5F12,
  simulatorResponse = { 0, 0, 0, 0, 0, 0, 0 }
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 7 then return nil end
  return {
    state = buf[1],
    combo_index = buf[2],
    inverted = buf[3],
    half_duplex = buf[4],
    pin_swap = buf[5],
    elapsed_ms = buf[6] + buf[7] * 256
  }
end

-- action 1 starts a scan, 2 stops it; anything else is refused (a poll is the plain read).
function Api.buildWritePayload(data)
  local action = data and data.action
  if action ~= 1 and action ~= 2 then return nil end
  return { action }
end

return Api
