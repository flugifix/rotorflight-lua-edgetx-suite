-- Manifest for onconnect tasks (ordered)
return {
  "apiversion",
  "uid",
  "rtc",
  { name = "flight_stats", context = "widget" },
  { name = "dataflash_summary", context = "widget" },
  { name = "battery_config", context = "both" },
  { name = "governor_config", context = "both" },
  { name = "esc_sensor_config", context = "tool" },
  { name = "smartfuel_config", context = "both" },
  { name = "name", context = "both" },
  -- The pilot config is read BEFORE the name is synchronised, because from MSP API 12.09 the
  -- flight controller's own MODEL_SET_NAME bit is what decides whether it is synchronised at
  -- all. One read serves both tasks; the order is what makes the flag available in time.
  { name = "model_params_sync", context = "both" },
  -- After `name`, which fills session.modelName, and after the read above.
  { name = "model_name_sync", context = "both" },
}
