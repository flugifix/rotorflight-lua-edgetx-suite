
local Api = {
    command = 158,
    name = "experimental",
    simulatorResponse = {
        255, 10, 60, 200, 20, 255, 6, 10,
        20, 40, 255, 6, 10, 20, 20, 20
    },
    fields = {
        { name = "exp_uint1", type = "U8" },
        { name = "exp_uint2", type = "U8" },
        { name = "exp_uint3", type = "U8" },
        { name = "exp_uint4", type = "U8" },
        { name = "exp_uint5", type = "U8" },
        { name = "exp_uint6", type = "U8" },
        { name = "exp_uint7", type = "U8" },
        { name = "exp_uint8", type = "U8" },
        { name = "exp_uint9", type = "U8" },
        { name = "exp_uint10", type = "U8" },
        { name = "exp_uint11", type = "U8" },
        { name = "exp_uint12", type = "U8" },
        { name = "exp_uint13", type = "U8" },
        { name = "exp_uint14", type = "U8" },
        { name = "exp_uint15", type = "U8" },
        { name = "exp_uint16", type = "U8" }
    }
}

function Api.parse(buf)
    if type(buf) ~= "table" or #buf < 16 then return nil end
    local out = {}
    for i, field in ipairs(Api.fields) do
        out[field.name] = tonumber(buf[i]) or 0
    end
    return out
end

return Api
