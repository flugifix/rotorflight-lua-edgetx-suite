-- Offline byte-vector checks; also runs on Lua 5.3 built with LUA_32BITS.
-- No EdgeTX globals are needed by these three modules.
local root = arg[1] or "src/rfsuite/"
local count = 0
local function module(path) return assert(loadfile(root .. path .. ".lua"))() end
local function eq(a,b,label)
  count=count+1
  assert(a==b,label .. ": " .. tostring(a) .. " / " .. tostring(b))
end
local function upvalue(fn,name)
  for i=1,math.huge do
    local key,value=debug.getupvalue(fn,i)
    if key==name then return value,i end
    assert(key,"missing upvalue " .. name)
  end
end
local yge=module("app/pages/setup/esc_motors/esc_tools/escmfg/yge/init")
local serials={
  {{0x1E,0xAA,0,0},"43550"},
  {{0x80,0x96,0x98,0},"10000000"},
  {{0xFE,0xFF,0xFF,0xFF},"4294967294"},
  {{0,0,0,0},""}
}
for _,case in ipairs(serials) do
  local buffer={}
  for i,v in ipairs(case[1]) do buffer[30+i]=v end
  eq(yge.getEscVersion(buffer),case[2],"YGE serial " .. case[2])
end
local formatUInt=upvalue(yge.getEscVersion,"formatUInt")
local signed=math.tointeger(0xFFFFFFFE - 0x100000000)
eq(signed,-2,"signed int32 input")
eq(formatUInt(signed),"4294967294","signed int32 formatting")

-- Compare firmware output to the original float assembly on the current numeric build.
local getUInt,getUIntIndex=upvalue(yge.getEscFirmware,"getUInt")
for _,little in ipairs({{0,0,0,0},{0xA0,0x86,1,0},{0xFF,0xFF,0xFF,0x7F},
  {0,0,0,0x80},{0x81,0,0,0xC0},{0xFE,0xFF,0xFF,0xFF}}) do
  local buffer={}
  local raw=0
  for i,v in ipairs(little) do buffer[26+i]=v;raw=raw+v*(256^(i-1)) end
  local expected=raw~=0 and string.format("%.5f",raw/100000) or ""
  eq(yge.getEscFirmware(buffer),expected,"YGE firmware")
  -- Exercise the signed-int32 firmware path even on a 64-bit desktop interpreter.
  local signed=little[1] | (little[2]<<8) | (little[3]<<16) | ((little[4]&0x7F)<<24)
  if little[4]>=0x80 then signed=signed+(-2147483647-1) end
  debug.setupvalue(yge.getEscFirmware,getUIntIndex,function() return signed end)
  eq(yge.getEscFirmware(buffer),expected,"YGE firmware with int32 input")
  debug.setupvalue(yge.getEscFirmware,getUIntIndex,getUInt)
end

local vectors={
  {0x01020304,{4,3,2,1}},
  {0x00FFFFFF,{255,255,255,0}},
  {0x7FFFFFFF,{255,255,255,127}},
  {0x12345678,{120,86,52,18}},
  {-2,{254,255,255,255}},
  {16909060.0,{4,3,2,1}},
  {12.5,{12.5,0,0,0}}
}
for _,name in ipairs({"rx_config","serial_config"}) do
  local api=module("tasks/msp/api/" .. name)
  local data=assert(api.parse(api.simulatorResponse))
  local field,pos="rx_spi_id",9
  if name=="serial_config" then data={};field,pos="function_mask",2 end
  for _,case in ipairs(vectors) do
    data[field]=case[1]
    local payload=api.buildWritePayload(data)
    for i,v in ipairs(case[2]) do
      eq(payload[pos+i-1],v,name .. " byte " .. i)
      if math.tointeger(case[1]) then eq(math.type(payload[pos+i-1]),"integer",name .. " byte type " .. i) end
    end
  end
end
print("YGE serial and U32 packing: " .. count .. " assertions passed")
