-- Ported ESC_PARAMETERS_HW5 -> esc_parameters_hw5.lua
local Api = {
    command = 217,
    writeCommand = 218,
    mspSignature = 0xFD,
    mspHeaderBytes = 2
}

local FIELD_SPEC = {
    {"esc_signature", "U8"},
    {"esc_command", "U8"},
    {"firmware_version", "U128"},
    {"hardware_version", "U128"},
    {"esc_type", "U128"},
    {"com_version", "U120"},
    {"flight_mode", "U8"},
    {"lipo_cell_count", "U8"},
    {"volt_cutoff_type", "U8"},
    {"cutoff_voltage", "U8"},
    {"bec_voltage", "U8"},
    {"startup_time", "U8"},
    {"gov_p_gain", "U8"},
    {"gov_i_gain", "U8"},
    {"auto_restart", "U8"},
    {"restart_time", "U8"},
    {"brake_type", "U8"},
    {"brake_force", "U8"},
    {"timing", "U8"},
    {"rotation", "U8"},
    {"active_freewheel", "U8"},
    {"startup_power", "U8"}
}

local SIM_RESPONSE = {
    253, -- esc_signature
    0, -- esc_command
    32, 32, 32, 80, 76, 45, 48, 52, 46, 49, 46, 48, 50, 32, 32, 32, -- firmware_version (16 bytes)
    72, 87, 49, 49, 48, 54, 95, 86, 50, 48, 48, 52, 53, 54, 78, 66, -- hardware_version (16)
    80, 108, 97, 116, 105, 110, 117, 109, 95, 86, 53, 32, 32, 32, 32, 32, -- esc_type (16)
    80, 108, 97, 116, 105, 110, 117, 109, 32, 86, 53, 32, 32, 32, 32, -- com_version (15)
    0, -- flight_mode
    0, -- lipo_cell_count
    0, -- volt_cutoff_type
    3, -- cutoff_voltage
    0, -- bec_voltage
    11, -- startup_time
    6, -- gov_p_gain
    5, -- gov_i_gain
    25, -- auto_restart
    1, -- restart_time
    0, -- brake_type
    0, -- brake_force
    24, -- timing
    0, -- rotation
    0, -- active_freewheel
    2 -- startup_power
}

local TYPE_LEN = {U8=1,S8=1,U16=2,S16=2,U24=3,U32=4,U64=8,U120=15,U128=16}

local function has_big_flag(field)
    for _, v in ipairs(field) do if v == "big" then return true end end
    return false
end

local function read_unsigned(buf, pos, len, big)
    local v = 0
    if big then
        for i = 0, len - 1 do v = v * 256 + (tonumber(buf[pos + i]) or 0) end
    else
        local mul = 1
        for i = 0, len - 1 do v = v + (tonumber(buf[pos + i]) or 0) * mul; mul = mul * 256 end
    end
    return v
end

local function read_signed(buf, pos, len, big)
    local v = read_unsigned(buf, pos, len, big)
    local max = 2 ^ (len * 8)
    local half = 2 ^ (len * 8 - 1)
    if v >= half then v = v - max end
    return v
end

local function bytes_to_string(buf, pos, len)
    local chars = {}
    for i = 0, len - 1 do chars[#chars+1] = string.char(tonumber(buf[pos + i]) or 0) end
    local s = table.concat(chars)
    s = string.gsub(s, "%z+$", "")
    s = string.gsub(s, "%s+$", "")
    return s
end

local function pack_unsigned(v, len, big)
    v = tonumber(v) or 0
    local out = {}
    if big then
        for i = len - 1, 0, -1 do out[#out+1] = math.floor(v / (256 ^ i)) % 256 end
    else
        for i = 0, len - 1 do out[#out+1] = math.floor(v / (256 ^ i)) % 256 end
    end
    return out
end

local function pack_string(s, len)
    s = s or ""
    local out = {}
    for i = 1, len do out[#out+1] = string.byte(s, i) or 0 end
    return out
end

Api.fields = FIELD_SPEC
Api.simulatorResponse = SIM_RESPONSE

function Api.parse(buf)
    if type(buf) ~= "table" then return nil end
    local pos = 1
    local out = {}
    for _, f in ipairs(FIELD_SPEC) do
        local name, typ = f[1], f[2]
        local len = TYPE_LEN[typ] or 1
        local big = has_big_flag(f)
        if typ == "U120" or typ == "U128" then
            out[name] = bytes_to_string(buf, pos, len); pos = pos + len
        elseif string.sub(typ, 1, 1) == "S" then
            out[name] = read_signed(buf, pos, len, big); pos = pos + len
        else
            out[name] = read_unsigned(buf, pos, len, big); pos = pos + len
        end
    end
    return out
end

function Api.buildWritePayload(data)
    data = data or {}
    local payload = {}
    for _, f in ipairs(FIELD_SPEC) do
        local name, typ = f[1], f[2]
        local len = TYPE_LEN[typ] or 1
        local big = has_big_flag(f)
        local v = data[name]
        if typ == "U120" or typ == "U128" then
            local bytes = pack_string(v, len)
            for _, b in ipairs(bytes) do payload[#payload+1] = b end
        else
            local bytes = pack_unsigned(v or 0, len, big)
            for _, b in ipairs(bytes) do payload[#payload+1] = b end
        end
    end
    return payload
end

return Api
