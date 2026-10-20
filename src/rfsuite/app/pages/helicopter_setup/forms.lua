local M = {}
function M.attach(w)
  function w:n(api, key, label, lo, hi, reboot, live, divisor)
    return { kind = "number", label = label, min = lo, max = hi, divisor = divisor,
      get = function() return self.data[api][key] end,
      set = function(v) self:field(api, key, v, reboot, live) end }
  end
  function w:c(api, key, label, values, reboot, live, offset)
    offset = offset or 0
    return { kind = "choice", label = label, values = values,
      get = function() return self.data[api][key] - offset + 1 end,
      set = function(v) self:field(api, key, v + offset - 1, reboot, live) end }
  end
  function w:button(label, press, enabled) return { kind = "button", label = label, press = press, enabled = enabled } end
  function w:value(label, get) return { kind = "value", label = label, get = get } end
  function w:check(key, label)
    return { kind = "choice", label = label, values = { self.L.no, self.L.yes },
      get = function() return self.checks[key] and 2 or 1 end,
      set = function(v) self.checks[key] = v == 2 end }
  end
  function w:cardDef(title, detail, rows, enter, art)
    return { title = title, detail = detail, rows = rows, enter = enter, art = art }
  end
  function w:feature(bit, enabled)
    local f = self.data.feature_config
    if enabled then f.enabledFeatures = f.enabledFeatures | (1 << bit)
    else f.enabledFeatures = f.enabledFeatures & (~(1 << bit)) end
    self:touch("feature_config")
  end
  function w:port(label, bit)
    local ids, values = {}, {}
    for i = 1, 12 do
      local p = "port_" .. i .. "_"
      local id, mask = self.data.serial_config[p .. "identifier"], self.data.serial_config[p .. "function_mask"]
      if id and id <= 20 and (mask == 0 or (mask & bit) ~= 0) then
        ids[#ids + 1] = i; values[#values + 1] = "UART" .. (id + 1)
      end
    end
    if #ids == 0 then values[1] = self.L.noPort end
    return { kind = "choice", label = label, values = values,
      get = function()
        for n, i in ipairs(ids) do
          if (self.data.serial_config["port_" .. i .. "_function_mask"] & bit) ~= 0 then return n end
        end; return 0
      end,
      set = function(v)
        if not ids[v] then return end
        for i = 1, 12 do
          local key = "port_" .. i .. "_function_mask"
          if self.data.serial_config[key] then self.data.serial_config[key] = self.data.serial_config[key] & (~bit) end
        end
        self.data.serial_config["port_" .. ids[v] .. "_function_mask"] = bit
        self:touch("serial_config", true)
      end }
  end
  function w:input(axis, key, label, lo, hi, divisor)
    return { kind = "number", label = label, min = lo, max = hi, divisor = divisor,
      get = function() return self.data.mixer_input.inputs[axis][key] end,
      set = function(v) self.data.mixer_input.inputs[axis][key] = v; self:touch("mixer_input", false, true) end }
  end
  function w:reverse(axis)
    local r = self.data.mixer_input.inputs[axis]; r.rate = -r.rate; self:touch("mixer_input", false, true)
  end
  function w:ack(key)
    if not self.checks[key] then self.message = self.L.confirmCheck; return false end
    return true
  end
end
return M
