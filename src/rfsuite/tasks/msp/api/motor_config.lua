-- Ported MOTOR_CONFIG -> motor_config.lua
local Api = {
    command = 131,
    writeCommand = 222
}

local FIELD_SPEC = {
    {"minthrottle", "U16"},
    {"maxthrottle", "U16"},
    {"mincommand", "U16"},
    {"motor_count_blheli", "U8"},
    {"motor_pole_count_blheli", "U8"},
    {"use_dshot_telemetry", "U8"},
    {"motor_pwm_protocol", "U8"},
    {"motor_pwm_rate", "U16"},
    {"use_unsynced_pwm", "U8"},
    {"motor_pole_count_0", "U8"},
    {"motor_pole_count_1", "U8"},
    {"motor_pole_count_2", "U8"},
    {"motor_pole_count_3", "U8"},
    {"motor_rpm_lpf_0", "U8"},
    {"motor_rpm_lpf_1", "U8"},
    {"motor_rpm_lpf_2", "U8"},
    {"motor_rpm_lpf_3", "U8"},
    {"main_rotor_gear_ratio_0", "U16"},
    {"main_rotor_gear_ratio_1", "U16"},
    {"tail_rotor_gear_ratio_0", "U16"},
    {"tail_rotor_gear_ratio_1", "U16"}
}

local SIM_RESPONSE = {
    45,4, -- minthrottle
    200,6, -- maxthrottle
    0,0, -- mincommand
    1, -- motor_count_blheli
    3, -- motor_pole_count_blheli
    0, -- use_dshot_telemetry
    0, -- motor_pwm_protocol
    0,0, -- motor_pwm_rate
    0, -- use_unsynced_pwm
    0,0,0,0, -- motor_pole_count_0..3
    0,0,0,0, -- motor_rpm_lpf_0..3
    0,0, -- main_rotor_gear_ratio_0
    0,0, -- main_rotor_gear_ratio_1
    0,0, -- tail_rotor_gear_ratio_0
    0,0, -- tail_rotor_gear_ratio_1
}

local function to_u16(lo, hi)
    lo = tonumber(lo) or 0
    hi = tonumber(hi) or 0
    return ((hi & 0xFF) << 8) | (lo & 0xFF)
end

local function from_u16(v)
    v = tonumber(v) or 0
    v = v & 0xFFFF
    return v & 0xFF, (v >> 8) & 0xFF
end

Api.simulatorResponse = (function()
    local t = {}
    for _, b in ipairs(SIM_RESPONSE) do t[#t+1] = b end
    return t
end)()

function Api.parse(buf)
    if type(buf) ~= "table" then return nil end
    local out = {}
    local i = 1
    for _, t in ipairs(FIELD_SPEC) do
        local name, typ = t[1], t[2]
        if typ == "U8" then
            out[name] = buf[i] and tonumber(buf[i]) or 0
            i = i + 1
        elseif typ == "U16" then
            out[name] = (buf[i] and buf[i+1]) and to_u16(buf[i], buf[i+1]) or 0
            i = i + 2
        else
            out[name] = buf[i] and tonumber(buf[i]) or 0
            i = i + 1
        end
    end
    return out
end

-- Build payload using the canonical FIELD_SPEC order (fallback/simple write)
function Api.buildWritePayload(data)
    data = data or {}
    local p = {}
    for _, t in ipairs(FIELD_SPEC) do
        local name, typ = t[1], t[2]
        local val = data[name] or 0
        if typ == "U8" then p[#p+1] = val & 0xFF
        elseif typ == "U16" then local lo, hi = from_u16(val); p[#p+1] = lo; p[#p+1] = hi
        else p[#p+1] = val & 0xFF end
    end
    return p
end

return Api
