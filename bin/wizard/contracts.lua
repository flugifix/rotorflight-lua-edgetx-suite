-- Behavioral contracts traced to Configurator PR 491. Runs only with offline
-- fixtures; no radio, EdgeTX executable, model API or virtual FC is started.
return function(h)
  local world,load,H,L,q=h.world,h.load,h.H,h.L,h.q
  local eq,check=h.eq,h.check
  local cases={}
  local function case(id,fn)
    cases[#cases+1]=id
    fn()
  end
  local function step(w,name)
    w.commit,w.validate,w.onLive=nil,nil,nil
    local cards=load("app/pages/helicopter_setup/steps/"..name..".lua")(w)
    w.cards=cards
    return cards
  end
  local function drain(w)
    for _=1,1500 do
      h.measure("contract wakeup",function() w:tick() end);h.pump();h.advance(1)
      if w.error or w.bus:idle() then return end
    end
    check(false,"contract transport completes")
  end
  local function settle(w) w.buildRequested=nil;drain(w);w.statusAt=getTime() end
  case("SOURCE.pure-helper-golden-vectors",function()
    local vectors=assert(loadfile("bin/wizard/source_vectors.lua"))().cases
    local function same(actual,expected,prefix)
      if type(expected)~="table" then eq(actual,expected,prefix);return end
      check(type(actual)=="table",prefix.." table")
      if type(actual)~="table" then return end
      for key,value in pairs(expected) do same(actual[key],value,prefix.."/"..key) end
    end
    for i,v in ipairs(vectors) do
      local result
      if v.fn=="style" then
        result=v.args[1];H.style(result,v.args[2],v.args[3])
      elseif v.fn=="switchRange" then
        local a,b=H.switchRange(table.unpack(v.args));result={a,b}
      elseif v.fn=="moved" then
        result=H.moved(v.args[1],nil,v.args[3])
      else result=H[v.fn](table.unpack(v.args)) end
      same(result,v.expected,"SOURCE vector "..i.." "..v.fn)
    end
  end)
  case("S01.calibration-alignment",function()
    local w=world();local c=step(w,"sensors")
    w.data.status.sensor_status=0;c=step(w,"sensors")
    check(not c[1].rows[3].enabled(),"S01 missing accelerometer blocks calibration")
    w.data.status.sensor_status=1;c=step(w,"sensors")
    c[1].rows[3].press();check(w.calibrationAt==nil,"S01 preparation required")
    w.checks.unplugged,w.checks.blades=true,true;c[1].rows[3].press();settle(w)
    check(w.calibrationAt~=nil,"S01 calibration starts after ACK")
    h.advance(200)
    local status=h.api("status").parse(h.fixtures[101]);status.arming_disable_flags=(1<<16)|(1<<12)
    w:acceptStatus(status)
    check(w.calibrationAt~=nil,"S01 ongoing calibration bit blocks premature completion")
    status.arming_disable_flags=1<<16;w:acceptStatus(status)
    check(w.calibrationAt==nil and w.message==L.calibrated,"S01 calibration completes only after both calibration flags clear")
    w.trial={api="board_auto_align"};w:trialReply({state=6})
    eq(w.message,L.calibrateFirst,"S01 uncalibrated firmware diagnosis")
    w.trial={api="board_auto_align"};w:trialReply({state=2,roll_degrees=-90,pitch_degrees=0,yaw_degrees=180})
    eq(w.data.board_alignment_config.roll_degrees,-90,"S01 signed alignment")
    check(w.rebootPending and w.dirty.board_alignment_config,"S01 alignment deferred to reboot gate")
    check(not w.validate(),"S01 physical direction answer required")
  end)
  case("S02.protocol-ids-presets-feature-group",function()
    local w=world();local entries=w:receiverProtocols();local ids={}
    for _,e in ipairs(entries) do ids[e[2]]=e[1] end
    eq(ids["S.BUS2"],15,"S02 S.BUS2 wire ID")
    eq(ids["F.PORT2"],16,"S02 F.PORT2 wire ID")
    eq(ids.FBUS,17,"S02 FBUS wire ID")
    eq(ids["XBUS A"],18,"S02 XBUS A wire ID")
    eq(ids.IBUS2,19,"S02 IBUS2 wire ID")
    w.data.rx_config.serialrx_provider=9;w.data.feature_config.enabledFeatures=1<<25
    local rx=step(w,"receiver")
    eq(rx[1].rows[2].get(),0,"S02 SPI receiver does not masquerade as stored serial protocol")
    rx[1].rows[2].set(1)
    eq(w.data.feature_config.enabledFeatures,1<<3,"S02 choosing stored CRSF still changes receiver feature group")
    eq(rx[1].rows[2].get(),1,"S02 serial receiver selection readback")
    w.data.feature_config.enabledFeatures=(1<<0)|(1<<13)|(1<<14)|(1<<25)|(1<<28)
    w:serialReceiver()
    eq(w.data.feature_config.enabledFeatures,(1<<3)|(1<<28),"S02 RX feature group preserves RPM feature")
    local c=step(w,"receiver")
    for i,map in ipairs({{0,1,3,2,5,4,6,7},{0,1,3,4,2,5,6,7},{0,1,3,5,2,4,6,7},{1,2,3,5,0,4,6,7}}) do
      c[2].rows[2].set(i)
      for n,key in ipairs({"aileron","elevator","rudder","collective","throttle","aux1","aux2","aux3"}) do
        eq(w.data.rx_map[key],map[n],"S02 preset "..i.." function "..n)
      end
      eq(c[2].rows[2].get(),i,"S02 preset readback")
    end
  end)
  case("S02.port-selection",function()
    local w=world()
    w.data.serial_config.port_1_identifier=20;w.data.serial_config.port_1_function_mask=0
    w.data.serial_config.port_2_identifier=30;w.data.serial_config.port_2_function_mask=0
    w.data.serial_config.port_3_function_mask=1|64
    local row=w:port(L.port,64)
    for _,name in ipairs(row.values) do check(name~="UART21","S02 USB VCP never offered") end
    local current=row.get();row.set(current)
    eq(w.data.serial_config.port_3_function_mask,65,"S02 current port preserves shared function mask")
    local free
    for n,name in ipairs(row.values) do if name=="SOFTSERIAL1" then free=n end end
    check(free~=nil,"S02 supported soft serial name shown")
    row.set(free)
    eq(w.data.serial_config.port_2_function_mask,64,"S02 free destination gets RX function")
    eq(w.data.serial_config.port_3_function_mask,1,"S02 old RX port preserves other functions")
  end)
  case("S02.order-detection-and-throttle",function()
    local w=world();local c=step(w,"receiver")
    c[2].rows[1].press()
    local values={1500,1500,1500,1500,1500,1500,1500,1500}
    local function reply()
      local copy={};for i,v in ipairs(values) do copy[i]=v end
      w.onLive("rx_channels",{channels=copy})
    end
    reply()
    -- Collective, roll, pitch, yaw, throttle; a used channel is never reused.
    for _,channel in ipairs({3,2,4,1,5}) do
      values[channel]=2000;reply();reply()
    end
    eq(w.data.rx_map.collective,2,"S02 collective detected first")
    eq(w.data.rx_map.aileron,1,"S02 roll detected")
    eq(w.data.rx_map.elevator,3,"S02 pitch detected")
    eq(w.data.rx_map.rudder,0,"S02 yaw detected")
    eq(w.data.rx_map.throttle,4,"S02 throttle detected")
    check(w.rx.detect==nil and w.dirty.rx_map,"S02 permutation completes")
    c[4].rows[2].press();values[5]=1100;reply();values[5]=1399;reply();c[4].rows[4].press()
    check(w.message==L.travelShort,"S02 travel below 300 rejected")
    values[5]=1900;reply();c[4].rows[4].press()
    eq(w.data.rc_config.rc_min_throttle,1120,"S02 low range margin")
    eq(w.data.rc_config.rc_max_throttle,1880,"S02 high range margin")
    c[5].rows[3].press();w.data.rx_channels={channels={1500,1500,1500,1500,1030}}
    eq(c[5].rows[4].get(),L.yes,"S02 default 1041 minus deadband allows 1030")
    w.data.rx_channels.channels[5]=0
    eq(c[5].rows[4].get(),L.no,"S02 absent throttle is not low confirmation")
  end)
  case("S03.mode-status-versus-switch",function()
    local w=world();w.data.boxids.box_ids={0,53,47}
    w.data.mode_ranges.mode_ranges[1]={id=0,auxChannelIndex=0,range={start=1800,["end"]=2100}}
    w.data.mode_ranges.mode_ranges[2]={id=53,auxChannelIndex=1,range={start=1800,["end"]=2100}}
    w.data.rc={channels={1500,1500,1500,1500,1000,2000,2000}}
    w.data.status.flight_mode_flags=0
    local c=step(w,"modes")
    w.data.rx_map.aux1=4
    eq(w:channelNumber(0),5,"S03 displayed receiver channel follows RX_MAP")
    check(c[1].rows[1].get():find("CH5",1,true)~=nil,"S03 switch assignment names physical receiver channel")
    eq(c[1].rows[4].get(),L.yes,"S03 ARM shows switch position despite arming inhibit")
    eq(c[2].rows[4].get(),L.no,"S03 rescue requires actual mode flag")
    w.data.status.flight_mode_flags=2
    eq(c[2].rows[4].get(),L.yes,"S03 actual rescue mode flag")
    c[2].rows[3].press();check(w.dirty.mode_ranges,"S03 remove live write")
    eq(w.data.mode_ranges.mode_ranges[2].range.start,1500,"S03 remove disables slot")
    check(w.validate(),"S03 ARM assignment required and present")
    c[1].rows[3].press();check(not w.validate(),"S03 missing ARM blocks advance")
  end)
  case("S03.switch-settle",function()
    local w=world();w.data.boxids.box_ids={0}
    local c=step(w,"modes");c[1].rows[2].press()
    w.onLive("rc",{channels={1500,1500,1500,1500,1000,1000}})
    w.onLive("rc",{channels={1500,1500,1500,1500,1000,2000}})
    h.advance(39);w.onLive("rc",{channels={1500,1500,1500,1500,1000,2000}})
    check(w.modeListen.id~=nil,"S03 switch waits 400 ms")
    h.advance(1);w.onLive("rc",{channels={1500,1500,1500,1500,1000,2000}})
    check(w.modeListen.id==nil,"S03 settled switch assigned")
    local r=w.data.mode_ranges.mode_ranges[2]
    eq(w.data.mode_ranges.mode_ranges[1].id,1,"S03 unrelated existing mode preserved")
    eq(r.auxChannelIndex,0,"S03 AUX index starts after five controls")
    eq(r.range.start,1500,"S03 switch range midpoint")
    eq(r.range["end"],2100,"S03 switch high end margin")
    eq(w.data.mode_ranges_extra.mode_ranges_extra[2].linkedTo,0,"S03 removes previous mode linkage")
  end)
  case("S04.readback-paired-capacity",function()
    local w=world();local ranges=w.data.adjustment_ranges.adjustment_ranges
    ranges[1]=H.mapped(2,2,1000,2000,1,3)
    ranges[2]=H.gain(83,3,true);ranges[3]=H.gain(84,3,true)
    local c=step(w,"profiles")
    eq(w.profile.mode,2,"S04 existing PID-only assignment inferred")
    eq(w.profile.gain,3,"S04 existing stepped gain inferred")
    eq(w.profile.channel,2,"S04 existing profile channel inferred")
    c[1].rows[1].set(1)
    eq(H.rangeOf(ranges,1).adjChannel,2,"S04 both copies existing PID channel")
    c[1].rows[1].set(3)
    check(not H.rangeOf(ranges,1) and not H.rangeOf(ranges,2),"S04 none removes both profiles")
    for i=1,#ranges do ranges[i]=H.gain(50,0,false) end
    ranges[1].adjFunction=0
    local before=#w.bus.jobs
    w.profile.mode=1;w.profile.positions={{low=1000,high=1000},{low=2000,high=2000}}
    c[1].rows[4].press()
    eq(w.message,L.noSlots,"S04 full-table feedback")
    eq(ranges[1].adjFunction,0,"S04 full pair leaves free slot untouched")
    eq(#w.bus.jobs,before,"S04 no partial paired write")
  end)
  case("S04.switch-recording-gain-feedback",function()
    local w=world();local c=step(w,"profiles")
    c[1].rows[1].set(1);c[1].rows[2].press()
    local function rc(value) w.onLive("rc",{channels={1500,1500,1500,1500,1000,value,2012}}) end
    rc(1000);rc(2000);rc(1500);rc(1200)
    c[1].rows[4].press()
    local r=H.rangeOf(w.data.adjustment_ranges.adjustment_ranges,2)
    eq(r.adjMax,3,"S04 four positions capped at three profiles")
    eq(r.adjRange1.start,1000,"S04 full switch travel low")
    eq(r.adjRange1["end"],2000,"S04 full switch travel high")
    c[2].rows[1].set(3);c[2].rows[2].press()
    rc(2012);rc(1654)
    local gr=H.rangeOf(w.data.adjustment_ranges.adjustment_ranges,83)
    eq(gr.adjStep,5,"S04 gain buttons step 5")
    eq(gr.enaChannel,255,"S04 adjustment always enabled")
    eq(gr.adjMin,25,"S04 gain minimum")
    eq(gr.adjMax,200,"S04 gain maximum")
    w.data.rc={channels={1500,1500,1500,1500,1000,1654,2012}}
    check(c[2].rows[4].get():find("-5%%")~=nil,"S04 pressed cyclic-down feedback")
    w.data.rc.channels[6]=2012
    eq(c[2].rows[4].get(),L.none,"S04 neutral outside button windows")
  end)
  case("S05.scoped-rates-and-readback",function()
    local w=world();w.step=5
    local ranges=w.data.adjustment_ranges.adjustment_ranges
    ranges[1]=H.mapped(2,1,1000,2000,2,3);ranges[2]=H.mapped(1,1,1000,2000,2,3)
    local c=step(w,"rates");c[1].enter();settle(w)
    eq(table.concat(w.rateProfiles,","),"1,2","S05 only mapped rate profiles offered")
    check(w.rateTunings[1] and w.rateTunings[2] and not w.rateTunings[0],"S05 profiles read individually")
    check(not c[1].rows[3].enabled(),"S05 suggest only offered for three positions")
    c[1].rows[1].set(1);c[1].rows[2].set(2)
    q.sent={};w:save();settle(w)
    local writes=0;local selections={}
    for _,m in ipairs(q.sent) do
      if m.command==204 then writes=writes+1 end
      if m.command==210 then selections[#selections+1]=m.payload[1] end
    end
    eq(writes,1,"S05 only chosen profile written")
    eq(table.concat(selections,","),"129,130","S05 selected profile restored")
    check(next(w.rateStyles)==nil,"S05 chosen styles cleared after save")
    local tuning={rates_type=6,rcRates_4=100}
    for style=1,3 do
      H.style(tuning,style);eq(H.matchStyle(tuning,6),style,"S05 preset matches readback "..style)
      eq(H.collective(tuning),12.5,"S05 collective preserved")
    end
    H.style(tuning,2,4);eq(tuning.rates_type,4,"S05 pre-12.09 Actual helper")
    eq(tuning.rcRates_1,19,"S05 Actual centre rounding")
  end)
  case("S06.tail-transition-and-pin",function()
    local w=world();w.data.mixer_config.tail_rotor_mode=1;w.startTail=1
    w.data.tail_motor_output={output=1,result=0}
    local c=step(w,"swash");c[1].rows[3].set(3);w.commit()
    check(w.restoreProfile==nil,"S06 motor to bidirectional preserves custom TTA")
    eq(math.abs(w.data.mixer_input.inputs[3].rate),1000,"S06 motor yaw scale")
    w.startTail=0;w.commit()
    check(w.restoreProfile~=nil,"S06 servo-to-motor updates TTA across PID profiles")
    w.bus:cancel();w.restoreProfile=nil;w.startTail=1
    w.data.tail_motor_output={output=0,result=0};step(w,"swash");w.commit()
    -- Module write reply must confirm the requested pin, rather than ACK alone.
    local job=w.bus.jobs[#w.bus.jobs]
    job.after({output=0,result=1})
    check(w.error~=nil,"S06 refused tail pin blocks advancement")
  end)
  case("S07.servo-bands-and-reboot",function()
    local w=world();w.checks.unplugged=true
    local c=step(w,"servoType");c[1].rows[2].set(3)
    local s=w.data.servo_configurations.servos[0]
    eq(s.mid,760,"S07 narrow midpoint")
    eq(s.min,-250,"S07 narrow minimum")
    eq(s.max,250,"S07 narrow maximum")
    eq(s.rneg,250,"S07 narrow negative scale")
    eq(s.rpos,250,"S07 narrow positive scale")
    eq(s.rate,560,"S07 narrow rate")
    check(w.rebootPending,"S07 frame rate requires reboot")
    c[1].rows[2].set(2)
    eq(s.mid,1520,"S07 wide midpoint")
    eq(s.min,-700,"S07 wide minimum")
    eq(s.rpos,500,"S07 wide scale")
    s.mid=1530;c[1].rows[2].set(1)
    eq(s.mid,1530,"S07 same pulse band preserves centre")
    w.checks.unplugged=false;c[1].rows[2].set(3)
    eq(s.mid,1530,"S07 plugged servos block band change")
  end)
  case("S08.governor-feature-and-rpm",function()
    local w=world();w.data.feature_config.enabledFeatures=0;w.data.governor_config.gov_mode=3
    local c=step(w,"governor")
    eq(c[1].rows[1].get(),1,"S08 disabled feature overrides latent mode")
    c[1].rows[2].set(3)
    eq(w.data.feature_config.enabledFeatures & (1<<26),0,"S08 throttle edit never enables latent governor")
    w.data.governor_config.gov_throttle_type=1;c[1].rows[1].set(3)
    eq(w.data.governor_config.gov_throttle_type,0,"S08 leaving headspeed resets Switch throttle")
    c[1].rows[2].set(2)
    eq(w.data.governor_config.gov_throttle_type,0,"S08 unsupported Switch choice refused")
    w.data.motor_config.motor_pole_count_0=14;w.data.motor_config.motor_pwm_protocol=5;w.data.motor_config.use_dshot_telemetry=1
    check(w:fastRpm(),"S08 bidirectional DShot is fast RPM")
    w.data.motor_config.use_dshot_telemetry=0;w.data.esc_sensor_config.protocol=1
    check(not w:fastRpm(),"S08 serial ESC telemetry does not prove fast RPM")
  end)
  case("S09-S12.versioned-esc-and-ports",function()
    local w=world();local oldVersion=rfsuite.session.apiVersion
    for _,v in ipairs({{version="12.09",off=10,telem=14},{version="12.10",off=11,telem=15}}) do
      rfsuite.session.apiVersion=v.version
      local e=w:motorProtocols();eq(e[#e][1],v.off,"S09 disabled wire ID "..v.version)
      eq(#w:telemetryProtocols(),v.telem,"S12 supported telemetry protocols "..v.version)
      for _,item in ipairs(e) do check(item[1]~=4,"S09 undefined protocol never offered") end
    end
    rfsuite.session.apiVersion=oldVersion
    w.data.serial_config.port_1_function_mask=1024|1
    local c=step(w,"escTelemetry");c[1].rows[1].set(1)
    eq(w.data.serial_config.port_1_function_mask,1,"S12 telemetry off frees only its function")
    w.data.motor_config.motor_pwm_protocol=9;w:fixMotor()
    eq(w.data.esc_sensor_config.protocol,0,"S09 Castle protocol fix")
    check((w.data.feature_config.enabledFeatures & (1<<27))~=0,"S09 Castle feature remains enabled")
    check(not w:canDetect(1024),"S12 Castle has no wiring trial")
    w.data.motor_telemetry={motors={{voltage=0,temperature=0,current=0,rpm=0}}}
    eq(c[3].rows[1].get(),L.noTelemetry,"S12 zero data is missing telemetry")
    w.data.motor_telemetry.motors[1].voltage=24000
    eq(c[3].rows[1].get(),L.receiving,"S12 voltage proves reception")
  end)
  case("S10.connection-gate",function()
    local w=world();w.rebootPending=true
    step(w,"connect");check(not w.validate(),"S10 reboot requires unplugged confirmation")
    w.checks.unplugged=true;check(w.validate(),"S10 reboot gate allows confirmed unplugged state")
    w.rebootPending=nil;w.data.motor={motor_1=0,motor_2=0}
    step(w,"connect");check(not w.validate(),"S10 missing main motor blocks connection gate")
    w.data.motor.motor_1=1000;w.data.motor.motor_2=1000
    w.checks.connected,w.checks.blades=true,true
    check(w.validate(),"S10 required outputs and physical answers allow next")
  end)
  case("S11.motor-hold-and-calibration",function()
    local w=world();w.data.motor_config.motor_pwm_protocol=0;w.bladesOff=true;w.data.motor={motor_1=1000,motor_2=1000}
    w:spin(0,1);check(w.motorHold==nil,"S11 PWM calibration required")
    eq(w.message,L.calibrateEscFirst,"S11 explains blocked spin")
    w.calibratedEsc=true;w:spin(0,1)
    eq(w.motorHold.value,100,"S11 initial 10 percent command")
    eq(w.motorHold.untilAt-getTime(),1500,"S11 hold bounded to fifteen seconds")
    w:stopMotor();check(w.motorHold==nil,"S11 release stops desired output")
    w.bladesOff=false;w:spin(0,1);check(w.motorHold==nil,"S11 blades acknowledgement required")
    local c=step(w,"throttle");w.checks.blades=true;c[1].rows[2].press()
    eq(w.motorHold.value,1000,"S11 calibration high command")
    w.data.motor={motor_1=1994};check(not c[1].rows[3].enabled(),"S11 actual high output required")
    w.data.motor.motor_1=2000;check(c[1].rows[3].enabled(),"S11 actual full output enables low transition")
    c[1].rows[3].press();w.data.motor.motor_1=1000;c[1].rows[4].press()
    check(w.calibratedEsc,"S11 low calibration completion")
    w.step=10;w:navigate(11,1)
    check(not w.calibratedEsc,"S11 revisiting requires fresh ESC procedure")
  end)
  case("S13.servo-direction-centre",function()
    local w=world();local c=step(w,"servos");c[1].enter()
    eq(w.holds.servo0.value,0,"S13 centre held on entry")
    c[1].rows[1].press();eq(w.holds.servo0.value,400,"S13 +20 degree servo test")
    c[1].rows[1].press();eq(w.holds.servo0.value,0,"S13 test toggles to centre")
    local s=w.data.servo_configurations.servos[0];s.flags=6;c[1].rows[2].press()
    eq(s.flags,7,"S13 reverse preserves other flags")
    c[1].rows[1].press();c[1].rows[3].set(2)
    eq(w.holds.servo0.value,0,"S13 affirmative answer centres tested servo")
    check(w.checks.servoUp0,"S13 answer recorded")
    c[2].rows[1].set(1700)
    eq(c[2].rows[2].get(),L.checkMechanics,"S13 large offset explains mechanical remedy")
  end)
  case("S14-S15.axis-direction-and-trims",function()
    local w=world();local c=step(w,"direction");c[1].enter()
    for _,i in ipairs({1,2,4}) do eq(w.holds["mixer"..i].value,2502,"S14 passthrough axis "..i) end
    w.checks.control1=true;local before=w.data.mixer_input.inputs[1].rate;c[1].rows[2].press()
    eq(w.data.mixer_input.inputs[1].rate,-before,"S14 reverse input scale")
    check(not w.checks.control1,"S14 reversal invalidates previous physical answer")
    c=step(w,"level");c[1].enter()
    eq(c[1].rows[1].label,L.roll,"S15 first trim is roll axis")
    eq(c[1].rows[2].label,L.pitch,"S15 second trim is pitch axis")
    eq(c[1].rows[3].label,L.collective,"S15 third trim is collective axis")
    for i=1,3 do c[1].rows[i].set(i*10) end
    c[1].rows[4].press()
    for i=0,2 do eq(w.data.mixer_config["swash_trim_"..i],0,"S15 reset trim "..i) end
  end)
  case("S16.pitch-calibration-limits-fullstick",function()
    local w=world();local c=step(w,"pitch");c[2].enter()
    w.data.mixer_input.inputs[1].rate=-1000;w.data.mixer_input.inputs[2].rate=1000
    c[2].rows[1].press();eq(w.holds.mixer2.value,750,"S16 9-degree test command")
    eq(w.holds.mixer1.value,0,"S16 other cyclic axis held zero")
    c[2].rows[2].set(180);c[2].rows[3].press()
    eq(w.data.mixer_input.inputs[1].rate,-500,"S16 correction preserves roll sign")
    eq(w.data.mixer_input.inputs[2].rate,500,"S16 correction from measured pitch axis")
    c[2].rows[1].press();eq(w.holds.mixer2.value,0,"S16 test toggles off")
    c[3].rows[1].set(120)
    eq(w.data.mixer_input.inputs[1].min,-1000,"S16 cyclic negative limit")
    eq(w.data.mixer_input.inputs[2].max,1000,"S16 cyclic positive limit")
    c[3].rows[3].set(360);eq(w.data.mixer_config.swash_pitch_limit,3000,"S16 total 36 degree range")
    w.data.rc_tuning.rates_type=0
    check(not c[4].rows[1].enabled(),"S16 unsupported rate type offers no numeric full-stick edit")
  end)
  case("S17.tail-servo-and-motor-variants",function()
    local w=world();w.data.mixer_config.tail_rotor_mode=0
    local c=step(w,"tail");c[1].enter();eq(w.holds.mixer3.value,0,"S17 neutral yaw")
    c[1].rows[1].set(-100);eq(w.data.mixer_config.tail_center_trim,-417,"S17 centre trim conversion")
    c[3].rows[1].press();eq(w.holds.mixer3.value,917,"S17 +22 degree command")
    c[3].rows[1].press();eq(w.holds.mixer3.value,0,"S17 test toggles to neutral")
    c[4].rows[2].press();eq(w.holds.mixer3.value,-2500,"S17 -60 degree command")
    c[4].rows[3].set(600);eq(w.data.mixer_input.inputs[3].min,-2500,"S17 clockwise stop units")
    w.data.mixer_input.inputs[3].rate=-250;c[3].rows[3].set(500)
    eq(w.data.mixer_input.inputs[3].rate,-500,"S17 yaw calibration preserves sign")
    w:release();w.data.mixer_config.tail_rotor_mode=2;c=step(w,"tail")
    eq(#c[1].rows,4,"S17 bidirectional reverse hold available")
    w.bladesOff=true;w.data.motor={motor_1=1000,motor_2=1000};c[1].rows[4].press();eq(w.motorHold.value,-100,"S17 reverse motor command")
    c[1].rows[4].release();check(w.motorHold==nil,"S17 reverse release stops")
    eq(c[2].rows[1].max,255,"S17 idle U8 ceiling")
  end)
  case("S18-S19.physical-check-and-summary",function()
    local w=world();w.data.mixer_config.tail_rotor_mode=0;local c=step(w,"gyro")
    eq(#c,3,"S18 servo tail includes yaw gyro check")
    check(not w.validate(),"S18 gyro response never auto-confirmed")
    c[1].rows[2].press();eq(w.step,1,"S18 wrong response returns to orientation")
    w.data.mixer_config.tail_rotor_mode=2;c=step(w,"gyro")
    eq(#c,2,"S18 motor tail omits servo yaw check")
    w.data.motor_config.motor_pwm_protocol=9;c=step(w,"finish")
    eq(c[1].rows[3].get(),L.bidirectional,"S19 tail summary distinguishes bidirectional")
    eq(c[2].rows[3].get(),"Castle Link","S19 Castle telemetry is not Off")
    check(type(c[1].rows[1].get())=="string","S19 swash summary is readable")
    check(not w.validate(),"S19 final physical acknowledgement required")
  end)
  case("CORE.status-expiry-during-pending-request",function()
    local w=world();settle(w);w:hold("servo",0,400)
    w.bus:add({api="rc"});w.bus:tick()
    -- A live pending transaction cannot hide an expired arming status.
    w.statusAt=getTime()-301;w:tick()
    check(w.error~=nil and next(w.holds)==nil,"CORE stale status releases holds before bus wait")
    check(not w:usable(),"CORE stale status disables editing")
    local off=false
    for _,m in ipairs(q.messages) do if m.command==193 and m.payload[2]==209 and m.payload[3]==7 then off=true end end
    check(off,"CORE expired status queues legacy OFF")
  end)
  case("CORE.wiring-success-polling-and-teardown",function()
    local w=world();settle(w);w.data.serial_config.port_1_function_mask=64
    w.trial={api="rx_serial_trial",untilAt=getTime()+6000,due=0}
    w.bus.apis.rx_serial_trial=h.api("rx_serial_trial")
    w:trialReply({state=2,inverted=1,half_duplex=1,pin_swap=0})
    check(w.trial and w.trial.success,"CORE successful wiring remains live for inspection")
    check(not w:trialTick(),"CORE successful trial yields to live polling")
    eq(w.data.rx_config.serialrx_inverted,1,"CORE detected inversion staged")
    w:release()
    check(w.trial==nil,"CORE leaving cancels trial owner")
    local stop=false
    for _,m in ipairs(q.messages) do if m.command==0x5F12 and m.payload[1]==2 and m.client=="helicopter-cleanup" then stop=true end end
    check(stop,"CORE stop survives page transport teardown")
    w.trial={api="esc_sensor_trial",untilAt=getTime()-1,due=0};w:trialTick()
    eq(w.message,L.detectTimeout,"CORE trial deadline is explicit")
  end)
  case("VISUAL.cached-reactivity",function()
    local w=world();local diagrams=load("app/pages/helicopter_setup/diagrams.lua")
    local view=load("app/pages/helicopter_setup/view.lua")
    local function scene(name,card)
      w.cards=step(w,name);w.card=card or 1
      local job=view.new(w,{w=320,h=240},diagrams)
      while not job.done do job:step() end
      return job.children
    end
    local function signature(children)
      local parts={}
      for _,item in ipairs(children) do
        if type(item.pts)=="function" then
          for _,p in ipairs(item.pts()) do parts[#parts+1]=p[1]..","..p[2] end
        end
      end
      return table.concat(parts,";")
    end
    local s=scene("direction");w.data.rc_command={commands={-500,0,0,0,0}};local a=signature(s)
    w.data.rc_command.commands[1]=500
    check(a~=signature(s),"VISUAL command changes existing stick marker")
    s=scene("rates");w.rateStyles[w.rateProfile]=1;a=signature(s);w.rateStyles[w.rateProfile]=3
    check(a~=signature(s),"VISUAL selected style changes existing rate curve")
    s=scene("servoType");w.data.servo_configurations.servos[0].rate=50;a=signature(s)
    w.data.servo_configurations.servos[0].rate=560
    check(a~=signature(s),"VISUAL selected servo rate changes existing pulses")
    s=scene("modes");w.animationFrame=0;a=signature(s);w.animationFrame=1
    check(a~=signature(s),"VISUAL switch cue moves without a scene rebuild")
    s=scene("swash");w.data.mixer_config.main_rotor_dir=0;a=signature(s);w.data.mixer_config.main_rotor_dir=1
    check(a~=signature(s),"VISUAL rotor direction changes existing arrow")
  end)
  case("CORE.prepared-api-roundtrip",function()
    local w=world();settle(w)
    h.fixtures[0x5F13]={1,0,0,0,0,0,0,2}
    w:startTrial("board_auto_align");drain(w)
    eq(w.message,L.liftTail,"CORE canonical board API start roundtrip")
    local request=q.sent[#q.sent]
    eq(request.command,0x5F13,"CORE board command")
    eq(request.payload[1],1,"CORE explicit board START payload")
    check(request.isWrite,"CORE board START is classified as a write")
    h.fixtures[0x5F13]={2,166,255,0,0,180,0,3}
    w:trialRequest("board_auto_align",0,function(d) w:trialReply(d) end);drain(w)
    eq(w.data.board_alignment_config.roll_degrees,-90,"CORE canonical signed alignment reaches configuration")
    eq(w.data.board_alignment_config.yaw_degrees,180,"CORE canonical yaw reaches configuration")
    check(not q.sent[#q.sent].isWrite,"CORE board poll is classified as a read")
    eq(h.api("board_auto_align").parse(h.fixtures[0x5F13]).matched_samples,3,"CORE matched samples retained")
    h.fixtures[0x5F13]=nil
    w=world();settle(w);w.data.serial_config.port_1_function_mask=1024;w.data.esc_sensor_config.protocol=1
    h.fixtures[0x5F0C]={1,2,0,0,232,3,0,0,4,1}
    w:startTrial("esc_sensor_trial");drain(w)
    check(w.trial~=nil and not w.trial.success,"CORE canonical ESC running state")
    h.fixtures[0x5F0C]={2,3,1,1,208,7,5,0,4,1}
    w:trialRequest("esc_sensor_trial",0,function(d) w:trialReply(d) end);drain(w)
    check(w.trial and w.trial.success,"CORE canonical ESC success remains live")
    eq(w.data.esc_sensor_config.half_duplex,1,"CORE canonical half-duplex result applied")
    eq(w.data.esc_sensor_config.pin_swap,1,"CORE canonical pin-swap result applied")
    check(w.trialDetails:find("5 frames",1,true)~=nil,"CORE canonical frame diagnostics available in help")
    w:release();local stop=q.messages[#q.messages]
    eq(stop.command,0x5F0C,"CORE canonical ESC stop command")
    eq(stop.payload[1],2,"CORE canonical ESC cancel action")
    check(stop.isWrite,"CORE ESC cancel is classified as a write")
    h.fixtures[0x5F0C]=nil
  end)
  case("CORE.trial-state-and-diagnostics",function()
    local w=world()
    for _,api in ipairs({"board_auto_align","rx_serial_trial","esc_sensor_trial"}) do
      for _,state in ipairs({0,1,3,4,5,6}) do
        w.trial={api=api,untilAt=getTime()+6000,due=0}
        w:trialReply({state=state,comboIndex=1,elapsedMs=1200})
        if state==1 then check(w.trial~=nil,"CORE running trial retains owner")
        else check(w.trial==nil,"CORE terminal trial releases owner") end
      end
    end
    local rx=h.api("rx_serial_trial")
    check(rx.parse({1,0,1,0,1,0})==nil,"CORE short RX trial refused")
    eq(rx.parse({1,0,1,0,1,52,18}).elapsedMs,4660,"CORE RX elapsed time decoded")
    local esc=h.api("esc_sensor_trial")
    check(esc.parse({1,0,0,0,0})==nil,"CORE short ESC trial refused")
    eq(esc.parse({1,0,0,0,52,18}).elapsedMs,4660,"CORE legacy ESC elapsed time")
    local e=esc.parse({2,3,1,1,52,18,5,0,4,1})
    eq(e.frameDelta,5,"CORE optional ESC frame diagnostics")
    eq(e.comboCount,4,"CORE optional ESC combination count")
    eq(e.portOpen,1,"CORE optional ESC port-open flag")
  end)
  case("CORE.second-pass-edges",function()
    local w=world()
    w.data.tail_motor_output={output=2,result=0};w.startTail=w.data.mixer_config.tail_rotor_mode
    step(w,"swash")
    check(not w.dirty.tail_motor_output,"CORE BOTH tail output already matches either tail kind")
    w.data.servo_configurations.servo_count=22;w.data.status.servo_count=4
    w.data.serial_config.port_1_function_mask=524288
    eq(#w:servos(),4,"CORE bus servo count follows configuration block")
    check(h.api("rc_config").parse({1,0,1,0,1,0,1})==nil,"CORE truncated RC config refused")
    local parsed=h.api("rc_config").parse(h.api("rc_config").simulatorResponse)
    eq(parsed.rc_deflection,510,"CORE complete RC config positive control")
    w=world();settle(w);w.data.serial_config.port_1_function_mask=64
    w.bus.apis.rx_serial_trial=h.api("rx_serial_trial")
    local inverted=w.data.rx_config.serialrx_inverted
    w:startTrial("rx_serial_trial");w:trialReply({state=2,inverted=1-inverted,half_duplex=1,pin_swap=1})
    check(w.trial and w.trial.success,"CORE cancel test has applied trial")
    w:stopTrial(true)
    eq(w.data.rx_config.serialrx_inverted,inverted,"CORE cancel restores original inversion")
    check(not w.dirty.rx_config and not w.rebootPending,"CORE cancel restores dirty/reboot state")
    w=world();settle(w);w.data.motor_config.motor_pwm_protocol=5;w.bladesOff=true
    w.data.motor={motor_1=0,motor_2=1000};w:spin(0,1)
    check(w.motorHold==nil,"CORE disabled actual motor blocks spin despite configured output count")
    w.data.motor.motor_1=1000;w:spin(0,1);w.percent=25
    w:tick();drain(w)
    local power
    for _,m in ipairs(q.sent) do if m.command==195 and m.payload[1]==0 then power=m.payload[2]+m.payload[3]*256 end end
    eq(power,250,"CORE motor refresh follows changed power setting")
  end)
  return cases
end
