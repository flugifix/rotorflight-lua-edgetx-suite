-- EdgeTX MSP API: ESC_PARAMETERS_AM32
-- Ported to EdgeTX schema (Api table + parse)
-- Note: This is a simple field-mapping port. Special normalization/encoding is omitted for brevity.

local Api = {
  command = 217, -- MSP_ESC_PARAMETERS_AM32
  writeCommand = 218, -- MSP_SET_ESC_PARAMETERS_AM32
  simulatorResponse = {
    194,64,1,3,1,2,19,50,1,0,10,100,0,100,0,255,255,255,255,0,0,0,0,0,1,26,16,50,12,24,0,1,5,0,128,128,128,50,0,50,0,0,10,10,5,145,102,7,1,0
  },
}

function Api.parse(buf)
  if type(buf) ~= "table" or #buf < 51 then return nil end
  return {
    esc_signature = buf[1] or 0,
    esc_command = buf[2] or 0,
    reserved_0 = buf[3] or 0,
    eeprom_version = buf[4] or 0,
    reserved_1 = buf[5] or 0,
    version_major = buf[6] or 0,
    version_minor = buf[7] or 0,
    max_ramp = buf[8] or 0,
    minimum_duty_cycle = buf[9] or 0,
    disable_stick_calibration = buf[10] or 0,
    absolute_voltage_cutoff = buf[11] or 0,
    current_p = buf[12] or 0,
    current_i = buf[13] or 0,
    current_d = buf[14] or 0,
    active_brake_power = buf[15] or 0,
    reserved_eeprom_3_0 = buf[16] or 0,
    reserved_eeprom_3_1 = buf[17] or 0,
    reserved_eeprom_3_2 = buf[18] or 0,
    reserved_eeprom_3_3 = buf[19] or 0,
    motor_direction = buf[20] or 0,
    bidirectional_mode = buf[21] or 0,
    sinusoidal_startup = buf[22] or 0,
    complementary_pwm = buf[23] or 0,
    variable_pwm_frequency = buf[24] or 0,
    stuck_rotor_protection = buf[25] or 0,
    timing_advance = buf[26] or 0,
    pwm_frequency = buf[27] or 0,
    startup_power = buf[28] or 0,
    motor_kv = buf[29] or 0,
    motor_poles = buf[30] or 0,
    brake_on_stop = buf[31] or 0,
    stall_protection = buf[32] or 0,
    beep_volume = buf[33] or 0,
    interval_telemetry = buf[34] or 0,
    servo_low_threshold = buf[35] or 0,
    servo_high_threshold = buf[36] or 0,
    servo_neutral = buf[37] or 0,
    servo_dead_band = buf[38] or 0,
    low_voltage_cutoff = buf[39] or 0,
    low_voltage_threshold = buf[40] or 0,
    rc_car_reversing = buf[41] or 0,
    use_hall_sensors = buf[42] or 0,
    sine_mode_range = buf[43] or 0,
    brake_strength = buf[44] or 0,
    running_brake_level = buf[45] or 0,
    temperature_limit = buf[46] or 0,
    current_limit = buf[47] or 0,
    sine_mode_power = buf[48] or 0,
    esc_protocol = buf[49] or 0,
    auto_advance = buf[50] or 0
  }
end

function Api.buildWritePayload(data)
  local payload = {}
  for i, k in ipairs({
    "esc_signature","esc_command","reserved_0","eeprom_version","reserved_1","version_major","version_minor","max_ramp","minimum_duty_cycle","disable_stick_calibration","absolute_voltage_cutoff","current_p","current_i","current_d","active_brake_power","reserved_eeprom_3_0","reserved_eeprom_3_1","reserved_eeprom_3_2","reserved_eeprom_3_3","motor_direction","bidirectional_mode","sinusoidal_startup","complementary_pwm","variable_pwm_frequency","stuck_rotor_protection","timing_advance","pwm_frequency","startup_power","motor_kv","motor_poles","brake_on_stop","stall_protection","beep_volume","interval_telemetry","servo_low_threshold","servo_high_threshold","servo_neutral","servo_dead_band","low_voltage_cutoff","low_voltage_threshold","rc_car_reversing","use_hall_sensors","sine_mode_range","brake_strength","running_brake_level","temperature_limit","current_limit","sine_mode_power","esc_protocol","auto_advance"
  }) do
    payload[i] = tonumber(data[k]) or 0
  end
  return payload
end

return Api
