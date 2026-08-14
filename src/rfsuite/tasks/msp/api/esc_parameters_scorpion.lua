-- Ported ESC_PARAMETERS_SCORPION -> esc_parameters_scorpion.lua
local Api = {
    command = 217,
    writeCommand = 218,
    mspSignature = 0x53,
    mspHeaderBytes = 2
}

local FIELD_SPEC = {
    {"esc_signature","U8"}, {"esc_command","U8"}, {"escinfo_1","U8"}, {"escinfo_2","U8"}, {"escinfo_3","U8"},
    {"escinfo_4","U8"}, {"escinfo_5","U8"}, {"escinfo_6","U8"}, {"escinfo_7","U8"}, {"escinfo_8","U8"},
    {"escinfo_9","U8"}, {"escinfo_10","U8"}, {"escinfo_11","U8"}, {"escinfo_12","U8"}, {"escinfo_13","U8"},
    {"escinfo_14","U8"}, {"escinfo_15","U8"}, {"escinfo_16","U8"}, {"escinfo_17","U8"}, {"escinfo_18","U8"},
    {"escinfo_19","U8"}, {"escinfo_20","U8"}, {"escinfo_21","U8"}, {"escinfo_22","U8"}, {"escinfo_23","U8"},
    {"escinfo_24","U8"}, {"escinfo_25","U8"}, {"escinfo_26","U8"}, {"escinfo_27","U8"}, {"escinfo_28","U8"},
    {"escinfo_29","U8"}, {"escinfo_30","U8"}, {"escinfo_31","U8"}, {"escinfo_32","U8"},
    {"esc_mode","U16"}, {"bec_voltage","U16"}, {"rotation","U16"}, {"telemetry_protocol","U16"},
    {"protection_delay","U16"}, {"min_voltage","U16"}, {"max_temperature","U16"}, {"max_current","U16"},
    {"cutoff_handling","U16"}, {"max_used","U16"}, {"motor_startup_sound","U16"}, {"padding_1","U16"},
    {"padding_2","U16"}, {"padding_3","U16"}, {"soft_start_time","U16"}, {"runup_time","U16"},
    {"bailout","U16"}, {"gov_proportional","U32"}, {"gov_integral","U32"}
}

local SIM_RESPONSE = {
    83, -- esc_signature
    128, -- esc_command
    84,114,105,98,117,110,117,115,32,69,83,67,45,54,83,45,56,48,65,0,0,0,0,0,0,0,0,0,0,0,4,0,
    3,0, 3,0, 1,0, 3,0, 136,19, 22,3, 16,39, 64,31, 136,19, 0,0, 1,0, 7,2, 0,6, 63,0, 160,15, 64,31, 208,7,
    100,0,0,0, 200,0,0,0
}

local TYPE_LEN = {U8=1,S8=1,U16=2,S16=2,U24=3,U32=4,U64=8,U120=15,U128=16}

local function has_big_flag(field)
    for _, v in ipairs(field) do if v == "big" then return true end end
    return false
end

local function read_unsigned(buf,pos,len,big)
    local v = 0
    if big then
        for i=0,len-1 do v = v*256 + (tonumber(buf[pos+i]) or 0) end
    else
        local mul = 1
        for i=0,len-1 do v = v + (tonumber(buf[pos+i]) or 0) * mul; mul = mul * 256 end
    end
    return v
end

local function read_signed(buf,pos,len,big)
    local v = read_unsigned(buf,pos,len,big)
    local max = 2^(len*8)
    local half = 2^(len*8-1)
    if v >= half then v = v - max end
    return v
end

local function bytes_to_string(buf,pos,len)
    local chars={}
    for i=0,len-1 do chars[#chars+1]=string.char(tonumber(buf[pos+i]) or 0) end
    local s=table.concat(chars)
    s=string.gsub(s, '%z+$','')
    s=string.gsub(s, '%s+$','')
    return s
end

local function pack_unsigned(v,len,big)
    v = tonumber(v) or 0
    local out={}
    if big then for i=len-1,0,-1 do out[#out+1]=math.floor(v/(256^i))%256 end
    else for i=0,len-1 do out[#out+1]=math.floor(v/(256^i))%256 end end
    return out
end

local function pack_string(s,len)
    s=s or ''
    local out={}
    for i=1,len do out[#out+1]=string.byte(s, i) or 0 end
    return out
end

Api.fields = FIELD_SPEC
Api.simulatorResponse = SIM_RESPONSE

function Api.parse(buf)
    if type(buf)~='table' then return nil end
    local pos=1
    local out={}
    for _, f in ipairs(FIELD_SPEC) do
        local name, typ = f[1], f[2]
        local len = TYPE_LEN[typ] or 1
        local big = has_big_flag(f)
        if typ=='U120' or typ=='U128' then out[name]=bytes_to_string(buf,pos,len); pos=pos+len
        elseif string.sub(typ, 1, 1)=='S' then out[name]=read_signed(buf,pos,len,big); pos=pos+len
        else out[name]=read_unsigned(buf,pos,len,big); pos=pos+len end
    end
    return out
end

function Api.buildWritePayload(data)
    data = data or {}
    local payload={}
    for _, f in ipairs(FIELD_SPEC) do
        local name, typ = f[1], f[2]
        local len = TYPE_LEN[typ] or 1
        local big = has_big_flag(f)
        local v = data[name]
        if typ=='U120' or typ=='U128' then local b=pack_string(v,len); for _,x in ipairs(b) do payload[#payload+1]=x end
        else local b=pack_unsigned(v or 0,len,big); for _,x in ipairs(b) do payload[#payload+1]=x end end
    end
    return payload
end

return Api
