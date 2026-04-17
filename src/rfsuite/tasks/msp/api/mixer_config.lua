-- Ported MIXER_CONFIG -> mixer_config.lua
local Api = {
    command = 42,
    writeCommand = 43
}

local FIELD_SPEC = {
    {"main_rotor_dir", "U8"},
    {"tail_rotor_mode", "U8"},
    {"tail_motor_idle", "U8"},
    {"tail_center_trim", "S16"},
    {"swash_type", "U8"},
    {"swash_ring", "U8"},
    {"swash_phase", "S16"},
    {"swash_pitch_limit", "U16"},
    {"swash_trim_0", "S16"},
    {"swash_trim_1", "S16"},
    {"swash_trim_2", "S16"},
    {"swash_tta_precomp", "U8"},
    {"swash_geo_correction", "S8"},
    {"collective_tilt_correction_pos", "S8"},
    {"collective_tilt_correction_neg", "S8"}
}

local SIM_RESPONSE = {
    0, -- main_rotor_dir
    0, -- tail_rotor_mode
    0, -- tail_motor_idle
    165, 1, -- tail_center_trim (S16)
    1, -- swash_type
    0, -- swash_ring
    17, 0, -- swash_phase (S16)
    0, 0, -- swash_pitch_limit (U16)
    0, 0, -- swash_trim_0 (S16)
    0, 0, -- swash_trim_1 (S16)
    0, 0, -- swash_trim_2 (S16)
    0, -- swash_tta_precomp
    0, -- swash_geo_correction (S8)
    0, -- collective_tilt_correction_pos
    0  -- collective_tilt_correction_neg
}

local function to_u16(lo, hi)
    lo = tonumber(lo) or 0
    hi = tonumber(hi) or 0
    return ((hi & 0xFF) << 8) | (lo & 0xFF)
end

local function to_s16(lo, hi)
    local v = to_u16(lo, hi)
    if v >= 0x8000 then return v - 0x10000 end
    return v
end

local function from_u16(v)
    v = tonumber(v) or 0
    v = v & 0xFFFF
    return v & 0xFF, (v >> 8) & 0xFF
end

local function from_s16(v)
    v = tonumber(v) or 0
    if v < 0 then v = 0x10000 + v end
    v = v & 0xFFFF
    return v & 0xFF, (v >> 8) & 0xFF
end

local function build_sim_response()
    local t = {}
    for _, b in ipairs(SIM_RESPONSE) do t[#t+1] = b end
    return t
end

Api.simulatorResponse = build_sim_response()

local function expected_bytes(spec)
    local n = 0
    for _, f in ipairs(spec) do
        local typ = f[2]
        if typ == "U8" or typ == "S8" then n = n + 1
        elseif typ == "U16" or typ == "S16" then n = n + 2
        else n = n + 1 end
    end
    return n
end

function Api.parse(buf)
    if type(buf) ~= "table" then return nil end
    local need = expected_bytes(FIELD_SPEC)
    if #buf < need then return nil end
    local out = {}
    local i = 1
    for _, t in ipairs(FIELD_SPEC) do
        local name, typ = t[1], t[2]
        if typ == "U8" then out[name] = tonumber(buf[i]) or 0; i = i + 1
        elseif typ == "S8" then local v = tonumber(buf[i]) or 0; if v >= 128 then v = v - 256 end; out[name] = v; i = i + 1
        elseif typ == "U16" then out[name] = to_u16(buf[i], buf[i+1]); i = i + 2
        elseif typ == "S16" then out[name] = to_s16(buf[i], buf[i+1]); i = i + 2
        else out[name] = tonumber(buf[i]) or 0; i = i + 1 end
    end
    return out
end

function Api.buildWritePayload(data)
    data = data or {}
    local payload = {}
    for _, t in ipairs(FIELD_SPEC) do
        local name, typ = t[1], t[2]
        local val = data[name] or 0
        if typ == "U8" or typ == "S8" then payload[#payload+1] = val & 0xFF
        elseif typ == "U16" then local lo, hi = from_u16(val); payload[#payload+1] = lo; payload[#payload+1] = hi
        elseif typ == "S16" then local lo, hi = from_s16(val); payload[#payload+1] = lo; payload[#payload+1] = hi
        else payload[#payload+1] = val & 0xFF end
    end
    return payload
end

return Api
