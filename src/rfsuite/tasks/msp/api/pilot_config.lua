-- EdgeTX MSP API: pilot_config (ported from Ethos)

local Api = {
  command = 12,
  writeCommand = 13,
  -- Fourteen bytes: model_id, three (type, int16 value) parameters, and the model_flags word.
  -- The eleven that stood here were the ten of the pre-12.09 struct plus one stray, so the
  -- flags could not be exercised in the simulator at all -- a page reading them would have got
  -- the short-buffer branch on every simulated read and shown the flags as absent.
  simulatorResponse = {3, 0, 44, 1, 0, 20, 0, 20, 0, 0, 30, 1, 0, 0, 0}
}

-- The two model_flags bits, from the firmware's own `src/main/pg/pilot.h`:
--
--     MODEL_SET_NAME = 0,     // Set the name of the model on the radio
--     MODEL_TELL_CAPACITY     // Announce the model battery capacity left on the radio
--
-- They are what a flight controller running API 12.09 or later uses to say which radio-side
-- features this model wants. Below that version the word is not in the message at all.
Api.FLAG_SET_NAME = 0
Api.FLAG_TELL_CAPACITY = 1

--- Is a bit set in a flags word? Returns nil when there is no word, which is a different answer
--- from false and the callers depend on the difference: `nil` means the flight controller never
--- told us, and a radio-side setting is then the only thing that can decide.
function Api.flagSet(flags, bit)
  if type(flags) ~= "number" then return nil end
  return (flags >> bit) & 1 == 1
end

function Api.withFlag(flags, bit, on)
  flags = tonumber(flags) or 0
  if on then
    return flags | (1 << bit)
  end
  return flags & ~(1 << bit)
end

local function u16_from_bytes(lo, hi)
  lo = tonumber(lo) or 0
  hi = tonumber(hi) or 0
  return ((hi & 0xFF) << 8) | (lo & 0xFF)
end

-- The parameter values are int16_t on the flight controller, so the top bit is a sign and not a
-- magnitude. Read unsigned, a value of -1 arrives as 65535 and anything acting on it acts on a
-- number the pilot never set.
local function s16_from_bytes(lo, hi)
  local v = u16_from_bytes(lo, hi)
  if v >= 0x8000 then
    return v - 0x10000
  end
  return v
end

local function bytes_from_u16(v)
  v = math.floor(tonumber(v) or 0) & 0xFFFF
  return v & 0xFF, (v >> 8) & 0xFF
end

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  if #buf < 7 then return nil end
  local i = 1
  local out = {}
  out.model_id = tonumber(buf[i]); i = i + 1
  out.model_param1_type = tonumber(buf[i]); i = i + 1
  out.model_param1_value = s16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.model_param2_type = tonumber(buf[i]); i = i + 1
  out.model_param2_value = s16_from_bytes(buf[i], buf[i+1]); i = i + 2
  out.model_param3_type = tonumber(buf[i]); i = i + 1
  out.model_param3_value = s16_from_bytes(buf[i], buf[i+1]); i = i + 2
  -- API 12.09 and later append the flags word. An older flight controller simply stops here,
  -- and `model_flags` is then nil rather than 0 -- see Api.flagSet for why that matters.
  if #buf >= i + 3 then
    out.model_flags = (tonumber(buf[i]) or 0)
      | ((tonumber(buf[i+1]) or 0) << 8)
      | ((tonumber(buf[i+2]) or 0) << 16)
      | ((tonumber(buf[i+3]) or 0) << 24)
  end
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  local function push(v) p[#p+1] = v end
  push(data.model_id or 0)
  push(data.model_param1_type or 0)
  local lo, hi = bytes_from_u16(data.model_param1_value or 300)
  push(lo); push(hi)
  push(data.model_param2_type or 0)
  lo, hi = bytes_from_u16(data.model_param2_value or 20)
  push(lo); push(hi)
  push(data.model_param3_type or 0)
  lo, hi = bytes_from_u16(data.model_param3_value or 7680)
  push(lo); push(hi)
  -- The flags word goes back only when there is one to send. Writing a zero word to a flight
  -- controller that has no such field would make the message four bytes too long; writing one
  -- to a flight controller that HAS the field, when the read never produced it, would clear
  -- both bits without anybody asking for that.
  if data.model_flags ~= nil then
    local f = math.floor(tonumber(data.model_flags) or 0)
    push(f & 0xFF)
    push((f >> 8) & 0xFF)
    push((f >> 16) & 0xFF)
    push((f >> 24) & 0xFF)
  end
  return p
end

return Api
