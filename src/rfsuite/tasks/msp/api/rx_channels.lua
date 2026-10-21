-- EdgeTX MSP API: RX_CHANNELS (MSP_RX_CHANNELS, 114, read only)
--
-- One U16 per active receiver channel, in the receiver's wire order before the channel map is
-- applied, at most 18. A board that has no active receiver channel answers with an empty reply,
-- which reads as zero channels. channels[1] is the first channel on the wire.

local Api = {
  command = 114,
  simulatorResponse = { 220, 5, 220, 5, 220, 5, 220, 5, 232, 3, 232, 3, 220, 5, 208, 7 }
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf % 2 ~= 0 or #buf > 36 then return nil end
  local values = {}
  for i = 1, #buf, 2 do values[#values + 1] = buf[i] + buf[i + 1] * 256 end
  return { channels = values, channel_count = #values }
end

return Api
