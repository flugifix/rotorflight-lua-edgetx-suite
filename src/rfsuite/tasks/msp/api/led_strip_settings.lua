-- EdgeTX MSP API: led_strip_settings (ported from Ethos)

local Api = {
  command = 150,
  writeCommand = 151,
  simulatorResponse = {
    0, -- ledstrip_beacon_armed_only
    0, -- ledstrip_beacon_color
    50, -- ledstrip_beacon_percent
    232, 3, -- ledstrip_beacon_period_ms (1000)
    232, 3, -- ledstrip_blink_period_ms (1000)
    100, -- ledstrip_brightness
    0, -- ledstrip_fade_rate
    0, -- ledstrip_flicker_rate
    0, -- ledstrip_grb_rgb
    0, -- ledstrip_profile
    0, -- ledstrip_race_color
    0, -- ledstrip_visual_beeper
    0  -- ledstrip_visual_beeper_color
  }
}

local function to_u16(lo, hi)
  lo = tonumber(lo) or 0
  hi = tonumber(hi) or 0
  return ((hi & 0xFF) << 8) | (lo & 0xFF)
end

local function from_u16(v)
  v = math.floor(tonumber(v) or 0) & 0xFFFF
  return v & 0xFF, (v >> 8) & 0xFF
end

function Api.parse(buf)
  if type(buf) ~= "table" then return nil end
  if #buf < 13 then return nil end
  local i = 1
  local out = {}
  out.ledstrip_beacon_armed_only = tonumber(buf[i]); i = i + 1
  out.ledstrip_beacon_color = tonumber(buf[i]); i = i + 1
  out.ledstrip_beacon_percent = tonumber(buf[i]); i = i + 1
  out.ledstrip_beacon_period_ms = to_u16(buf[i], buf[i+1]); i = i + 2
  out.ledstrip_blink_period_ms = to_u16(buf[i], buf[i+1]); i = i + 2
  out.ledstrip_brightness = tonumber(buf[i]); i = i + 1
  out.ledstrip_fade_rate = tonumber(buf[i]); i = i + 1
  out.ledstrip_flicker_rate = tonumber(buf[i]); i = i + 1
  out.ledstrip_grb_rgb = tonumber(buf[i]); i = i + 1
  out.ledstrip_profile = tonumber(buf[i]); i = i + 1
  out.ledstrip_race_color = tonumber(buf[i]); i = i + 1
  out.ledstrip_visual_beeper = tonumber(buf[i]); i = i + 1
  out.ledstrip_visual_beeper_color = tonumber(buf[i]); i = i + 1
  return out
end

function Api.buildWritePayload(data)
  data = data or {}
  local p = {}
  local function push(v) p[#p+1] = v end
  push(data.ledstrip_beacon_armed_only or 0)
  push(data.ledstrip_beacon_color or 0)
  push(data.ledstrip_beacon_percent or 50)
  local lo, hi = from_u16(data.ledstrip_beacon_period_ms or 1000); push(lo); push(hi)
  lo, hi = from_u16(data.ledstrip_blink_period_ms or 1000); push(lo); push(hi)
  push(data.ledstrip_brightness or 100)
  push(data.ledstrip_fade_rate or 0)
  push(data.ledstrip_flicker_rate or 0)
  push(data.ledstrip_grb_rgb or 0)
  push(data.ledstrip_profile or 0)
  push(data.ledstrip_race_color or 0)
  push(data.ledstrip_visual_beeper or 0)
  push(data.ledstrip_visual_beeper_color or 0)
  return p
end

return Api
