local M = {}
local AUX_KEYS={"aux1","aux2","aux3"}
function M.attach(w)
  M.protocols(w)
  function w:channelNumber(aux)
    local raw=aux<3 and self.data.rx_map[AUX_KEYS[aux+1]] or nil
    return raw and raw+1 or aux+6
  end
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
      if id and id ~= 20 and (mask == 0 or (mask & bit) ~= 0) then
        ids[#ids + 1] = i; values[#values + 1] = id==30 and "SOFTSERIAL1" or id==31 and "SOFTSERIAL2" or "UART" .. (id + 1)
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
        if (self.data.serial_config["port_"..ids[v].."_function_mask"] & bit) ~= 0 then return end
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
  function w:invertInput(axis)
    local r = self.data.mixer_input.inputs[axis]; r.rate = -r.rate; self:touch("mixer_input", false, true)
  end
  function w:ack(key)
    if not self.checks[key] then self.message = self.L.confirmCheck; return false end
    return true
  end
end
-- Explicit wire IDs keep sparse/versioned protocol menus safe.
function M.protocols(w)
  function w:apiAtLeast(minor)
    local major, value = string.match(tostring(self:session().apiVersion or ""), "(%d+)%.(%d+)")
    return tonumber(major or 0) > 12 or tonumber(major or 0) == 12 and tonumber(value or 0) >= minor
  end
  function w:enum(api, key, label, entries, reboot)
    local values = {}; for i, e in ipairs(entries) do values[i] = e[2] end
    return { kind = "choice", label = label, values = values,
      get = function()
        for i,e in ipairs(entries) do if e[1] == self.data[api][key] then return i end end
        return 0
      end,
      set = function(v) if entries[v] then self:field(api, key, entries[v][1], reboot) end end }
  end
  function w:receiverProtocols()
    local e = {{9,"CRSF / ELRS"},{2,"S.BUS"},{0,"DSM/1024"},{1,"DSM/2048"},{10,"SRXL"},{13,"SRXL2"},
      {14,"GHOST"},{3,"SUMD"},{4,"SUMH"},{7,"IBUS"},{5,"XBUS B"},{6,"XBUS RJ01"},{8,"Jeti EXBUS"},{12,"F.PORT"}}
    if self:apiAtLeast(7) then
      e[#e+1]={15,"S.BUS2"}; e[#e+1]={16,"F.PORT2"}; e[#e+1]={17,"FBUS"}
    end
    if self:apiAtLeast(8) then e[#e+1]={18,"XBUS A"} end
    if self:apiAtLeast(9) then e[#e+1]={19,"IBUS2"} end
    return e
  end
  function w:motorProtocols()
    local e = {{0,"PWM"},{1,"ONESHOT125"},{2,"ONESHOT42"},{3,"MULTISHOT"},
      {5,"DSHOT150"},{6,"DSHOT300"},{7,"DSHOT600"},{8,"PROSHOT"}}
    local disabled = 9
    if self:apiAtLeast(8) then e[#e+1]={9,"CASTLE"}; disabled=10 end
    if self:apiAtLeast(10) then e[#e+1]={10,"SRXL2"}; disabled=11 end
    e[#e+1]={disabled,self.L.off}; return e
  end
  function w:telemetryProtocols()
    local names = {self.L.off,"BLHeli32","Hobbywing V4","Hobbywing V5","Scorpion","Kontronik","OMPHobby", "ZTW",
      "APD","OpenYGE","FLYROTOR","Graupner","XDFLY"}
    if self:apiAtLeast(9) then names[#names+1]="FBUS" end
    if self:apiAtLeast(10) then names[#names+1]="SRXL2" end
    local e={}; for i,n in ipairs(names) do e[i]={i-1,n} end; return e
  end
end

return M
