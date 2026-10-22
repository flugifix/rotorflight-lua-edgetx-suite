-- On 64-bit Lua every U32 round-trips; 2^53+1 exercises float rounding before byte extraction.
-- Byte-table vectors cover values that fail on EdgeTX's 32-bit-integer, single-precision build.
local root=arg[1] or "src/rfsuite/tasks/msp/api/"
local count=0
local function api(name) return assert(loadfile(root .. name .. ".lua"))() end
local function eq(a,b,label) count=count+1;assert(a==b,label .. ": " .. tostring(a) .. " / " .. tostring(b)) end
local function bytes(a,b,label)
    eq(#a,#b,label .. " length")
    for i,v in ipairs(b) do eq(a[i],v,label .. " byte " .. i) end
    for i,v in ipairs(a) do eq(math.type(v),"integer",label .. " byte type " .. i) end
end
local function inject(buf,pos,little,big)
    local out={};for i,v in ipairs(buf) do out[i]=v end
    for i=1,4 do out[pos+i-1]=little[big and 5-i or i] end
    return out
end
local lengths={U8=1,S8=1,U16=2,S16=2,U24=3,U32=4,U64=8,U120=15,U128=16}
local vectors={
    {0x1E,0xAA,0x00,0x00}, {0xFF,0xFF,0xFF,0x00}, {0x01,0x00,0x00,0x01},
    {0x56,0x04,0x16,0x03}, {0xFF,0xFF,0xFF,0x7F}, {0xEF,0xBE,0xAD,0xDE},
    {0xFF,0xFF,0xFF,0xFF}
}
local inputs={
    {12.5,{0x0C,0,0,0}}, {-3.7,{0xFC,0xFF,0xFF,0xFF}}, {"123",{0x7B,0,0,0}},
    {0/0,{0,0,0,0}}, {math.huge,{0,0,0,0}}, {-math.huge,{0,0,0,0}}
}
for _,name in ipairs({"yge","scorpion","omp","xdfly","ztw"}) do
    local mod=api("esc_parameters_" .. name)
    local fixture=mod.simulatorResponse
    bytes(mod.buildWritePayload(assert(mod.parse(fixture))),fixture,name .. " fixture")
    local pos=1
    local fields=0
    for _,f in ipairs(mod.fields) do
        local len=assert(lengths[f[2]],"unknown type " .. f[2])
        local big=false;for _,v in ipairs(f) do if v=="big" then big=true end end
        if f[2]=="U32" then
            fields=fields+1
            local label=name .. " " .. f[1]
            for i,little in ipairs(vectors) do
                local buf=inject(fixture,pos,little,big)
                bytes(mod.buildWritePayload(assert(mod.parse(buf))),buf,label .. " vector " .. i)
            end
            local function pack(value,expected,suffix)
                local data=assert(mod.parse(fixture))
                data[f[1]]=value
                bytes(mod.buildWritePayload(data),inject(fixture,pos,expected,big),label .. suffix)
            end
            if math.maxinteger > 2^53 then
                pack((1 << 53)+1,{1,0,0,0}," integer 2^53+1")
            end
            for i,input in ipairs(inputs) do pack(input[1],input[2]," input " .. i) end
        end
        pos=pos+len
    end
    eq(pos-1,#fixture,name .. " field lengths")
    eq(fields>0,true,name .. " U32 coverage")
end
print("ESC parameter byte packing: " .. count .. " assertions passed")
