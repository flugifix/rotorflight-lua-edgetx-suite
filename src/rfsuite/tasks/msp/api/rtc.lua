local Api = {
    command = 247, -- MSP_RTC_READ
    writeCommand = 246, -- MSP_RTC_WRITE
    simulatorResponse = {
        233, 7, -- year (2025)
        1,      -- month
        1,      -- day
        0,      -- hours
        0,      -- minutes
        0,      -- seconds
        0, 0    -- milliseconds (U16 LE)
    }
}

function Api.parse(buf)
    if type(buf) ~= "table" or #buf < 9 then return nil end
    local function u16le(idx)
        local lo = tonumber(buf[idx]) or 0
        local hi = tonumber(buf[idx+1]) or 0
        return lo + hi * 256
    end
    return {
        year = u16le(1),
        month = tonumber(buf[3]) or 0,
        day = tonumber(buf[4]) or 0,
        hours = tonumber(buf[5]) or 0,
        minutes = tonumber(buf[6]) or 0,
        seconds = tonumber(buf[7]) or 0,
        milliseconds = u16le(8)
    }
end

return Api
