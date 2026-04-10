local CRSF_ADDRESS_BETAFLIGHT = 0xC8
local CRSF_ADDRESS_RADIO_TRANSMITTER = 0xEA
local CRSF_FRAMETYPE_MSP_REQ = 0x7A
local CRSF_FRAMETYPE_MSP_WRITE = 0x7C
local CRSF_FRAMETYPE_MSP_RESP = 0x7B

local transport = {}
local currentFrameType = CRSF_FRAMETYPE_MSP_REQ

function transport.prepareRequest(isWrite)
  currentFrameType = isWrite == true and CRSF_FRAMETYPE_MSP_WRITE or CRSF_FRAMETYPE_MSP_REQ
end

function transport.mspSend(payload)
  local payloadOut = { CRSF_ADDRESS_BETAFLIGHT, CRSF_ADDRESS_RADIO_TRANSMITTER }
  for i = 1, #payload do
    payloadOut[i + 2] = payload[i]
  end
  return crossfireTelemetryPush(currentFrameType, payloadOut)
end

function transport.mspPoll()
  while true do
    local cmd, data = crossfireTelemetryPop()
    if cmd == CRSF_FRAMETYPE_MSP_RESP and data and data[1] == CRSF_ADDRESS_RADIO_TRANSMITTER and data[2] == CRSF_ADDRESS_BETAFLIGHT then
      local mspData = {}
      for i = 3, #data do
        mspData[i - 2] = data[i]
      end
      return mspData
    elseif cmd == nil then
      return nil
    end
  end
end

transport.maxTxBufferSize = 8
transport.maxRxBufferSize = 58
transport.mspPollBudget = 0.1
transport.mspNonBlocking = true
transport.mspPollSliceSeconds = 0.004
transport.mspPollSlicePolls = 6

return transport
