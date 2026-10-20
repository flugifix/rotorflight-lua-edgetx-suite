return function(w)
  local L, H = w.L, w.math
  w.profile = w.profile or { mode = 1, gain = 1, channel = 0, positions = {} }
  local p = w.profile
  local ranges = w.data.adjustment_ranges.adjustment_ranges
  local function writeRange(fn, range)
    local slot
    for i, r in ipairs(ranges) do if r.adjFunction == fn then slot = i; break end end
    if not slot then for i, r in ipairs(ranges) do if r.adjFunction == 0 then slot = i; break end end end
    if not slot then w.message = L.noSlots; return false end
    ranges[slot] = range
    w:action("set_adjustment_range", H.adjustPayload(slot - 1, range)); w:touch("adjustment_ranges")
    return true
  end
  local function remove(fn)
    for i, r in ipairs(ranges) do
      if r.adjFunction == fn then
        r.adjFunction = 0; w:action("set_adjustment_range", H.adjustPayload(i - 1, r)); w:touch("adjustment_ranges")
      end
    end
  end
  local function sample(v)
    for _, value in ipairs(p.positions) do if math.abs(value - v) < 150 then return end end
    if #p.positions < 3 then p.positions[#p.positions + 1] = v; table.sort(p.positions) end
  end
  w.onLive = function(api, d)
    if api ~= "rc" then return end
    if p.record then sample(d.channels[p.channel + 6] or 0) end
    if not p.listen then return end
    if getTime() > p.untilAt then p.listen = nil; w.message = L.detectTimeout; return end
    if not p.base then p.base = d.channels; return end
    local peaks = {}; for i = 6, #d.channels do peaks[i - 5] = math.abs(d.channels[i] - (p.base[i] or d.channels[i])) end
    local aux = H.moved(peaks, nil, p.listen == "profile" and 300 or p.gain == 2 and 250 or 100)
    if not aux then return end
    p.channel = aux - 1
    if p.listen == "profile" then
      p.positions, p.record = {}, true; sample(p.base[aux + 5]); sample(d.channels[aux + 5])
    else
      writeRange(83, H.gain(83, p.channel, p.gain == 3)); writeRange(84, H.gain(84, p.channel, p.gain == 3))
    end
    p.listen = nil; w.message = L.detected
  end
  local function listen(kind)
    p.listen, p.base, p.untilAt, p.record = kind, nil, getTime() + 2000, nil
    w.message = L.flick
  end
  return {
    w:cardDef(L.profiles, L.profileHint, {
      { kind = "choice", label = L.profileSwitch, values = { L.bothProfiles, L.pidOnly, L.none },
        get = function() return p.mode end,
        set = function(v) p.mode = v; if v == 3 then remove(1); remove(2) elseif v == 2 then remove(1) end end },
      w:button(L.detect, function() listen("profile") end),
      w:value(L.positions, function() return string.format("CH%d: %d", p.channel + 6, #p.positions) end),
      w:button(L.useSwitch, function()
        if #p.positions < 2 then w.message = L.twoPositions; return end
        p.record = nil
        writeRange(2, H.mapped(2, p.channel, p.positions[1], p.positions[#p.positions], 1, #p.positions))
        if p.mode == 1 then writeRange(1, H.mapped(1, p.channel, p.positions[1], p.positions[#p.positions], 1, #p.positions)) end
      end)
    }),
    w:cardDef(L.masterGain, L.gainHint, {
      { kind = "choice", label = L.method, values = { L.none, L.knob, L.buttons }, get = function() return p.gain end,
        set = function(v) p.gain = v; remove(83); remove(84) end },
      w:button(L.detect, function() if p.gain > 1 then listen("gain") end end),
      w:value(L.channel, function() return "CH" .. (p.channel + 6) end),
      w:value(L.channelCount, function() return w.data.rc and w.data.rc.channel_count or "--" end)
    }),
    w:cardDef(L.trimGuide, L.trimHint, {
      w:value(L.cyclicDown, function() return "30% / 1654 us" end),
      w:value(L.cyclicUp, function() return "40% / 1705 us" end),
      w:value(L.yawDown, function() return "50% / 1756 us" end),
      w:value(L.yawUp, function() return "60% / 1807 us" end)
    })
  }
end
